import Foundation
import CoreGraphics

public enum TimelineRenderer {
    public static func scene(_ document: Diagram) throws -> RenderScene {
        let issues = Validator.validate(document)
        guard issues.isEmpty else { throw DiagramError.invalid(issues) }
        guard let timeline = document.timeline else { throw DiagramError.message("This document has no timeline.") }
        let geometry = TimelineGeometry(timeline), palette = RenderPalette(document.theme.preset)
        var drawings: [Drawing] = []
        func fitted(_ value: String, width: CGFloat, size: CGFloat) -> String {
            guard width > 12 else { return "" }
            let clean = value.replacingOccurrences(of: "\n", with: " "), characters = Array(clean.prefix(512))
            let font = Typography.font(document.theme, size: size)
            if clean.count <= 512 && Typography.width(clean, font: font) <= width { return clean }
            var low = 0, high = characters.count
            while low < high {
                let middle = (low + high + 1) / 2
                if Typography.width(String(characters.prefix(middle)) + "…", font: font) <= width { low = middle }
                else { high = middle - 1 }
            }
            return String(characters.prefix(low)) + "…"
        }
        func rect(_ r: CGRect, fill: CGFloat, opacity: CGFloat = 1, role: PaintRole = .neutral) {
            drawings.append(Drawing(CGPath(rect: r, transform: nil), fill: fill, opacity: opacity, fillRole: role))
        }
        func text(_ value: String, _ r: CGRect, size: CGFloat = 13, accent: Bool = false, centered: Bool = false) {
            drawings.append(Drawing(Typography.paths(fitted(value, width: r.width, size: size), in: r, font: Typography.font(document.theme, size: size), centered: centered), fill: 0.14, fillRole: accent ? .accent : .neutral))
        }
        func line(_ points: [CGPoint], opacity: CGFloat = 1, accent: Bool = false, dashed: Bool = false) {
            guard let first = points.first else { return }
            let p = CGMutablePath(); p.move(to: first); for point in points.dropFirst() { p.addLine(to: point) }
            let path = accent && document.theme.sketch ? SketchStroke.path(p, seed: document.theme.seed ^ stableHash(points.map { "\($0.x),\($0.y)" }.joined(separator: ";")), connector: true) : p
            drawings.append(Drawing(path, stroke: 0.4, width: accent ? CGFloat(document.theme.strokeWidth) : 0.65, dashed: dashed, opacity: opacity, strokeRole: accent ? .accent : .neutral))
        }
        text(document.title, CGRect(x: 16, y: 7, width: geometry.bounds.width - 32, height: 30), size: 22)
        text("Calendar days · \(timeline.tasks.count) items", CGRect(x: 16, y: 38, width: 260, height: 24), size: 11)
        text("TASK / OWNER", CGRect(x: 16, y: 72, width: geometry.labelWidth - 28, height: 24), size: 11, accent: true)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimelineDate.calendar.timeZone
        formatter.dateFormat = "MMM yyyy"
        for day in 0..<geometry.days {
            guard let dateString = TimelineDate.adding(day, to: geometry.start), let date = TimelineDate.parse(dateString) else { continue }
            let x = geometry.labelWidth + CGFloat(day) * geometry.dayWidth
            let components = TimelineDate.calendar.dateComponents([.day, .weekday], from: date)
            let weekend = components.weekday == 1 || components.weekday == 7
            if weekend { rect(CGRect(x: x, y: geometry.headerHeight, width: geometry.dayWidth, height: geometry.bounds.height - geometry.headerHeight), fill: 0.4, opacity: 0.07) }
            let weekStart = components.weekday == 2
            let monthStart = components.day == 1
            if day == 0 || monthStart {
                let month = TimelineDate.calendar.range(of: .day, in: .month, for: date)!.count
                let width = min(CGFloat(month - components.day! + 1) * geometry.dayWidth - 10, geometry.bounds.maxX - x - 5)
                text(formatter.string(from: date), CGRect(x: x + 5, y: 51, width: min(150, width), height: 23), size: 12, accent: true)
            }
            if timeline.scale == .days || (timeline.scale == .weeks && (weekStart || day == 0)) || (timeline.scale == .months && monthStart) {
                text(String(components.day!), CGRect(x: x, y: 77, width: timeline.scale == .months ? 26 : max(28, geometry.dayWidth), height: 22), size: 10, centered: true)
            }
            if timeline.scale == .days || weekStart || monthStart {
                line([CGPoint(x: x, y: 76), CGPoint(x: x, y: geometry.bounds.maxY)], opacity: monthStart ? 0.4 : 0.16)
            }
        }
        for index in 0...max(timeline.tasks.count, 3) {
            let y = geometry.headerHeight + CGFloat(index) * geometry.rowHeight
            line([CGPoint(x: 0, y: y), CGPoint(x: geometry.bounds.maxX, y: y)], opacity: 0.22)
        }
        line([CGPoint(x: geometry.labelWidth, y: 52), CGPoint(x: geometry.labelWidth, y: geometry.bounds.maxY)], opacity: 0.5)
        for task in timeline.tasks {
            guard let bar = geometry.bars[task.id] else { continue }
            for dependency in task.dependencies {
                guard let before = geometry.bars[dependency] else { continue }
                let start = CGPoint(x: before.maxX + 2, y: before.midY), end = CGPoint(x: bar.minX - 3, y: bar.midY)
                let departure = start.x + 10, approach = min(end.x - 10, departure), middle = (start.y + end.y) / 2
                line([start, CGPoint(x: departure, y: start.y), CGPoint(x: departure, y: middle), CGPoint(x: approach, y: middle), CGPoint(x: approach, y: end.y), end], opacity: 0.65, accent: true)
                line([CGPoint(x: end.x - 5, y: end.y - 4), end, CGPoint(x: end.x - 5, y: end.y + 4)], opacity: 0.65, accent: true)
            }
        }
        for (index, task) in timeline.tasks.enumerated() {
            let row = geometry.rows[task.id]!, bar = geometry.bars[task.id]!
            let titleLines = Typography.lines(task.label, font: Typography.font(document.theme, size: 13), maxWidth: geometry.labelWidth - 54).prefix(2).joined(separator: "\n")
            text(String(index + 1), CGRect(x: 6, y: row.minY + 5, width: 20, height: 24), size: 10)
            text(titleLines, CGRect(x: 32, y: row.minY + 2, width: geometry.labelWidth - 44, height: 30), size: 13)
            let detail = task.owner.isEmpty ? (task.milestone ? task.start : "\(task.start) · \(task.duration)d") : task.owner
            text(detail, CGRect(x: 32, y: row.minY + 31, width: geometry.labelWidth - 44, height: 17), size: 10)
            if task.milestone {
                let p = CGMutablePath(); p.move(to: CGPoint(x: bar.midX, y: bar.minY)); p.addLine(to: CGPoint(x: bar.maxX, y: bar.midY)); p.addLine(to: CGPoint(x: bar.midX, y: bar.maxY)); p.addLine(to: CGPoint(x: bar.minX, y: bar.midY)); p.closeSubpath()
                drawings.append(Drawing(p, stroke: 0.2, fill: 0.2, width: CGFloat(document.theme.strokeWidth), strokeRole: .outline, fillRole: .outline))
            } else {
                let shape = CGPath(roundedRect: bar, cornerWidth: 3, cornerHeight: 3, transform: nil)
                let outline = document.theme.sketch ? SketchStroke.path(shape, seed: document.theme.seed ^ stableHash(task.id)) : shape
                drawings.append(Drawing(shape, fill: 0.25, opacity: 0.14, fillRole: .accent))
                if task.progress > 0 { rect(CGRect(x: bar.minX, y: bar.minY, width: bar.width * task.progress, height: bar.height), fill: 0.3, opacity: 0.34, role: .accent) }
                drawings.append(Drawing(outline, stroke: 0.2, width: CGFloat(document.theme.strokeWidth), strokeRole: .outline))
                if bar.width > 52 { text("\(Int((task.progress * 100).rounded()))%", bar, size: 11, centered: true) }
            }
        }
        if timeline.tasks.isEmpty { text("Add a task or milestone to start your timeline.", CGRect(x: 300, y: 120, width: 380, height: 34), size: 14) }
        var bounds = geometry.bounds.insetBy(dx: -24, dy: -24)
        for item in drawings { bounds = bounds.union(item.path.boundingBoxOfPath.insetBy(dx: -2, dy: -2)) }
        if document.watermark {
            bounds.size.height += 42
            let r = CGRect(x: bounds.maxX - 20 - T1AWatermark.aspectRatio * 24, y: bounds.maxY - 38, width: T1AWatermark.aspectRatio * 24, height: 24)
            drawings.append(Drawing(T1AWatermark.path(in: r), fill: 0.12, opacity: 0.4))
        }
        let layout = DiagramLayout(frames: geometry.bars.merging([document.root: geometry.bounds]) { first, _ in first }, contentOrigins: [document.root: .zero], order: [document.root] + timeline.tasks.map(\.id), routes: [:], labelFrames: [:], grids: [:], bounds: bounds)
        return RenderScene(layout: layout, drawings: drawings, palette: palette)
    }
}
