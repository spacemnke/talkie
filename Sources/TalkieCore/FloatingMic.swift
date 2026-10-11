import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The mic that drops out of the menu bar when a line opens and floats above every app.
/// Coordinates are the overlay's: origin at the top left of the screen, y pointing down.
public struct FloatingMic: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Tucked into the menu bar icon.
        case hidden
        case dropping
        case floating
        case dragging
        /// Winding back up into the menu bar.
        case retracting
    }

    public var mode: Mode = .hidden
    public var position: CGPoint = .zero
    public var velocity: CGVector = .zero
    /// Degrees. The mic tilts in the direction it moves.
    public var angle: CGFloat = 0
    public var angularVelocity: CGFloat = 0
    public var scale: CGFloat = 1
    /// Where you last left it, as a fraction of the bounds, so it comes back there next call.
    public var home: CGPoint?
    public var flung = false

    public init() {}

    public var isVisible: Bool { mode != .hidden }

    public func clamped(_ p: CGPoint, bounds: CGRect, size: CGSize) -> CGPoint {
        CGPoint(
            x: clamp(p.x, bounds.minX + size.width / 2 + 4, bounds.maxX - size.width / 2 - 4),
            y: clamp(p.y, bounds.minY + size.height / 2 + 6, bounds.maxY - size.height / 2 - 4)
        )
    }

    public func homePoint(anchor: CGPoint, bounds: CGRect, size: CGSize) -> CGPoint {
        if let h = home {
            return clamped(CGPoint(x: bounds.minX + h.x * bounds.width, y: bounds.minY + h.y * bounds.height), bounds: bounds, size: size)
        }
        // First time: just below and left of the menu bar icon.
        return clamped(CGPoint(x: anchor.x - size.width * 0.45, y: bounds.minY + 26 + size.height / 2), bounds: bounds, size: size)
    }

    public mutating func drop(from anchor: CGPoint) {
        guard mode == .hidden || mode == .retracting else { return }
        if mode == .hidden {
            position = CGPoint(x: anchor.x, y: anchor.y + 12)
            velocity = .zero
            scale = 0.2
        }
        mode = .dropping
    }

    public mutating func stow() {
        guard mode != .hidden && mode != .retracting else { return }
        mode = .retracting
        flung = false
    }

    public mutating func beginDrag() {
        mode = .dragging
        scale = 1
    }

    public mutating func drag(to point: CGPoint, bounds: CGRect, size: CGSize) {
        let p = clamped(point, bounds: bounds, size: size)
        velocity = CGVector(dx: velocity.dx * 0.4 + (p.x - position.x) * 0.6, dy: velocity.dy * 0.4 + (p.y - position.y) * 0.6)
        position = p
    }

    public mutating func endDrag() {
        guard mode == .dragging else { return }
        mode = .floating
        flung = true
    }

    public mutating func step(anchor: CGPoint, bounds: CGRect, size: CGSize, reduceMotion: Bool) {
        switch mode {
        case .hidden:
            return
        case .dropping:
            let h = homePoint(anchor: anchor, bounds: bounds, size: size)
            if reduceMotion {
                position = h
                scale = 1
                mode = .floating
            } else {
                Spring.step(&position, &velocity, toward: h, k: 0.07, damping: 0.83)
                scale += (1 - scale) * 0.2
                if position.distance(to: h) < 0.8 && velocity.length < 0.2 {
                    mode = .floating
                    velocity = .zero
                    scale = 1
                }
            }
        case .retracting:
            if !reduceMotion {
                Spring.step(&position, &velocity, toward: anchor, k: 0.16, damping: 0.68)
                scale += (0.15 - scale) * 0.22
            }
            if reduceMotion || position.distance(to: anchor) < 8 {
                mode = .hidden
                velocity = .zero
                angle = 0
                angularVelocity = 0
                return
            }
        case .floating:
            position.x += velocity.dx
            position.y += velocity.dy
            velocity.dx *= 0.92
            velocity.dy *= 0.92
            let b = clamped(position, bounds: bounds, size: size)
            if b.x != position.x { velocity.dx *= -0.45; position.x = b.x }
            if b.y != position.y { velocity.dy *= -0.45; position.y = b.y }
            if flung && abs(velocity.dx) + abs(velocity.dy) < 0.06 {
                flung = false
                velocity = .zero
                home = CGPoint(x: (position.x - bounds.minX) / bounds.width, y: (position.y - bounds.minY) / bounds.height)
            }
        case .dragging:
            velocity.dx *= 0.75
            velocity.dy *= 0.75
        }
        let target = reduceMotion ? 0 : clamp(velocity.dx * 2.4, -24, 24)
        angularVelocity = (angularVelocity + (target - angle) * 0.12) * 0.78
        angle += angularVelocity
    }

    /// Whether anything is still moving, so the overlay can stop redrawing.
    public var isAtRest: Bool {
        mode == .hidden || (mode == .floating && abs(velocity.dx) + abs(velocity.dy) < 0.01 && abs(angularVelocity) < 0.005 && abs(angle) < 0.05)
    }
}
