import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#else
/// Linux's Foundation has CGPoint and CGRect but no CGVector; this lets the core build and test there too.
public struct CGVector: Equatable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }
    public static let zero = CGVector(dx: 0, dy: 0)
}
#endif

public extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

public extension CGVector {
    var length: CGFloat { hypot(dx, dy) }
}

enum Spring {
    /// One step of a damped spring pulling `position` toward `target`.
    static func step(_ position: inout CGPoint, _ velocity: inout CGVector, toward target: CGPoint, k: CGFloat, damping: CGFloat) {
        velocity.dx = (velocity.dx + (target.x - position.x) * k) * damping
        velocity.dy = (velocity.dy + (target.y - position.y) * k) * damping
        position.x += velocity.dx
        position.y += velocity.dy
    }
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T {
    min(max(value, low), high)
}
