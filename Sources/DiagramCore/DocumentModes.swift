import Foundation
import CoreGraphics

public enum DocumentMode: String, Codable, CaseIterable {
    case diagram, drawing, timeline
    public var title: String { switch self { case .diagram: return "Diagram"; case .drawing: return "Free Drawing"; case .timeline: return "Timeline" } }
    public var symbol: String { switch self { case .diagram: return "square.stack.3d.up"; case .drawing: return "pencil.tip"; case .timeline: return "chart.bar.xaxis" } }
    public func blank() -> Diagram { Diagram(title: "Untitled " + (self == .drawing ? "drawing" : rawValue), mode: self) }
}

public struct InkStroke: Codable, Equatable {
    public var id: String
    public var points: [Point]
    public var strokeWidth: Double
    public var smoothing: Double
    public init(id: String = UUID().uuidString.lowercased(), points: [Point], strokeWidth: Double = 2, smoothing: Double = 0.65) {
        self.id = id; self.points = points; self.strokeWidth = strokeWidth; self.smoothing = smoothing
    }
}
public struct FreeDrawing: Codable, Equatable {
    public var strokes: [InkStroke]
    public var smoothing: Double
    public var strokeWidth: Double
    public init(strokes: [InkStroke] = [], smoothing: Double = 0.65, strokeWidth: Double = 2) {
        self.strokes = strokes; self.smoothing = smoothing; self.strokeWidth = strokeWidth
    }
}

public enum FreehandGeometry {
    /// A bounded local filter removes mouse jitter; midpoint curves avoid overshoot.
    /// Keep raw samples in the document so smoothing remains editable and deterministic.
    public static func path(_ stroke: InkStroke) -> CGPath {
        let path = CGMutablePath()
        var points = stroke.points.map { CGPoint(x: $0.x, y: $0.y) }
        guard let first = points.first else { return path }
        if points.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 0.01, y: first.y - 0.01, width: 0.02, height: 0.02)); return path
        }
        let amount = CGFloat(min(1, max(0, stroke.smoothing)))
        if points.count > 2 && amount > 0 {
            for _ in 0..<2 {
                let source = points
                for i in 1..<(points.count - 1) {
                    points[i] = CGPoint(x: source[i].x * (1 - amount / 2) + (source[i - 1].x + source[i + 1].x) * amount / 4,
                                        y: source[i].y * (1 - amount / 2) + (source[i - 1].y + source[i + 1].y) * amount / 4)
                }
            }
        }
        path.move(to: first)
        if amount == 0 || points.count == 2 { for point in points.dropFirst() { path.addLine(to: point) }; return path }
        for i in 1..<points.count {
            let midpoint = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
            path.addQuadCurve(to: midpoint, control: points[i - 1])
        }
        path.addQuadCurve(to: points.last!, control: points.last!)
        return path
    }
    public static func hit(_ stroke: InkStroke, point: CGPoint, tolerance: CGFloat = 6) -> Bool {
        path(stroke).copy(strokingWithWidth: max(CGFloat(stroke.strokeWidth), tolerance * 2), lineCap: .round, lineJoin: .round, miterLimit: 2).contains(point)
    }
}

public enum TimelineScale: String, Codable, CaseIterable {
    case days, weeks, months
    public var dayWidth: CGFloat { switch self { case .days: return 38; case .weeks: return 18; case .months: return 6 } }
    public var title: String { rawValue.capitalized }
}
public struct TimelineTask: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var start: String
    public var duration: Int
    public var progress: Double
    public var owner: String
    public var milestone: Bool
    public var dependencies: [String]
    public init(id: String = UUID().uuidString.lowercased(), label: String = "New task", start: String = TimelineDate.today,
                duration: Int = 5, progress: Double = 0, owner: String = "", milestone: Bool = false, dependencies: [String] = []) {
        self.id = id; self.label = label; self.start = start; self.duration = duration; self.progress = progress
        self.owner = owner; self.milestone = milestone; self.dependencies = dependencies
    }
    public var finish: String { TimelineDate.adding((1...3650).contains(duration) ? duration - 1 : 0, to: start) ?? start }
}
public struct Timeline: Codable, Equatable {
    public var tasks: [TimelineTask]
    public var scale: TimelineScale
    public init(tasks: [TimelineTask] = [], scale: TimelineScale = .weeks) { self.tasks = tasks; self.scale = scale }
    public static func example(start: String = TimelineDate.today) -> Timeline {
        let a = TimelineTask(id: "discovery", label: "Discovery & design", start: start, duration: 5, progress: 0.6, owner: "Architecture")
        let b = TimelineTask(id: "build", label: "Build & integration", start: TimelineDate.adding(5, to: start)!, duration: 10, progress: 0.2, owner: "Engineering", dependencies: [a.id])
        let c = TimelineTask(id: "test", label: "Validation", start: TimelineDate.adding(15, to: start)!, duration: 5, owner: "Delivery", dependencies: [b.id])
        let d = TimelineTask(id: "launch", label: "Go live", start: TimelineDate.adding(20, to: start)!, duration: 0, milestone: true, dependencies: [c.id])
        return Timeline(tasks: [a, b, c, d])
    }
}

public enum TimelineDate {
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    public static func parse(_ value: String) -> Date? {
        guard value.count == 10, value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }) else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1900...2200).contains(parts[0]), let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), string(date) == value else { return nil }
        return date
    }
    public static func string(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    public static var today: String {
        // A document stores a calendar date, independent of the machine's UTC offset.
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func adding(_ days: Int, to value: String) -> String? {
        guard (-36600...36600).contains(days) else { return nil }
        guard let date = parse(value), let result = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return string(result)
    }
    public static func distance(_ a: String, _ b: String) -> Int {
        guard let start = parse(a), let end = parse(b) else { return 0 }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

public struct TimelineGeometry {
    public let start: String
    public let days: Int
    public let dayWidth: CGFloat
    public let labelWidth: CGFloat = 280
    public let headerHeight: CGFloat = 104
    public let rowHeight: CGFloat = 52
    public var bars: [String: CGRect] = [:]
    public var rows: [String: CGRect] = [:]
    public var bounds: CGRect
    public init(_ timeline: Timeline) {
        dayWidth = timeline.scale.dayWidth
        let first = timeline.tasks.map(\.start).min() ?? TimelineDate.today
        let padded = TimelineDate.adding(-2, to: first) ?? first
        start = TimelineDate.parse(padded) == nil ? first : padded
        let last = timeline.tasks.map(\.finish).max() ?? first
        days = max(28, TimelineDate.distance(start, last) + 8)
        bounds = CGRect(x: 0, y: 0, width: 280 + CGFloat(days) * dayWidth, height: 104 + CGFloat(max(timeline.tasks.count, 3)) * 52)
        for (index, task) in timeline.tasks.enumerated() {
            let y = headerHeight + CGFloat(index) * rowHeight
            rows[task.id] = CGRect(x: 0, y: y, width: bounds.width, height: rowHeight)
            bars[task.id] = CGRect(x: labelWidth + CGFloat(TimelineDate.distance(start, task.start)) * dayWidth,
                                   y: y + 14, width: task.milestone ? 24 : max(dayWidth, CGFloat(task.duration) * dayWidth), height: 24)
        }
    }
    public func date(at x: CGFloat) -> String { TimelineDate.adding(Int(floor((x - labelWidth) / dayWidth)), to: start) ?? start }
}

public enum TimelineEditing {
    public static func shift(_ id: String, by days: Int, in timeline: inout Timeline) {
        guard let index = timeline.tasks.firstIndex(where: { $0.id == id }), let start = TimelineDate.adding(days, to: timeline.tasks[index].start) else { return }
        timeline.tasks[index].start = start
    }
    public static func reorder(_ id: String, by delta: Int, in timeline: inout Timeline) {
        guard let index = timeline.tasks.firstIndex(where: { $0.id == id }) else { return }
        let next = max(0, min(timeline.tasks.count - 1, index + delta))
        let task = timeline.tasks.remove(at: index); timeline.tasks.insert(task, at: next)
    }
}

public enum DocumentModeValidation {
    public static func validate(_ d: Diagram) -> [Diagnostic] {
        var issues: [Diagnostic] = []
        func report(_ path: String, _ message: String) { issues.append(.init("mode-content", path, message)) }
        if (d.mode == .drawing) != (d.drawing != nil) { report("$.drawing", "Free Drawing requires drawing content; other modes must omit it.") }
        if (d.mode == .timeline) != (d.timeline != nil) { report("$.timeline", "Timeline requires timeline content; other modes must omit it.") }
        if d.mode != .diagram && (d.containers.count != 1 || !d.connectors.isEmpty || d.containers[d.root]?.layout.mode != .free) { report("$.mode", "Drawing and timeline documents use a free root without containers or diagram connectors.") }
        if d.mode == .drawing && d.nodes.values.contains(where: { $0.shape != .text }) { report("$.nodes", "Free Drawing uses pen strokes and text items.") }
        if d.mode == .timeline && !d.nodes.isEmpty { report("$.nodes", "Timeline content belongs in timeline.tasks.") }
        var ids = Set(d.nodes.keys).union(d.containers.keys).union(d.connectors.keys)
        if let drawing = d.drawing {
            if !drawing.smoothing.isFinite || !(0...1).contains(drawing.smoothing) { report("$.drawing.smoothing", "Use smoothing between 0 and 1.") }
            if !drawing.strokeWidth.isFinite || !(0.5...8).contains(drawing.strokeWidth) { report("$.drawing.strokeWidth", "Use a line width between 0.5 and 8.") }
            if drawing.strokes.count > 2000 { report("$.drawing.strokes", "Use at most 2000 strokes.") }
            var samples = 0
            for (i, stroke) in drawing.strokes.enumerated() {
                let p = "$.drawing.strokes[\(i)]"; samples += stroke.points.count
                if stroke.id.isEmpty || !ids.insert(stroke.id).inserted { report(p + ".id", "Use a nonempty unique ID.") }
                if stroke.points.isEmpty || stroke.points.count > 20000 { report(p + ".points", "A stroke needs 1–20000 points.") }
                if stroke.points.contains(where: { !$0.x.isFinite || !$0.y.isFinite || abs($0.x) > 100000 || abs($0.y) > 100000 }) { report(p + ".points", "Coordinates must be finite and within ±100000.") }
                if !stroke.smoothing.isFinite || !(0...1).contains(stroke.smoothing) { report(p + ".smoothing", "Use smoothing between 0 and 1.") }
                if !stroke.strokeWidth.isFinite || !(0.5...8).contains(stroke.strokeWidth) { report(p + ".strokeWidth", "Use a line width between 0.5 and 8.") }
            }
            if samples > 250000 { report("$.drawing.strokes", "Use at most 250000 total points.") }
        }
        if let timeline = d.timeline {
            if timeline.tasks.count > 500 { report("$.timeline.tasks", "Use at most 500 tasks."); return issues }
            let taskIDs = Set(timeline.tasks.map(\.id))
            for (i, task) in timeline.tasks.enumerated() {
                let p = "$.timeline.tasks[\(i)]"
                if task.id.isEmpty || !ids.insert(task.id).inserted { report(p + ".id", "Use a nonempty unique ID.") }
                if TimelineDate.parse(task.start) == nil { report(p + ".start", "Use a valid YYYY-MM-DD date between 1900 and 2200.") }
                if !(task.milestone ? 0...0 : 1...3650).contains(task.duration) { report(p + ".duration", "Tasks last 1–3650 calendar days; milestones have zero duration.") }
                if TimelineDate.parse(task.finish) == nil { report(p + ".duration", "Task finish must be between 1900 and 2200.") }
                if !task.progress.isFinite || !(0...1).contains(task.progress) { report(p + ".progress", "Progress must be between 0 and 1.") }
                if Set(task.dependencies).count != task.dependencies.count || task.dependencies.contains(where: { $0 == task.id || !taskIDs.contains($0) }) { report(p + ".dependencies", "Predecessors must be distinct, existing, other tasks.") }
            }
            var active = Set<String>(), done = Set<String>()
            let tasks = Dictionary(timeline.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            func visit(_ id: String) {
                if active.contains(id) { report("$.timeline.tasks", "Task dependencies cannot contain a cycle."); return }
                guard !done.contains(id) else { return }
                active.insert(id)
                for previous in tasks[id]?.dependencies ?? [] { visit(previous) }
                active.remove(id); done.insert(id)
            }
            for task in timeline.tasks { visit(task.id) }
            if let first = timeline.tasks.map(\.start).min(), let last = timeline.tasks.map(\.finish).max(), TimelineDate.distance(first, last) > 3650 { report("$.timeline.tasks", "Keep the overall timeline within ten years.") }
        }
        return issues
    }
}
