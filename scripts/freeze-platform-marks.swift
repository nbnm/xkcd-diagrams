import Foundation
import CoreGraphics

// Compile alongside DiagramCore/SVGPath.swift, using the app's geometry parser.
enum DiagramError: Error { case message(String) }

/// Only the self-contained SVG subset used by our retained source marks is supported.
final class MarkParser: NSObject, XMLParserDelegate {
    struct Paint {
        var fill = "black", stroke = "none"
        var width: CGFloat = 1
        var cap = CGLineCap.butt, join = CGLineJoin.miter
        var transform = CGAffineTransform.identity
    }
    var stack: [Paint] = [], paths: [String] = [], viewBox: [Double] = []
    var failure: Error?
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        do {
            var paint = stack.last ?? Paint()
            if let fill = a["fill"] { paint.fill = fill }
            if let stroke = a["stroke"] { paint.stroke = stroke }
            if let width = a["stroke-width"] { paint.width = try value(width) }
            if let cap = a["stroke-linecap"] { paint.cap = cap == "round" ? .round : cap == "square" ? .square : .butt }
            if let join = a["stroke-linejoin"] { paint.join = join == "round" ? .round : join == "bevel" ? .bevel : .miter }
            if let text = a["transform"] {
                let n = try numbers(text)
                guard text.hasPrefix("rotate("), n.count == 1 || n.count == 3 else { throw DiagramError.message("Unsupported source transform: \(text)") }
                let angle = n[0] * .pi / 180, c = cos(angle), s = sin(angle)
                let x = n.count == 3 ? n[1] : 0, y = n.count == 3 ? n[2] : 0
                let rotation = CGAffineTransform(a: c, b: s, c: -s, d: c, tx: x * (1 - c) + y * s, ty: y * (1 - c) - x * s)
                paint.transform = rotation.concatenating(paint.transform)
            }
            stack.append(paint)
            func n(_ key: String, _ fallback: CGFloat = 0) throws -> CGFloat { try a[key].map(value) ?? fallback }
            let path: CGPath
            switch element {
            case "svg":
                guard let box = a["viewBox"] else { throw DiagramError.message("Missing source viewBox") }
                viewBox = try numbers(box).map(Double.init); return
            case "g", "title", "desc": return
            case "path": path = try SVGPath.parse(a["d"] ?? "")
            case "rect":
                let rect = try CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height"))
                let rx = try n("rx", n("ry")), ry = try n("ry", rx)
                path = CGPath(roundedRect: rect, cornerWidth: min(rx, rect.width / 2), cornerHeight: min(ry, rect.height / 2), transform: nil)
            case "circle":
                let x = try n("cx"), y = try n("cy"), r = try n("r")
                path = CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil)
            case "line":
                let line = CGMutablePath(); line.move(to: try CGPoint(x: n("x1"), y: n("y1")))
                line.addLine(to: try CGPoint(x: n("x2"), y: n("y2"))); path = line
            default: throw DiagramError.message("Unsupported source element: \(element)")
            }
            func append(_ path: CGPath) {
                var transform = paint.transform
                paths.append(path.copy(using: &transform)!.svgData)
            }
            if paint.fill != "none" { append(path) }
            if paint.stroke != "none" {
                append(path.copy(strokingWithWidth: paint.width, lineCap: paint.cap, lineJoin: paint.join, miterLimit: 10))
            }
        } catch { failure = error; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
    func value(_ text: String) throws -> CGFloat {
        guard let value = Double(text), value.isFinite else { throw DiagramError.message("Invalid source number") }
        return CGFloat(value)
    }
    func numbers(_ text: String) throws -> [CGFloat] {
        let regex = try NSRegularExpression(pattern: "[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?[0-9]*)(?:[eE][-+]?[0-9]+)?")
        let source = text as NSString
        return try regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { try value(source.substring(with: $0.range)) }
    }
    static func read(_ url: URL) throws -> MarkParser {
        let mark = MarkParser(), parser = XMLParser(data: try Data(contentsOf: url))
        parser.shouldResolveExternalEntities = false; parser.delegate = mark
        guard parser.parse(), mark.failure == nil, mark.viewBox.count == 4, !mark.paths.isEmpty else {
            throw mark.failure ?? parser.parserError ?? DiagramError.message("Invalid source SVG")
        }
        return mark
    }
}

@main struct FreezeMarks {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw DiagramError.message("Supply repository root and output JSON path") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let definitions = [
            ("secondstack", "SecondStack", "assets/vendor/secondstack.svg", "https://secondstack.ai/", "asterisk"),
            ("lakesentry", "LakeSentry", "assets/vendor/lakesentry.svg", "https://lakesentry.io/logo.svg", "light.beacon.max"),
            ("8fde", "8FDE", "assets/vendor/8fde.svg", "https://8fde.ai/", "person.2"),
            ("antares", "Antares", "assets/vendor/antares.svg", "https://getantares.io/", "chart.bar"),
            ("t1a", "T1A", "assets/t1a-logo.svg", "https://t1a.com/images/t1a-LOGO.svg", "building.2"),
            ("ai-agent", "AI Agent", "assets/ai-agent.svg", "builtin:ai-agent", "cpu"),
            ("genie-agent", "Genie Agent", "assets/vendor/genie-agent.svg", "https://www.databricks.com/sites/default/files/2026-05/icon-genie.svg", "sparkles")
        ]
        var entries: [[String: Any]] = []
        for (id, title, filename, source, symbol) in definitions {
            let mark = try MarkParser.read(root.appendingPathComponent(filename))
            // Use LakeSentry's lighthouse symbol; the editable label supplies the product name.
            let paths = id == "lakesentry" ? Array(mark.paths.prefix(1)) : mark.paths
            let box = id == "lakesentry" ? [263.0, 0, 32, 56] : mark.viewBox
            let agent = id == "ai-agent" || id == "genie-agent"
            entries.append(["id": id, "title": title, "group": id == "ai-agent" ? "Systems" : id == "genie-agent" ? "Databricks" : "T1A",
                "type": agent ? "agent" : "service", "shape": agent ? "roundedRectangle" : "rectangle", "symbol": symbol,
                "asset": ["name": title, "source": source, "viewBox": box, "paths": paths]])
        }
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
