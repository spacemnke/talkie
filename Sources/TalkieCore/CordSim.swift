import Foundation
import CoreGraphics

/// A patch cord: it leaves its hole in the well, hangs in a curve, and ends at the plug.
/// The two control points trail behind on springs, so the cord swings when the plug moves.
public struct CordSim: Equatable, Sendable {
    public var plug: CGPoint = .zero
    public var plugVelocity: CGVector = .zero
    public var control1: CGPoint = .zero
    public var control1Velocity: CGVector = .zero
    public var control2: CGPoint = .zero
    public var control2Velocity: CGVector = .zero
    public var dragging = false

    public init() {}

    public static func controlTargets(dock: CGPoint, plug: CGPoint) -> (CGPoint, CGPoint) {
        let d = dock.distance(to: plug)
        return (
            CGPoint(x: dock.x, y: dock.y - min(d * 0.35, 110)),
            CGPoint(x: plug.x + (dock.x - plug.x) * 0.08, y: plug.y + min(16 + d * 0.4, 130))
        )
    }

    public mutating func snap(dock: CGPoint, target: CGPoint) {
        plug = target
        plugVelocity = .zero
        (control1, control2) = Self.controlTargets(dock: dock, plug: plug)
        control1Velocity = .zero
        control2Velocity = .zero
    }

    /// Advances one frame. Returns false once everything has come to rest.
    @discardableResult
    public mutating func step(dock: CGPoint, target: CGPoint, reduceMotion: Bool) -> Bool {
        let before = (plug, control1, control2)
        if !dragging {
            if reduceMotion {
                plug = target
                plugVelocity = .zero
            } else {
                Spring.step(&plug, &plugVelocity, toward: target, k: 0.2, damping: 0.68)
            }
        }
        let (t1, t2) = Self.controlTargets(dock: dock, plug: plug)
        if reduceMotion {
            control1 = t1
            control2 = t2
        } else {
            Spring.step(&control1, &control1Velocity, toward: t1, k: 0.14, damping: 0.72)
            Spring.step(&control2, &control2Velocity, toward: t2, k: 0.07, damping: 0.82)
        }
        return before.0.distance(to: plug) > 0.01
            || before.1.distance(to: control1) > 0.01
            || before.2.distance(to: control2) > 0.01
    }
}
