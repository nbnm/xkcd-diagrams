import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

public struct Drawing {
    public var path: CGPath
    public var stroke: CGFloat?
    public var fill: CGFloat?
    public var width: CGFloat
    public var dashed: Bool
    public var evenOdd: Bool = false
    public var opacity: CGFloat
    public var strokeRole: PaintRole
    public var fillRole: PaintRole
    public init(_ path: CGPath, stroke: CGFloat? = nil, fill: CGFloat? = nil, width: CGFloat = 1, dashed: Bool = false, evenOdd: Bool = false, opacity: CGFloat = 1, strokeRole: PaintRole = .neutral, fillRole: PaintRole = .neutral) {
        self.path = path; self.stroke = stroke; self.fill = fill; self.width = width; self.dashed = dashed; self.evenOdd = evenOdd
        self.opacity = opacity
        self.strokeRole = strokeRole; self.fillRole = fillRole
    }
}

public struct RenderScene {
    public var layout: DiagramLayout
    public var drawings: [Drawing]
    public var palette: RenderPalette
    public func drawBackground(in context: CGContext, bounds: CGRect) {
        context.setFillColor(palette.background); context.fill(bounds)
        if palette.blueprint { BlueprintGrid.draw(in: context, bounds: bounds) }
    }
    public func draw(in context: CGContext) {
        for item in drawings {
            context.saveGState()
            context.setAlpha(item.opacity)
            context.addPath(item.path)
            context.setLineWidth(item.width); context.setLineCap(.round); context.setLineJoin(.round)
            if item.dashed { context.setLineDash(phase: 0, lengths: [7, 5]) }
            if let fill = item.fill { context.setFillColor(palette.color(fill, role: item.fillRole)) }
            if let stroke = item.stroke { context.setStrokeColor(palette.color(stroke, role: item.strokeRole)) }
            if palette.blueprint && (item.fill ?? 0) >= 0.99 {
                // Repaint the same paper through filled objects, hiding underlying connectors while keeping the grid continuous.
                context.saveGState(); context.clip(using: item.evenOdd ? .evenOdd : .winding)
                drawBackground(in: context, bounds: item.path.boundingBoxOfPath)
                context.restoreGState()
                if item.stroke != nil { context.addPath(item.path); context.strokePath() }
            }
            else if item.stroke != nil && item.fill != nil { context.drawPath(using: item.evenOdd ? .eoFillStroke : .fillStroke) }
            else if item.stroke != nil { context.strokePath() }
            else { context.drawPath(using: item.evenOdd ? .eoFill : .fill) }
            context.restoreGState()
        }
    }
}

public enum Renderer {
    public static func scene(_ document: Diagram) throws -> RenderScene {
        if document.mode == .timeline { return try TimelineRenderer.scene(document) }
        let layout = try LayoutEngine.layout(document)
        var drawings: [Drawing] = []
        let sketch = document.theme.sketch, palette = RenderPalette(document.theme.preset)
        func penStroke(_ path: CGPath, id: String, connector: Bool = false) -> CGPath {
            sketch ? SketchStroke.path(path, seed: document.theme.seed ^ stableHash(id), connector: connector) : path
        }
        func outline(_ points: [CGPoint], id: String, closed: Bool = false, connector: Bool = false) -> CGPath {
            let p = CGMutablePath(); guard let first = points.first else { return p }
            p.move(to: first)
            for end in points.dropFirst() { p.addLine(to: end) }
            if closed { p.addLine(to: first); p.closeSubpath() }
            return penStroke(p, id: id, connector: connector)
        }
        func corners(_ r: CGRect) -> [CGPoint] { [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)] }
        func polygon(_ geometry: CGPath, id: String) -> CGPath {
            var vertices: [CGPoint] = []
            geometry.applyWithBlock { element in
                if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint { vertices.append(element.pointee.points[0]) }
            }
            return outline(vertices, id: id, closed: true)
        }
        // Boundaries first, relationships second, system nodes last.
        for id in layout.order where document.containers[id] != nil && id != document.root {
            let rect = layout.frames[id]!
            let width = CGFloat(document.strokeWidth(for: id))
            drawings.append(Drawing(outline(corners(rect), id: id, closed: true), stroke: 0.46, fill: 1, width: width, dashed: true, strokeRole: .accent, fillRole: .container))
        }
        for id in document.connectors.keys.sorted() {
            let edge = document.connectors[id]!, points = layout.routes[id]!
            let width = CGFloat(document.strokeWidth(for: id))
            drawings.append(Drawing(outline(points, id: id, connector: true), stroke: 0.32, width: width, dashed: edge.dashed, strokeRole: .accent))
            func arrow(_ end: CGPoint, before: CGPoint, suffix: String) {
                let angle = atan2(end.y - before.y, end.x - before.x), length: CGFloat = 10
                let a = CGPoint(x: end.x - length * cos(angle - 0.42), y: end.y - length * sin(angle - 0.42))
                let b = CGPoint(x: end.x - length * cos(angle + 0.42), y: end.y - length * sin(angle + 0.42))
                drawings.append(Drawing(outline([a, end, b], id: id + suffix), stroke: 0.32, width: width, strokeRole: .accent))
            }
            let distinct = points.enumerated().filter { $0.offset == 0 || points[$0.offset - 1] != $0.element }.map(\.element)
            if distinct.count > 1 && edge.direction != .none { arrow(distinct.last!, before: distinct[distinct.count - 2], suffix: "-arrow") }
            if distinct.count > 1 && edge.direction == .both { arrow(distinct[0], before: distinct[1], suffix: "-back") }
        }
        for id in layout.order {
            let r = layout.frames[id]!
            guard let node = document.nodes[id] else { continue }
            let width = CGFloat(document.strokeWidth(for: id))
            let path: CGPath
            let geometry = SymbolGeometry.paths(node.shape, in: r)
            switch node.shape {
            case .roundedRectangle:
                path = penStroke(geometry[0], id: id)
            case .file, .xlsx, .pdf, .docx:
                // Both the renderer and the library preview use the folded sheet geometry.
                path = polygon(geometry[0], id: id)
                drawings.append(Drawing(path, stroke: 0.14, fill: 1, width: width, strokeRole: .outline, fillRole: .surface))
                drawings.append(Drawing(penStroke(geometry[1], id: id + "-fold"), stroke: 0.14, width: width, strokeRole: .outline))
                for (index, detail) in geometry.enumerated() where index >= 2 {
                    drawings.append(SymbolGeometry.isFilledDetail(node.shape, index: index)
                        ? Drawing(detail, fill: 0.14)
                        : Drawing(penStroke(detail, id: id + "-detail-\(index)"), stroke: 0.14, width: width, strokeRole: .outline))
                }
            case .cylinder:
                path = penStroke(geometry[0], id: id)
                drawings.append(Drawing(path, stroke: 0.14, fill: 1, width: width, strokeRole: .outline, fillRole: .surface))
                drawings.append(Drawing(penStroke(geometry[1], id: id + "-lip"), stroke: 0.14, width: width, strokeRole: .outline))
            case .queue:
                for (index, layer) in geometry.enumerated() {
                    drawings.append(Drawing(outline(corners(layer.boundingBoxOfPath), id: id + "-layer-\(index)", closed: true), stroke: 0.14, fill: 1, width: width, strokeRole: .outline, fillRole: .surface))
                }
                path = geometry.last!
            case .text: path = CGMutablePath()
            case .actor: path = penStroke(geometry[0], id: id)
            case .rectangle: path = outline(corners(r), id: id, closed: true)
            }
            if node.shape != .cylinder && node.shape != .queue && !node.shape.isDocument && node.shape != .text { drawings.append(Drawing(path, stroke: 0.14, fill: node.shape == .actor ? nil : 1, width: width, strokeRole: .outline, fillRole: .surface)) }
            var labelRect = (node.shape == .queue ? geometry.last!.boundingBoxOfPath : r).insetBy(dx: 18, dy: 12)
            if node.shape == .cylinder { labelRect = DatabaseContent.labelRect(in: r, hasLogo: node.asset != nil) }
            else if node.shape.isDocument { labelRect = DocumentContent.labelRect(node.shape, in: r, hasLogo: node.asset != nil) }
            if let assetID = node.asset, let asset = document.assets[assetID] {
                let logoY: CGFloat = node.shape.isDocument && node.shape != .file ? 102 : 14
                let target = node.shape == .cylinder ? DatabaseContent.logoRect(in: r)
                    : CGRect(x: r.midX - 50, y: r.minY + logoY, width: 100, height: 34)
                let variant = node.variant ?? .black
                if variant == .white && !palette.lightInk { drawings.append(Drawing(CGPath(roundedRect: target.insetBy(dx: -5, dy: -5), cornerWidth: 4, cornerHeight: 4, transform: nil), fill: 0.15)) }
                let scale = min(target.width / asset.viewBox[2], target.height / asset.viewBox[3])
                var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                    tx: target.midX - asset.viewBox[2] * scale / 2 - asset.viewBox[0] * scale,
                    ty: target.midY - asset.viewBox[3] * scale / 2 - asset.viewBox[1] * scale)
                let ink: CGFloat = palette.lightInk || variant == .black ? 0.12 : 1
                for data in asset.paths {
                    let p = try SVGPath.parse(data).copy(using: &transform)!
                    drawings.append(asset.rendering == .outline ? Drawing(p, stroke: ink, width: max(0.65, width * 0.65)) : Drawing(p, fill: ink, evenOdd: true))
                }
                if node.shape != .cylinder && !node.shape.isDocument { labelRect.origin.y += 43; labelRect.size.height -= 43 }
            } else if node.shape == .actor { labelRect = UserContent.labelRect(in: r) }
            drawings.append(Drawing(Typography.paths(node.label, in: labelRect, font: Typography.font(document, for: id), centered: document.mode != .drawing, fitInk: node.shape == .actor), fill: 0.12))
        }
        for id in layout.order where id != document.root && document.containers[id] != nil {
            let r = layout.frames[id]!, label = document.containers[id]!.label ?? "Container"
            let container = document.containers[id]!
            let height = container.fontSize == nil ? 26 : Typography.containerHeaderHeight(container, theme: document.theme) - 22
            let textRect = CGRect(x: r.minX + 20, y: r.minY + 11, width: r.width - 40, height: height)
            drawings.append(Drawing(Typography.paths(label, in: textRect, font: Typography.font(document, for: id), centered: false), fill: 0.36, fillRole: .accent))
        }
        for id in document.connectors.keys.sorted() {
            if let label = document.connectors[id]!.label, let rect = layout.labelFrames[id] {
                drawings.append(Drawing(CGPath(rect: rect, transform: nil), fill: 1))
                drawings.append(Drawing(Typography.paths(label, in: rect.insetBy(dx: 5, dy: 2), font: Typography.font(document, for: id)), fill: 0.32))
            }
        }
        if let drawing = document.drawing {
            // Freehand strokes use their own smoothing, never synthetic sketch wobble.
            drawings.insert(contentsOf: drawing.strokes.map { Drawing(FreehandGeometry.path($0), stroke: 0.14, width: CGFloat($0.strokeWidth), strokeRole: .outline) }, at: 0)
        }
        // Include actual stroked geometry and glyph extents to avoid export clipping.
        var result = layout
        for drawing in drawings { result.bounds = result.bounds.union(drawing.path.boundingBoxOfPath.insetBy(dx: -drawing.width, dy: -drawing.width)) }
        if document.watermark {
            // Keep branding in its own footer rather than obscuring systems or connectors.
            let height: CGFloat = 24, inset: CGFloat = 20
            result.bounds.size.width = max(result.bounds.width, T1AWatermark.aspectRatio * height + inset * 2)
            result.bounds.size.height += height + inset
            let rect = CGRect(x: result.bounds.maxX - inset - T1AWatermark.aspectRatio * height,
                              y: result.bounds.maxY - inset - height, width: T1AWatermark.aspectRatio * height, height: height)
            drawings.append(Drawing(T1AWatermark.path(in: rect), fill: 0.12, opacity: 0.4))
        }
        return RenderScene(layout: result, drawings: drawings, palette: palette)
    }

    public static func svg(_ document: Diagram, transparent: Bool = false) throws -> Data {
        let scene = try scene(document), b = scene.layout.bounds
        var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(format(b.width))\" height=\"\(format(b.height))\" viewBox=\"\(format(b.minX)) \(format(b.minY)) \(format(b.width)) \(format(b.height))\" role=\"img\">",
                     "<title>\(xmlEscape(document.title))</title>"]
        if scene.palette.blueprint { lines.append(BlueprintGrid.svgDefinitions(background: scene.palette.backgroundHex)) }
        if !transparent { lines.append("<rect x=\"\(format(b.minX))\" y=\"\(format(b.minY))\" width=\"\(format(b.width))\" height=\"\(format(b.height))\" fill=\"\(scene.palette.blueprint ? "url(#blueprint-paper)" : scene.palette.backgroundHex)\"/>") }
        for item in scene.drawings {
            let fill = scene.palette.blueprint && (item.fill ?? 0) >= 0.99 ? "url(#blueprint-paper)" : item.fill.map { scene.palette.hex($0, role: item.fillRole) } ?? "none"
            var attributes = "d=\"\(item.path.svgData)\" fill=\"\(fill)\""
            if let stroke = item.stroke { attributes += " stroke=\"\(scene.palette.hex(stroke, role: item.strokeRole))\" stroke-width=\"\(format(item.width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" }
            if item.dashed { attributes += " stroke-dasharray=\"7 5\"" }
            if item.evenOdd { attributes += " fill-rule=\"evenodd\"" }
            if item.opacity < 1 { attributes += " opacity=\"\(format(item.opacity))\"" }
            lines.append("<path \(attributes)/>")
        }
        lines.append("</svg>"); return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    public static func png(_ document: Diagram, scale: Double = 2, transparent: Bool = false) throws -> Data {
        guard scale.isFinite && (0.25...8).contains(scale) else { throw DiagramError.message("PNG scale must be between 0.25 and 8.") }
        let scene = try scene(document), b = scene.layout.bounds
        let w = Int(ceil(b.width * scale)), h = Int(ceil(b.height * scale))
        guard w > 0, h > 0, w <= 16384, h <= 16384, w * h <= 64000000 else { throw DiagramError.message("PNG exceeds the 64 megapixel export limit. Reduce scale or export SVG.") }
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw DiagramError.message("Cannot allocate export image.") }
        context.translateBy(x: 0, y: CGFloat(h)); context.scaleBy(x: scale, y: -scale); context.translateBy(x: -b.minX, y: -b.minY)
        if !transparent { scene.drawBackground(in: context, bounds: CGRect(x: b.minX, y: b.minY, width: CGFloat(w) / scale, height: CGFloat(h) / scale)) }
        scene.draw(in: context)
        guard let image = context.makeImage() else { throw DiagramError.message("Cannot create export image.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw DiagramError.message("Cannot encode PNG.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw DiagramError.message("PNG encoding failed.") }
        return data as Data
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(state >> 11) / Double(UInt64.max >> 11) * 2 - 1)
    }
}
func stableHash(_ text: String) -> UInt64 { text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 } }
func xmlEscape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
