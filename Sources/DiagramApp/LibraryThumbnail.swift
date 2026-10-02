import AppKit
import DiagramCore

@MainActor enum LibraryThumbnail {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(_ item: DiagramCore.LibraryItem, dark: Bool) -> NSImage {
        let key = "\(item.id)-\(dark ? "dark" : "light")" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let paths: [CGPath]
        if let asset = item.asset { paths = asset.paths.compactMap { try? SVGPath.parse($0) } }
        else if item.shape == .text { paths = [Typography.paths("T", in: CGRect(x: 0, y: 0, width: 24, height: 24), font: Typography.font(Theme(preset: .standard), size: 20))] }
        else { paths = SymbolGeometry.paths(item.shape, in: CGRect(x: 0, y: 0, width: item.shape.defaultWidth, height: item.shape.defaultHeight)) }
        let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let image = NSImage(size: NSSize(width: 28, height: 24), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext, !bounds.isNull else { return false }
            appearance.performAsCurrentDrawingAppearance {
                let scale = min(24 / max(bounds.width, 1), 20 / max(bounds.height, 1))
                cg.translateBy(x: (28 - bounds.width * scale) / 2 - bounds.minX * scale, y: (24 - bounds.height * scale) / 2 - bounds.minY * scale)
                cg.scaleBy(x: scale, y: scale)
                cg.setStrokeColor(NSColor.labelColor.cgColor); cg.setFillColor(NSColor.labelColor.cgColor)
                cg.setLineWidth(1.25 / scale); cg.setLineJoin(.round); cg.setLineCap(.round)
                for (index, path) in paths.enumerated() {
                    cg.setLineWidth((item.shape.isDocument && index >= 3 ? 0.65 : 1.25) / scale)
                    cg.addPath(path)
                    if item.asset != nil { item.asset?.rendering == .outline ? cg.strokePath() : cg.drawPath(using: .eoFill) }
                    else if item.shape == .text { cg.fillPath() }
                    else if SymbolGeometry.isFilledDetail(item.shape, index: index) { cg.fillPath() }
                    else if item.shape == .actor || ((item.shape == .cylinder || item.shape.isDocument) && index > 0) { cg.strokePath() }
                    else {
                        cg.setFillColor(NSColor.windowBackgroundColor.cgColor); cg.drawPath(using: .fillStroke)
                    }
                }
            }
            return true
        }
        cache.setObject(image, forKey: key); return image
    }
}
