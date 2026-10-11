import Foundation
import CoreGraphics

/// The mic's coiled cord: a fixed number of loops wound around a sagging curve,
/// so pulling the mic further away stretches the coils open.
public enum Coil {
    public static func bezier(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ u: CGFloat) -> CGPoint {
        let v = 1 - u
        let a = v * v * v, b = 3 * v * v * u, c = 3 * v * u * u, d = u * u * u
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
        )
    }

    public static func points(from start: CGPoint, to anchor: CGPoint, coils: Int = 26, radius: CGFloat = 5.5) -> [CGPoint] {
        let d = start.distance(to: anchor)
        let c1 = CGPoint(x: start.x, y: start.y + 30 + d * 0.25)
        let c2 = CGPoint(x: anchor.x, y: anchor.y + 20 + d * 0.3)

        // Sample the curve and measure it, so the loops are spaced by length, not by curve parameter.
        let samples = 60
        var base = [start]
        var cumulative: [CGFloat] = [0]
        for i in 1...samples {
            let q = bezier(start, c1, c2, anchor, CGFloat(i) / CGFloat(samples))
            cumulative.append(cumulative[i - 1] + q.distance(to: base[i - 1]))
            base.append(q)
        }
        let length = cumulative[samples]
        let count = max(140, Int((length / 1.3).rounded()))
        var out: [CGPoint] = []
        out.reserveCapacity(count + 1)
        var k = 0
        for i in 0...count {
            let u = CGFloat(i) / CGFloat(count)
            let s = u * length
            while k < samples - 1 && cumulative[k + 1] < s { k += 1 }
            let a = base[k], b = base[k + 1]
            let segment = max(cumulative[k + 1] - cumulative[k], 0.0001)
            let t = (s - cumulative[k]) / segment
            let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
            let tx = (b.x - a.x) / segment, ty = (b.y - a.y) / segment
            // Straight at both ends, coiled in between.
            let taper = clamp(min(u / 0.05, (1 - u) / 0.05), 0, 1)
            let r = radius * taper
            let theta = u * CGFloat(coils) * 2 * .pi
            out.append(CGPoint(
                x: x - ty * r * sin(theta) - tx * r * 0.9 * cos(theta),
                y: y + tx * r * sin(theta) - ty * r * 0.9 * cos(theta)
            ))
        }
        return out
    }
}
