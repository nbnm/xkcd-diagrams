import Foundation
import CoreGraphics
import CoreText

public enum Typography {
    public static func font(_ theme: Theme, size: CGFloat? = nil) -> CTFont {
        CTFontCreateWithName((theme.fontFamily ?? (theme.sketch ? "ChalkboardSE-Regular" : theme.preset == .blueprint ? "Menlo-Regular" : "Helvetica")) as CFString, size ?? CGFloat(theme.fontSize), nil)
    }
    public static func font(_ document: Diagram, for id: String) -> CTFont {
        font(document.theme, size: CGFloat(document.fontSize(for: id)))
    }
    static func containerHeaderHeight(_ container: Container, theme: Theme) -> CGFloat {
        guard let size = container.fontSize else { return 36 }
        let font = font(theme, size: CGFloat(size))
        let lines = (container.label ?? "Container").components(separatedBy: "\n").count
        return max(36, ceil(CGFloat(lines) * (CTFontGetAscent(font) + CTFontGetDescent(font) + 5)) + 22)
    }
    static func line(_ text: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    }
    public static func width(_ text: String, font: CTFont) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line(text, font: font), nil, nil, nil)) }
    public static func lines(_ text: String, font: CTFont, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
                let candidate = current.isEmpty ? String(word) : current + " " + word
                if !current.isEmpty && width(candidate, font: font) > maxWidth { lines.append(current); current = String(word) }
                else { current = candidate }
            }
            lines.append(current)
        }
        return lines
    }
    public static func paths(_ text: String, in rect: CGRect, font: CTFont, centered: Bool = true) -> CGPath {
        let result = CGMutablePath(), strings = lines(text, font: font, maxWidth: rect.width)
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + 5
        let total = CGFloat(strings.count) * lineHeight
        var y = rect.midY - total / 2 + CTFontGetAscent(font)
        for string in strings {
            let line = line(string, font: font)
            let x = centered ? rect.midX - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / 2 : rect.minX
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName] as! CTFont
                for index in 0..<count {
                    if let path = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) {
                        let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x + positions[index].x, ty: y - positions[index].y)
                        result.addPath(path, transform: transform)
                    }
                }
            }
            y += lineHeight
        }
        return result
    }
}

public struct DiagramLayout {
    public var frames: [String: CGRect]
    public var order: [String]
    public var routes: [String: [CGPoint]]
    public var labelFrames: [String: CGRect]
    public var grids: [String: GridGeometry]
    public var bounds: CGRect
    public func hit(_ point: CGPoint, document: Diagram, excluding: Set<String> = []) -> String? {
        order.reversed().first { $0 != document.root && !excluding.contains($0) && frames[$0]!.contains(point) }
    }
    /// Preview a drag without changing the document, using the same attachment rules as a saved connector.
    public func connectionPreview(from source: String, to target: String?, at point: CGPoint, document: Diagram) -> [CGPoint]? {
        func valid(_ id: String) -> Bool { id != document.root && (document.nodes[id] != nil || document.containers[id] != nil) }
        guard valid(source), let frame = frames[source], point.x.isFinite, point.y.isFinite else { return nil }
        if let target {
            guard valid(target), target != source else { return nil }
            return ConnectorRouter.route(Connector(from: Endpoint(source), to: Endpoint(target)), frames: frames, document: document)
        }
        let cursor = CGRect(origin: point, size: .zero)
        let start = ConnectorRouter.attachment(.auto, frame: frame, toward: cursor, shape: document.nodes[source]?.shape, inward: false)
        let end = ConnectorRouter.Attachment(point: point, normal: CGPoint(x: -start.normal.x, y: -start.normal.y))
        let obstacles = document.nodes.keys.sorted().compactMap { frames[$0]?.insetBy(dx: -8, dy: -8) }
        return ConnectorRouter.route(from: start, to: end, waypoints: nil, obstacles: obstacles, envelope: frame.union(cursor))
    }
}

public enum LayoutEngine {
    public static func layout(_ d: Diagram) throws -> DiagramLayout {
        let diagnostics = Validator.validate(d)
        guard diagnostics.isEmpty else { throw DiagramError.invalid(diagnostics) }
        let font = Typography.font(d.theme)
        var sizes: [String: CGSize] = [:], shifts: [String: CGPoint] = [:], grids: [String: GridGeometry] = [:]
        func measure(_ id: String) -> CGSize {
            if let existing = sizes[id] { return existing }
            let size: CGSize
            if let n = d.nodes[id] {
                let font = Typography.font(d, for: id)
                let wordWidth = n.label.split(whereSeparator: { $0.isWhitespace }).map { Typography.width(String($0), font: font) }.max() ?? 0
                let labelPadding: CGFloat = n.shape.isDocument ? 44 : 40
                let logoWidth: CGFloat = n.shape == .cylinder && n.asset != nil ? DatabaseContent.minimumLogoWidth : 0
                let width = max(CGFloat(n.width ?? n.shape.defaultWidth), wordWidth + labelPadding, logoWidth)
                let lines = Typography.lines(n.label, font: font, maxWidth: width - labelPadding).count
                let contentPadding: CGFloat = n.shape == .cylinder ? DatabaseContent.verticalPadding(hasLogo: n.asset != nil) : n.shape.isDocument && n.shape != .file ? 120 + (n.asset == nil ? 0 : 43) : n.asset != nil ? 70 : n.shape == .actor ? 96 : n.shape == .file ? 48 : 32
                let height = CGFloat(lines) * (CTFontGetAscent(font) + CTFontGetDescent(font) + 5) + contentPadding
                size = CGSize(width: width, height: max(CGFloat(n.height ?? n.shape.defaultHeight), height))
            } else {
                let c = d.containers[id]!, padding = CGFloat(c.layout.padding), gap = CGFloat(c.layout.gap)
                let childSizes = c.children.map(measure)
                let header: CGFloat = id == d.root ? 0 : Typography.containerHeaderHeight(c, theme: d.theme)
                var content = CGSize.zero
                switch c.layout.mode {
                case .grid:
                    // The document validator has already checked capacity and cell assignments.
                    let plan = try! GridLayout.plan(c, id: id)
                    let grid = GridLayout.geometry(plan, sizes: sizes, gap: gap)
                    grids[id] = grid; content = grid.size
                case .horizontal:
                    content = CGSize(width: childSizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, childSizes.count - 1)), height: childSizes.map(\.height).max() ?? 0)
                case .vertical:
                    content = CGSize(width: childSizes.map(\.width).max() ?? 0, height: childSizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, childSizes.count - 1)))
                case .free:
                    var rect = CGRect.zero
                    for (index, child) in c.children.enumerated() {
                        let p = d.nodes[child]?.position ?? d.containers[child]?.position ?? Point(x: Double(index) * 210, y: 0)
                        rect = rect.union(CGRect(x: p.x, y: p.y, width: childSizes[index].width, height: childSizes[index].height))
                    }
                    content = rect.size; shifts[id] = CGPoint(x: -rect.minX, y: -rect.minY)
                }
                let titleFont = c.fontSize == nil ? font : Typography.font(d, for: id)
                let titleWidth = c.fontSize == nil ? Typography.width(c.label ?? "", font: titleFont) :
                    (c.label ?? "Container").components(separatedBy: "\n").map { Typography.width($0, font: titleFont) }.max() ?? 0
                let titlePadding = c.fontSize == nil ? padding * 2 : max(40, padding * 2)
                size = CGSize(width: max(CGFloat(c.width ?? 0), id == d.root ? 0 : 210, content.width + padding * 2, titleWidth + titlePadding), height: max(CGFloat(c.height ?? 0), id == d.root ? 0 : 130, content.height + padding * 2 + header))
            }
            sizes[id] = size; return size
        }
        _ = measure(d.root)
        var frames: [String: CGRect] = [:], order: [String] = []
        func place(_ id: String, at origin: CGPoint, size forcedSize: CGSize? = nil) {
            let size = forcedSize ?? sizes[id]!
            frames[id] = CGRect(origin: origin, size: size); order.append(id)
            guard let c = d.containers[id] else { return }
            let pad = CGFloat(c.layout.padding), gap = CGFloat(c.layout.gap)
            let header: CGFloat = id == d.root ? 0 : Typography.containerHeaderHeight(c, theme: d.theme)
            if var grid = grids[id] {
                let extraWidth = max(0, size.width - pad * 2 - grid.size.width) / CGFloat(grid.columnWidths.count)
                let extraHeight = max(0, size.height - pad * 2 - header - grid.size.height) / CGFloat(grid.rowHeights.count)
                grid.columnWidths = grid.columnWidths.map { $0 + extraWidth }
                grid.rowHeights = grid.rowHeights.map { $0 + extraHeight }
                grids[id] = grid
            }
            var cursor = CGPoint(x: origin.x + pad, y: origin.y + pad + header)
            for (index, child) in c.children.enumerated() {
                let childSize = sizes[child]!
                var at = cursor
                switch c.layout.mode {
                case .grid:
                    let grid = grids[id]!, cell = grid.frame(grid.cells[child]!)
                    at.x += cell.minX; at.y += cell.minY
                    if d.containers[child] != nil {
                        place(child, at: at, size: cell.size)
                    } else {
                        at.x += (cell.width - childSize.width) / 2; at.y += (cell.height - childSize.height) / 2
                        place(child, at: at)
                    }
                    continue
                case .horizontal:
                    at.y += (size.height - pad * 2 - header - childSize.height) / 2
                    cursor.x += childSize.width + gap
                case .vertical:
                    at.x += (size.width - pad * 2 - childSize.width) / 2
                    cursor.y += childSize.height + gap
                case .free:
                    let p = d.nodes[child]?.position ?? d.containers[child]?.position ?? Point(x: Double(index) * 210, y: 0)
                    at.x += CGFloat(p.x) + (shifts[id]?.x ?? 0); at.y += CGFloat(p.y) + (shifts[id]?.y ?? 0)
                }
                place(child, at: at)
            }
        }
        place(d.root, at: .zero)
        var routes: [String: [CGPoint]] = [:], labelFrames: [String: CGRect] = [:]
        var bounds = order.filter { $0 != d.root }.reduce(CGRect.null) { $0.union(frames[$1]!) }
        if d.containers[d.root]?.layout.mode == .grid { bounds = bounds.union(frames[d.root]!) }
        for id in d.connectors.keys.sorted() {
            let edge = d.connectors[id]!, points = ConnectorRouter.route(edge, frames: frames, document: d)!
            routes[id] = points
            for point in points { bounds = bounds.union(CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)) }
            if let label = edge.label, !label.isEmpty {
                let pairs = Array(zip(points, points.dropFirst())).sorted {
                    hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) > hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
                }
                let labelFont = Typography.font(d, for: id)
                let lines = label.components(separatedBy: "\n")
                let width = (edge.fontSize == nil ? Typography.width(label, font: labelFont) : lines.map { Typography.width($0, font: labelFont) }.max() ?? 0) + 16
                let height: CGFloat = edge.fontSize == nil ? 22 : max(22, ceil(CGFloat(lines.count) * (CTFontGetAscent(labelFont) + CTFontGetDescent(labelFont) + 5)) + 4)
                var candidates: [CGRect] = []
                for step in 0..<12 {
                    let offset = CGFloat(10 + step * 24)
                    for segment in pairs {
                        let midpoint = CGPoint(x: (segment.0.x + segment.1.x) / 2, y: (segment.0.y + segment.1.y) / 2)
                        let horizontal = abs(segment.0.x - segment.1.x) >= abs(segment.0.y - segment.1.y)
                        if horizontal {
                            candidates.append(CGRect(x: midpoint.x - width / 2, y: midpoint.y - height - offset, width: width, height: height))
                            candidates.append(CGRect(x: midpoint.x - width / 2, y: midpoint.y + offset, width: width, height: height))
                        } else {
                            candidates.append(CGRect(x: midpoint.x + offset, y: midpoint.y - height / 2, width: width, height: height))
                            candidates.append(CGRect(x: midpoint.x - width - offset, y: midpoint.y - height / 2, width: width, height: height))
                        }
                    }
                }
                let obstacles = d.nodes.keys.compactMap { frames[$0] } + d.containers.keys.filter { $0 != d.root }.compactMap { key -> CGRect? in
                    guard let rect = frames[key] else { return nil }
                    return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(42, Typography.containerHeaderHeight(d.containers[key]!, theme: d.theme) + 6))
                } + Array(labelFrames.values)
                let r = candidates.first { candidate in !obstacles.contains { $0.intersects(candidate.insetBy(dx: -2, dy: -2)) } } ?? candidates[0]
                labelFrames[id] = r; bounds = bounds.union(r)
            }
        }
        if bounds.isNull { bounds = CGRect(x: 0, y: 0, width: 640, height: 420) }
        return DiagramLayout(frames: frames, order: order, routes: routes, labelFrames: labelFrames, grids: grids, bounds: bounds.insetBy(dx: -36, dy: -36))
    }
}
