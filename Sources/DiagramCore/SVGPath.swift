import Foundation
import CoreGraphics

/// Parses geometry only. No XML, scripts, links, filters, or external resources.
public enum SVGPath {
    public static func parse(_ source: String) throws -> CGPath {
        let regex = try NSRegularExpression(pattern: "[a-zA-Z]|[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?[0-9]*)(?:[eE][-+]?[0-9]+)?")
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        let residue = regex.stringByReplacingMatches(in: source, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        guard residue.allSatisfy({ $0.isWhitespace || $0 == "," }), matches.count <= 100000 else { throw DiagramError.message("Invalid or excessively large SVG path.") }
        var tokens = matches.map { ns.substring(with: $0.range) }
        let path = CGMutablePath()
        var i = 0, command = "", previous = ""
        var current = CGPoint.zero, start = CGPoint.zero, control = CGPoint.zero
        func number() throws -> CGFloat {
            guard i < tokens.count, let value = Double(tokens[i]), value.isFinite, abs(value) <= 1e7 else { throw DiagramError.message("Invalid SVG path coordinate.") }
            i += 1; return CGFloat(value)
        }
        func point(relative: Bool) throws -> CGPoint {
            let x = try number(), y = try number()
            return CGPoint(x: x + (relative ? current.x : 0), y: y + (relative ? current.y : 0))
        }
        // SVG permits flags and coordinates without separators: "0 0110.4-7.5".
        func flag() throws -> Bool {
            guard i < tokens.count, let first = tokens[i].first, first == "0" || first == "1" else { throw DiagramError.message("SVG arc flags must be 0 or 1.") }
            let remainder = String(tokens[i].dropFirst())
            if remainder.isEmpty { i += 1 } else { tokens[i] = remainder }
            return first == "1"
        }
        while i < tokens.count {
            if tokens[i].first?.isLetter == true { command = tokens[i]; i += 1 }
            guard !command.isEmpty else { throw DiagramError.message("SVG paths must start with a move command.") }
            let relative = command == command.lowercased(), op = command.uppercased()
            switch op {
            case "M":
                current = try point(relative: relative); path.move(to: current); start = current
                command = relative ? "l" : "L"
            case "L": current = try point(relative: relative); path.addLine(to: current)
            case "H": let x = try number(); current.x = x + (relative ? current.x : 0); path.addLine(to: current)
            case "V": let y = try number(); current.y = y + (relative ? current.y : 0); path.addLine(to: current)
            case "C":
                let a = try point(relative: relative), b = try point(relative: relative), end = try point(relative: relative)
                path.addCurve(to: end, control1: a, control2: b); control = b; current = end
            case "S":
                let a = ["C", "S"].contains(previous) ? CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y) : current
                let b = try point(relative: relative), end = try point(relative: relative)
                path.addCurve(to: end, control1: a, control2: b); control = b; current = end
            case "Q":
                let a = try point(relative: relative), end = try point(relative: relative)
                path.addQuadCurve(to: end, control: a); control = a; current = end
            case "T":
                let a = ["Q", "T"].contains(previous) ? CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y) : current
                let end = try point(relative: relative); path.addQuadCurve(to: end, control: a); control = a; current = end
            case "A":
                let rx = try number(), ry = try number(), angle = try number(), large = try flag(), sweep = try flag()
                let end = try point(relative: relative)
                arc(path, from: current, to: end, rx: abs(rx), ry: abs(ry), angle: angle, large: large, sweep: sweep)
                current = end
            case "Z": path.closeSubpath(); current = start; command = ""
            default: throw DiagramError.message("Unsupported SVG path command '\(command)'.")
            }
            previous = op
        }
        guard !path.isEmpty else { throw DiagramError.message("Empty SVG path.") }
        return path
    }

    private static func arc(_ path: CGMutablePath, from a: CGPoint, to b: CGPoint, rx: CGFloat, ry: CGFloat, angle: CGFloat, large: Bool, sweep: Bool) {
        guard a != b else { return }
        guard rx > 0, ry > 0 else { path.addLine(to: b); return }
        var rx = rx, ry = ry
        let phi = angle * .pi / 180, c = cos(phi), s = sin(phi)
        let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
        let x = c * dx + s * dy, y = -s * dx + c * dy
        let ratio = x * x / (rx * rx) + y * y / (ry * ry)
        if ratio > 1 { let scale = sqrt(ratio); rx *= scale; ry *= scale }
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y * y - ry * ry * x * x)
        let denominator = rx * rx * y * y + ry * ry * x * x
        let factor = (large == sweep ? -1.0 : 1.0) * sqrt(numerator / max(denominator, 1e-12))
        let cxp = factor * rx * y / ry, cyp = factor * -ry * x / rx
        let center = CGPoint(x: c * cxp - s * cyp + (a.x + b.x) / 2, y: s * cxp + c * cyp + (a.y + b.y) / 2)
        let theta = atan2((y - cyp) / ry, (x - cxp) / rx)
        var delta = atan2((-y - cyp) / ry, (-x - cxp) / rx) - theta
        if sweep && delta < 0 { delta += 2 * .pi }
        if !sweep && delta > 0 { delta -= 2 * .pi }
        let count = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        func position(_ t: CGFloat) -> CGPoint { CGPoint(x: center.x + c * rx * cos(t) - s * ry * sin(t), y: center.y + s * rx * cos(t) + c * ry * sin(t)) }
        func derivative(_ t: CGFloat) -> CGPoint { CGPoint(x: -c * rx * sin(t) - s * ry * cos(t), y: -s * rx * sin(t) + c * ry * cos(t)) }
        for n in 0..<count {
            let t1 = theta + delta * CGFloat(n) / CGFloat(count), t2 = theta + delta * CGFloat(n + 1) / CGFloat(count)
            let k = 4 / 3 * tan((t2 - t1) / 4), p1 = position(t1), p2 = position(t2), v1 = derivative(t1), v2 = derivative(t2)
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + k * v1.x, y: p1.y + k * v1.y), control2: CGPoint(x: p2.x - k * v2.x, y: p2.y - k * v2.y))
        }
    }
}

extension CGPath {
    public var svgData: String {
        var commands: [String] = []
        func p(_ point: CGPoint) -> String { "\(format(point.x)) \(format(point.y))" }
        applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: commands.append("M" + p(e.points[0]))
            case .addLineToPoint: commands.append("L" + p(e.points[0]))
            case .addQuadCurveToPoint: commands.append("Q" + p(e.points[0]) + " " + p(e.points[1]))
            case .addCurveToPoint: commands.append("C" + p(e.points[0]) + " " + p(e.points[1]) + " " + p(e.points[2]))
            case .closeSubpath: commands.append("Z")
            @unknown default: break
            }
        }
        return commands.joined(separator: " ")
    }
}
func format(_ value: CGFloat) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value) }
