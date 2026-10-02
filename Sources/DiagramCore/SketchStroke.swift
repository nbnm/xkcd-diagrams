import CoreGraphics

/// Seeded pen strokes keep original vertices and midpoint tangents as attachment anchors.
/// Connector bends and attachments have straight stubs; glyphs and vendor marks stay exact.
enum SketchStroke {
    static func path(_ original: CGPath, seed: UInt64, connector: Bool = false) -> CGPath {
        let result = CGMutablePath()
        var random = SeededRandom(seed: seed)
        var current = CGPoint.zero, start = CGPoint.zero

        func draw(_ curve: Cubic, straight: Bool) {
            let length = curve.controlLength
            guard length > 0.001 else { return }
            // An even count preserves the original segment's midpoint and tangent.
            let count = 2 * min(32, max(1, Int(ceil(length / 280))))
            for index in 0..<count {
                let section = curve.section(from: CGFloat(index) / CGFloat(count), to: CGFloat(index + 1) / CGFloat(count))
                let sample = random.next()
                var (left, right) = section.split(at: 0.35 + abs(sample) * 0.30)
                let tangent = subtract(right.control1, left.control2)
                let magnitude = hypot(tangent.x, tangent.y)
                let maximum: CGFloat = connector ? 1.1 : (straight ? 1.5 : 0.85)
                let amplitude = min(maximum, section.controlLength * 0.06)
                let displacement = amplitude * (0.65 + abs(sample) * 0.35) * (sample < 0 ? -1 : 1)
                let offset = magnitude > 0.001
                    ? CGPoint(x: -tangent.y / magnitude * displacement, y: tangent.x / magnitude * displacement)
                    : .zero
                // Shift the interior join with its two handles; endpoint tangents stay exact.
                left.control2 = add(left.control2, offset)
                left.end = add(left.end, offset)
                right.control1 = add(right.control1, offset)
                result.addCurve(to: left.end, control1: left.control1, control2: left.control2)
                result.addCurve(to: right.end, control1: right.control1, control2: right.control2)
            }
        }

        original.applyWithBlock { element in
            let item = element.pointee
            switch item.type {
            case .moveToPoint:
                current = item.points[0]; start = current; result.move(to: current)
            case .addLineToPoint:
                let end = item.points[0]
                if connector {
                    let length = hypot(end.x - current.x, end.y - current.y)
                    if length > 24 {
                        // Protect both ends of every segment, including manual bends.
                        let departure = interpolate(current, end, 12 / length)
                        let approach = interpolate(current, end, 1 - 12 / length)
                        result.addLine(to: departure)
                        draw(Cubic.line(from: departure, to: approach), straight: true)
                        result.addLine(to: end)
                    } else { result.addLine(to: end) }
                } else { draw(Cubic.line(from: current, to: end), straight: true) }
                current = end
            case .addQuadCurveToPoint:
                let control = item.points[0], end = item.points[1]
                draw(Cubic(start: current, control1: interpolate(current, control, 2 / 3),
                           control2: interpolate(end, control, 2 / 3), end: end), straight: false)
                current = end
            case .addCurveToPoint:
                draw(Cubic(start: current, control1: item.points[0], control2: item.points[1], end: item.points[2]), straight: false)
                current = item.points[2]
            case .closeSubpath:
                if current != start { draw(Cubic.line(from: current, to: start), straight: true) }
                result.closeSubpath(); current = start
            @unknown default: break
            }
        }
        return result
    }

    private struct Cubic {
        var start: CGPoint
        var control1: CGPoint
        var control2: CGPoint
        var end: CGPoint

        static func line(from start: CGPoint, to end: CGPoint) -> Cubic {
            Cubic(start: start, control1: interpolate(start, end, 1 / 3), control2: interpolate(start, end, 2 / 3), end: end)
        }
        var controlLength: CGFloat {
            zip([start, control1, control2], [control1, control2, end]).reduce(0) {
                $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
            }
        }
        func split(at t: CGFloat) -> (Cubic, Cubic) {
            let a = interpolate(start, control1, t), b = interpolate(control1, control2, t), c = interpolate(control2, end, t)
            let d = interpolate(a, b, t), e = interpolate(b, c, t), middle = interpolate(d, e, t)
            return (Cubic(start: start, control1: a, control2: d, end: middle),
                    Cubic(start: middle, control1: e, control2: c, end: end))
        }
        func section(from lower: CGFloat, to upper: CGFloat) -> Cubic {
            let prefix = upper == 1 ? self : split(at: upper).0
            return lower == 0 ? prefix : prefix.split(at: lower / upper).1
        }
    }
    private static func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    private static func subtract(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
}
