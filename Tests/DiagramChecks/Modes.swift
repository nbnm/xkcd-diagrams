import Foundation
import CoreGraphics
import ImageIO
import DiagramCore

func documentModesPreserveLegacyAndStrictRoundTrips() throws {
    let legacy = Library.sample()
    var object = try JSONSerialization.jsonObject(with: legacy.encoded()) as! [String: Any]
    object.removeValue(forKey: "mode")
    let decoded = try Diagram.decode(JSONSerialization.data(withJSONObject: object))
    try expect(decoded.mode == .diagram && decoded.drawing == nil && decoded.timeline == nil)
    for mode in DocumentMode.allCases {
        let doc = mode.blank()
        try expect(Validator.validate(doc).isEmpty)
        try expect(try Diagram.decode(doc.encoded()) == doc)
        _ = try Renderer.svg(doc)
    }
    var doc = DocumentMode.drawing.blank()
    doc.drawing = nil
    try expect(!Validator.validate(doc).isEmpty)
    doc = DocumentMode.timeline.blank(); doc.drawing = FreeDrawing()
    try expect(!Validator.validate(doc).isEmpty)
    object = try JSONSerialization.jsonObject(with: DocumentMode.drawing.blank().encoded()) as! [String: Any]
    var drawing = object["drawing"] as! [String: Any]; drawing["unknown"] = true; object["drawing"] = drawing
    try expectThrows { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)) }
    object = try JSONSerialization.jsonObject(with: DocumentMode.timeline.blank().encoded()) as! [String: Any]
    object["mode"] = "future-mode"
    try expectThrows { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)) }
}

func freehandSmoothingPreservesEndpointsAndRemovesJitter() throws {
    let points: [Point] = (0...20).map { index in
        let y: Double = index == 0 || index == 20 ? 0 : (index % 2 == 0 ? 6 : -6)
        return Point(x: Double(index) * 8, y: y)
    }
    let raw = InkStroke(id: "raw", points: points, smoothing: 0)
    let smooth = InkStroke(id: "smooth", points: points, smoothing: 1)
    let a = FreehandGeometry.path(raw), b = FreehandGeometry.path(smooth)
    try expect(b.currentPoint == CGPoint(x: points.last!.x, y: points.last!.y))
    try expect(b.boundingBoxOfPath.height < a.boundingBoxOfPath.height)
    try expect(b.boundingBoxOfPath.minX >= 0 && b.boundingBoxOfPath.maxX <= 160)
    try expect(FreehandGeometry.hit(smooth, point: CGPoint(x: 80, y: 0)))
    try expect(!FreehandGeometry.hit(smooth, point: CGPoint(x: 80, y: 100)))
    try expect(!FreehandGeometry.path(InkStroke(points: [Point(x: 12, y: 9)])).isEmpty)
    var d = DocumentMode.drawing.blank(); d.drawing?.strokes = [smooth]
    let before = d.drawing!.strokes[0].points
    d.drawing?.strokes[0].smoothing = 0.4
    try expect(d.drawing!.strokes[0].points == before)
    try expect(try Renderer.svg(d) == Renderer.svg(d))
}

func freeDrawingBoundsTextAndValidationStayPortable() throws {
    var d = DocumentMode.drawing.blank()
    d.drawing?.strokes = [InkStroke(id: "stroke", points: [Point(x: -250, y: -130), Point(x: -70, y: -20)], strokeWidth: 8)]
    d.nodes["note"] = Node(type: "text", label: "A handwritten note", shape: .text, position: Point(x: -230, y: -100))
    d.containers[d.root]?.children = ["note"]
    try expect(try Diagram.decode(d.encoded()) == d)
    let scene = try Renderer.scene(d)
    try expect(scene.layout.bounds.minX < -250 && scene.layout.bounds.minY < -130)
    for preset in ThemePreset.allCases {
        d.theme.preset = preset
        let png = try Renderer.png(d, scale: 0.5)
        try expect(CGImageSourceCreateWithData(png as CFData, nil) != nil)
        _ = try Renderer.svg(d)
    }
    let valid = d
    d.drawing?.strokes[0].points[0].x = .infinity
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.drawing?.strokes[0].id = "note"
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.nodes["note"]?.shape = .rectangle
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.drawing?.smoothing = 2
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.remove("stroke")
    try expect(d.drawing?.strokes.isEmpty == true && d.nodes["note"] != nil)
}

func timelineCalendarMathHandlesLeapYearsAndDST() throws {
    try expect(TimelineDate.adding(1, to: "2026-03-08") == "2026-03-09")
    try expect(TimelineDate.adding(2, to: "2024-02-28") == "2024-03-01")
    try expect(TimelineDate.distance("2026-03-07", "2026-03-10") == 3)
    try expect(TimelineDate.parse("2025-02-29") == nil && TimelineDate.parse("2026-13-01") == nil)
    try expect(TimelineDate.parse("2026-2-01") == nil)
    let task = TimelineTask(start: "2026-03-08", duration: 3)
    try expect(task.finish == "2026-03-10")
    let milestone = TimelineTask(start: "2026-10-26", duration: 0, milestone: true)
    try expect(milestone.finish == milestone.start)
    var d = DocumentMode.timeline.blank()
    d.timeline?.tasks = [TimelineTask(start: "1900-01-01", duration: 1)]
    _ = try Renderer.svg(d)
    d.timeline?.tasks[0].duration = Int.min
    try expect(!Validator.validate(d).isEmpty)
}

func timelineValidationRejectsCyclesAndInvalidSchedules() throws {
    var d = DocumentMode.timeline.blank(); d.timeline = .example(start: "2026-10-26")
    try expect(try Diagram.decode(d.encoded()) == d)
    let valid = d
    d.timeline?.tasks[0].dependencies = ["launch"]
    try expect(Validator.validate(d).contains { $0.message.contains("cycle") })
    try expectThrows { _ = try Renderer.svg(d) }
    d = valid; d.timeline?.tasks[0].dependencies = ["missing"]
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.timeline?.tasks[0].start = "2026-02-30"
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.timeline?.tasks[0].progress = 1.1
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.timeline?.tasks[0].id = valid.timeline!.tasks[1].id
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.timeline?.tasks[3].duration = 1
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.timeline?.tasks[3].start = "2040-01-01"
    try expect(!Validator.validate(d).isEmpty)
    d = valid; d.remove("build")
    try expect(d.timeline?.tasks.first { $0.id == "test" }?.dependencies.isEmpty == true)
    try expect(Validator.validate(d).isEmpty)
}

func timelineGeometryEditingAndExportsAgreeAcrossStyles() throws {
    var d = DocumentMode.timeline.blank(); d.title = "Delivery timeline"; d.timeline = .example(start: "2026-10-26")
    let original = d.timeline!
    for scale in TimelineScale.allCases {
        d.timeline?.scale = scale
        let g = TimelineGeometry(d.timeline!)
        try expect(g.bars["build"]!.width == CGFloat(original.tasks[1].duration) * scale.dayWidth)
        try expect(g.bars["test"]!.minX - g.bars["build"]!.minX == 10 * scale.dayWidth)
    }
    TimelineEditing.shift("build", by: 3, in: &d.timeline!)
    try expect(d.timeline!.tasks[1].start == "2026-11-03")
    try expect(d.timeline!.tasks[0] == original.tasks[0] && d.timeline!.tasks[2] == original.tasks[2])
    TimelineEditing.reorder("build", by: 1, in: &d.timeline!)
    try expect(d.timeline!.tasks[2].id == "build" && d.timeline!.tasks[2].dependencies == ["discovery"])
    for preset in ThemePreset.allCases {
        for sketch in [false, true] {
            d.theme.preset = preset; d.theme.sketch = sketch
            let scene = try Renderer.scene(d), g = TimelineGeometry(d.timeline!)
            try expect(scene.layout.frames["build"] == g.bars["build"])
            try expect(try Renderer.svg(d) == Renderer.svg(d))
            let png = try Renderer.png(d, scale: 0.4)
            try expect(CGImageSourceCreateWithData(png as CFData, nil) != nil)
        }
    }
}

func oversizedModeFilesCannotOverwriteReadableDocuments() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mode-size-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("drawing.diagram.json"), original = DocumentMode.drawing.blank()
    let revision = try DiagramFiles.write(original, to: file)
    var oversized = original; oversized.title = String(repeating: "x", count: 16 * 1024 * 1024)
    try expectThrows { _ = try DiagramFiles.write(oversized, to: file, expectedRevision: revision) }
    let (saved, unchangedRevision) = try DiagramFiles.read(file)
    try expect(saved == original && unchangedRevision == revision)
}

func timelineDependenciesApproachTheStartFromOutsideTheBar() throws {
    var d = DocumentMode.timeline.blank(); d.timeline = .example(start: "2026-10-26"); d.theme.sketch = false
    let scene = try Renderer.scene(d), geometry = TimelineGeometry(d.timeline!)
    let lines = scene.drawings.filter { $0.strokeRole == .accent && $0.stroke != nil }
    var routes: [[CGPoint]] = []
    for line in lines {
        var points: [CGPoint] = []
        line.path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint { points.append(element.pointee.points[0]) }
        }
        if points.count > 3 { routes.append(points) }
    }
    try expect(routes.count == 3)
    for (route, task) in zip(routes, d.timeline!.tasks.dropFirst()) {
        let end = route.last!, before = route[route.count - 2], bar = geometry.bars[task.id]!
        try expect(before.y == end.y && before.x < end.x && end.x < bar.minX)
        try expect(route.allSatisfy { !bar.contains($0) })
        for (a, b) in zip(route, route.dropFirst()) { try expect(a.x == b.x || a.y == b.y) }
    }
}
