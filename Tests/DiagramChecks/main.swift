import Foundation
import CoreGraphics
import ImageIO
import CoreText
import Darwin
import DiagramCore

let themeVariants = ThemePreset.allCases.flatMap { preset in [false, true].map { (preset, $0) } }

func toolboxShortcutsCoverEveryPresetWithoutConflicts() throws {
    let keys = ToolboxShortcuts.all.map(\.keys)
    try expect(Set(keys).count == keys.count)
    for key in keys { try expect(!keys.contains { $0.count < key.count && key.starts(with: $0) }) }
    let presets = ToolboxShortcuts.all.compactMap { tool -> String? in if case .item(let id) = tool.action { return id }; return nil }
    try expect(Set(presets) == Set(Library.items().map(\.id)))
    for item in Library.items() {
        try expect(ToolboxShortcuts.shortcut(for: .item(item.id))?.title == item.title)
    }
    try expect(ToolboxShortcuts.matching(["e"]).first?.action == .connector)
    try expect(ToolboxShortcuts.matching(["x"]).first?.action == .container)
    try expect(ToolboxShortcuts.matching(["2", "g"]).first?.action == .item("genie-agent"))
    try expect(ToolboxShortcuts.matching(["3", "v"]).first?.action == .item("azure-vm"))
}

func clipboardDuplicatesNestedContainersAndInternalConnections() throws {
    var original = Library.sample()
    original.containers["platform"]?.fontSize = 24
    original.nodes["lakehouse"]?.fontSize = 28; original.nodes["lakehouse"]?.strokeWidth = 4
    original.containers["nested"] = Container(label: "Nested", layout: .init(mode: .grid, rows: 1, columns: 1, cells: ["catalog": GridCell()]), children: ["catalog"])
    original.containers["platform"]?.children = ["ingestion", "lakehouse", "nested"]
    original.containers["platform"]?.allowedChildTypes?.append("container")
    try DiagramEditing.setLayout(.grid, container: "platform", document: &original)
    let cells = try GridLayout.plan(original.containers["platform"]!, id: "platform").cells
    original.containers["platform"]?.layout.cells = cells
    original.connectors["store"]?.waypoints = [Point(x: 480, y: 195), Point(x: 510, y: 195)]
    let clip = try DiagramClipboard.decode(DiagramClipboard.capture("platform", from: original).encoded())
    try expect(Set(clip.content.nodes.keys) == ["ingestion", "lakehouse", "catalog"])
    try expect(Set(clip.content.connectors.keys) == ["store", "govern"])
    var d = original
    let id = try clip.paste(into: d.root, at: Point(x: 900, y: 400), document: &d)
    let descendants = d.descendants(of: id)
    try expect(descendants.count == 5 && descendants.isDisjoint(with: original.descendants(of: "platform")))
    try expect(d.nodes.count == original.nodes.count + 3 && d.connectors.count == original.connectors.count + 2)
    try expect(d.containers[id]?.fontSize == 24 && d.containers[id]?.allowedChildTypes == original.containers["platform"]?.allowedChildTypes)
    try expect(Set(d.containers[id]!.layout.cells!.keys) == Set(d.containers[id]!.children))
    for child in descendants where d.containers[child] != nil {
        try expect(Set(d.containers[child]!.layout.cells!.keys) == Set(d.containers[child]!.children))
    }
    for child in descendants where d.nodes[child]?.shape == .cylinder {
        try expect(d.nodes[child]?.fontSize == 28 && d.nodes[child]?.strokeWidth == 4)
        try expect(d.nodes[child]?.asset == original.nodes["lakehouse"]?.asset)
    }
    for (key, edge) in d.connectors where original.connectors[key] == nil {
        try expect(descendants.contains(edge.from.element) && descendants.contains(edge.to.element))
    }
    for (key, node) in original.nodes { try expect(d.nodes[key] == node) }
    for (key, edge) in original.connectors { try expect(d.connectors[key] == edge) }
    try expect(d.assets == original.assets && d.theme == original.theme)
    try expect(try Diagram.decode(d.encoded()) == d)
    _ = try Renderer.svg(d)
    let again = try clip.paste(into: d.root, at: Point(x: 925, y: 425), document: &d)
    try expect(d.descendants(of: again).isDisjoint(with: descendants))
}

func clipboardPreservesAssetsAcrossFilesAndRejectsInvalidTargets() throws {
    let source = Library.sample()
    let clip = try DiagramClipboard.capture("lakehouse", from: source)
    var target = Diagram(theme: .init(preset: .blueprint))
    target.assets = source.assets; target.assets["databricks"]?.name = "Different embedded mark"
    let before = target
    let id = try clip.paste(into: target.root, at: Point(x: 50, y: 60), document: &target)
    try expect(target.nodes.count == 1 && target.connectors.isEmpty && target.assets.count == before.assets.count + 1)
    try expect(target.nodes[id]?.asset != "databricks" && target.assets["databricks"] == before.assets["databricks"])
    try expect(target.assets[target.nodes[id]!.asset!] == source.assets["databricks"])
    try expect(target.nodes[id]?.shape == .cylinder && target.nodes[id]?.label == "Lakehouse")
    try expect(target.theme == before.theme && target.nodes[id]?.position == Point(x: 50, y: 60))
    _ = try Renderer.png(target, scale: 0.3)
    target.containers["restricted"] = Container(allowedChildTypes: ["application"])
    target.containers[target.root]?.children.append("restricted")
    let restricted = target
    try expectThrows { _ = try clip.paste(into: "restricted", at: Point(), document: &target) }
    try expect(target == restricted)
    try expectThrows { _ = try clip.paste(into: "missing", at: Point(), document: &target) }
    try expect(target == restricted)
    var object = try JSONSerialization.jsonObject(with: clip.encoded()) as! [String: Any]
    object["version"] = 99
    try expectThrows { _ = try DiagramClipboard.decode(JSONSerialization.data(withJSONObject: object)) }
    try expectThrows { _ = try DiagramClipboard.capture(source.root, from: source) }
}

func clipboardConnectionsRetainEndpointsAndManualRoutes() throws {
    var d = Library.sample()
    d.connectors["query"]?.waypoints = [Point(x: 620, y: 300)]
    d.connectors["query"]?.strokeWidth = 3; d.connectors["query"]?.fontSize = 26
    let original = d, clip = try DiagramClipboard.capture("query", from: d)
    let id = try clip.paste(into: d.root, at: Point(x: 100, y: 100), document: &d)
    try expect(d.connectors[id] == original.connectors["query"])
    try expect(d.nodes == original.nodes && d.containers == original.containers && d.assets == original.assets)
    var other = Library.sample(); other.id = "other-file"
    let before = other
    try expectThrows { _ = try clip.paste(into: other.root, at: Point(), document: &other) }
    try expect(other == before)
    d.remove("assistant")
    let deleted = d
    try expectThrows { _ = try clip.paste(into: d.root, at: Point(), document: &d) }
    try expect(d == deleted)
}

func fontSizeEditsAffectOnlyTheirTargetAndResetToDefaults() throws {
    let original = Library.sample()
    for (id, collection) in [("sources", "nodes"), ("platform", "containers"), ("query", "connectors")] {
        var d = original, expected = original
        try DiagramEditing.setFontSize(30, element: id, document: &d)
        if collection == "nodes" { expected.nodes[id]?.fontSize = 30 }
        else if collection == "containers" { expected.containers[id]?.fontSize = 30 }
        else { expected.connectors[id]?.fontSize = 30 }
        try expect(d == expected && d.theme == original.theme)
        try expect(try Diagram.decode(d.encoded()) == d)
        try expect(d.fontSize(for: id) == 30 && d.fontSize(for: "ingestion") == original.theme.fontSize)
        try expect(d.fontSizeOverride(for: "ingestion") == nil)
        d.theme.fontSize = 22
        try expect(d.fontSize(for: id) == 30 && d.fontSize(for: "ingestion") == 22)
        d.theme = original.theme
        try DiagramEditing.setFontSize(nil, element: id, document: &d)
        try expect(d == original)
        let fallback = collection == "nodes" ? original.theme.fontSize : collection == "containers" ? 14 : 12
        try expect(d.fontSize(for: id) == fallback)
        for size in [9.9, 36.1, Double.infinity, Double.nan] {
            try expectThrows { try DiagramEditing.setFontSize(size, element: id, document: &d) }
            try expect(d == original)
        }
        for invalid in ["large", NSNull()] as [Any] {
            var object = try JSONSerialization.jsonObject(with: d.encoded()) as! [String: Any]
            var entries = object[collection] as! [String: [String: Any]]
            entries[id]?["fontSize"] = invalid; object[collection] = entries
            do { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)); throw CheckFailure(description: "Invalid item text size accepted") }
            catch DiagramError.invalid(let issues) { try expect(issues.first?.path == "$.\(collection).\(id).fontSize") }
        }
        for size in [9.0, 37] {
            var object = try JSONSerialization.jsonObject(with: d.encoded()) as! [String: Any]
            var entries = object[collection] as! [String: [String: Any]]
            entries[id]?["fontSize"] = size; object[collection] = entries
            do { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)); throw CheckFailure(description: "Out-of-range item text size accepted") }
            catch DiagramError.invalid(let issues) { try expect(issues.contains { $0.code == "numeric-range" && $0.path == "$.\(collection).\(id).fontSize" && $0.element == id }) }
        }
    }
    var d = original
    for id in [d.root, "missing"] {
        try expectThrows { try DiagramEditing.setFontSize(30, element: id, document: &d) }
        try expect(d == original)
    }
}

func perElementFontSizesReachExportsWithoutChangingOtherLabels() throws {
    var original = Diagram(theme: Theme(fontFamily: "Helvetica"))
    original.nodes = ["a": Node(label: "Customers\nOrders", shape: .cylinder, position: Point(), width: 500, height: 360),
                      "b": Node(label: "Other system", position: Point(x: 850, y: 0), width: 400, height: 360)]
    original.containers["boundary"] = Container(label: "Boundary", position: Point(x: 0, y: 460), width: 500, height: 360)
    original.containers[original.root]?.children = ["a", "b", "boundary"]
    original.connectors["edge"] = Connector(from: Endpoint("a", side: .right), to: Endpoint("b", side: .left), label: "HTTPS")
    for (preset, isSketch) in themeVariants {
        var plain = original; plain.theme.preset = preset; plain.theme.sketch = isSketch
        let before = try Renderer.scene(plain), png = try Renderer.png(plain, scale: 0.5)
        for id in ["a", "boundary", "edge"] {
            var changed = plain
            try DiagramEditing.setFontSize(32, element: id, document: &changed)
            let after = try Renderer.scene(changed)
            try expect(after.layout.frames == before.layout.frames && after.layout.routes == before.layout.routes)
            try expect(after.drawings.count == before.drawings.count)
            let different = zip(before.drawings, after.drawings).filter { $0.path.svgData != $1.path.svgData }
            try expect(different.count == (id == "edge" ? 2 : 1))
            let text = different.last!.1
            try expect(text.stroke == nil && text.path.boundingBoxOfPath.height > different.last!.0.path.boundingBoxOfPath.height)
            let svg = try Renderer.svg(changed)
            try expect(String(decoding: svg, as: UTF8.self).contains(text.path.svgData))
            try expect(try Renderer.png(changed, scale: 0.5) != png)
            try expect(try Diagram.decode(changed.encoded()) == changed)
            for other in ["a", "b", "boundary", "edge"] where other != id {
                try expect(CTFontGetSize(Typography.font(changed, for: other)) == CTFontGetSize(Typography.font(plain, for: other)))
            }
            try DiagramEditing.setFontSize(nil, element: id, document: &changed)
            try expect(changed == plain && Renderer.svg(changed) == Renderer.svg(plain))
        }
    }
}

func individualLargeLabelsFitShapesContainersAndConnectors() throws {
    for (preset, isSketch) in themeVariants {
        for family in [nil, "Helvetica-Oblique"] as [String?] {
            let theme = Theme(preset: preset, sketch: isSketch, fontFamily: family, fontSize: 12)
            for shape in [Shape.rectangle, .cylinder, .file, .xlsx, .pdf, .docx, .queue, .actor] {
                var d = Diagram(theme: theme)
                d.nodes["a"] = Node(label: "Large label gjpqy\nSecond line", shape: shape, fontSize: 36)
                d.containers[d.root]?.children = ["a"]
                let scene = try Renderer.scene(d), glyphs = scene.drawings.last!.path.boundingBoxOfPath, frame = scene.layout.frames["a"]!
                let inset: CGFloat = shape == .actor ? 4 : 10
                try expect(frame.insetBy(dx: inset, dy: inset).contains(glyphs))
                if shape == .cylinder { try expect(glyphs.minY > scene.drawings[1].path.boundingBoxOfPath.maxY + 8) }
                try expect(d.theme.fontSize == 12)
            }
            var d = Diagram(theme: theme)
            d.nodes["a"] = Node(label: "Unchanged child")
            d.nodes["b"] = Node(label: "Other system", position: Point(x: 1100, y: 100))
            d.containers["group"] = Container(label: "Long container heading\nSecond line gjpqy", layout: .init(padding: 0), children: ["a"], fontSize: 36)
            d.containers[d.root]?.children = ["group", "b"]
            d.connectors["edge"] = Connector(from: Endpoint("group", side: .right), to: Endpoint("b", side: .left), label: "Long connection label\nSecond line gjpqy", fontSize: 36)
            let scene = try Renderer.scene(d), title = scene.drawings.first { $0.fill == 0.36 }!.path.boundingBoxOfPath
            try expect(title.maxY + 5 < scene.layout.frames["a"]!.minY)
            try expect(scene.layout.frames["group"]!.insetBy(dx: 8, dy: 8).contains(title))
            let edgeText = scene.drawings.last!.path.boundingBoxOfPath
            try expect(scene.layout.labelFrames["edge"]!.contains(edgeText))
            try expect(d.fontSize(for: "a") == 12)
            try expectRightAngleAttachments(scene.layout.routes["edge"]!, source: .right, destination: .left)
        }
    }
}

func legacyThemesPreserveAppearanceAndSaveSeparateSettings() throws {
    let source = Library.sample()
    var object = try JSONSerialization.jsonObject(with: source.encoded()) as! [String: Any]
    for saved in ["signature-sketch", "standard", "blueprint", "dark"] {
        var theme = object["theme"] as! [String: Any]
        theme.removeValue(forKey: "sketch"); theme["preset"] = saved
        object["theme"] = theme
        let decoded = try Diagram.decode(JSONSerialization.data(withJSONObject: object))
        var expected = source
        expected.theme.preset = ThemePreset(rawValue: saved) ?? .standard
        expected.theme.sketch = saved == "signature-sketch"
        try expect(decoded == expected)
        let canonical = try JSONSerialization.jsonObject(with: decoded.encoded()) as! [String: Any]
        let settings = canonical["theme"] as! [String: Any]
        try expect(settings["preset"] as? String == expected.theme.preset.rawValue)
        try expect(settings["sketch"] as? Bool == expected.theme.sketch)
        try expect(try Diagram.decode(decoded.encoded()) == expected)
        // An explicit toggle overrides the legacy default, even for signature-sketch.
        theme["sketch"] = !expected.theme.sketch; object["theme"] = theme
        try expect(try Diagram.decode(JSONSerialization.data(withJSONObject: object)).theme.sketch == !expected.theme.sketch)
    }
    object["theme"] = [:] as [String: Any]
    try expect(try Diagram.decode(JSONSerialization.data(withJSONObject: object)).theme == Theme())
    object.removeValue(forKey: "theme")
    try expect(try Diagram.decode(JSONSerialization.data(withJSONObject: object)).theme == Theme())
    try expect(Theme().preset == .standard && Theme().sketch)
}

func sketchSettingHasStrictBooleanValidation() throws {
    var object = try JSONSerialization.jsonObject(with: Library.sample().encoded()) as! [String: Any]
    var theme = object["theme"] as! [String: Any]
    for invalid in ["true", 1, NSNull()] as [Any] {
        theme["sketch"] = invalid; object["theme"] = theme
        do { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)); throw CheckFailure(description: "Invalid sketch setting accepted") }
        catch DiagramError.invalid(let issues) { try expect(issues.first?.path == "$.theme.sketch") }
    }
    theme["sketch"] = false; theme["preset"] = "invented-theme"; object["theme"] = theme
    do { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)); throw CheckFailure(description: "Invalid color theme accepted") }
    catch DiagramError.invalid(let issues) { try expect(issues.first?.path == "$.theme.preset") }
    let schema = try JSONSerialization.jsonObject(with: Library.schema()) as! [String: Any]
    let definitions = schema["$defs"] as! [String: [String: Any]]
    let properties = definitions["theme"]!["properties"] as! [String: [String: Any]]
    try expect(properties["sketch"]?["type"] as? String == "boolean")
}

func brandThemesKeepReadableSemanticColorsInPNGAndSVG() throws {
    for (preset, paper, container, surface, ink, accent, outline) in [
        (ThemePreset.secondStack, "#0b0d10", "#0b0d10", "#14171b", "#f4f6f8", "#2fb5f4", "#f4f6f8"),
        (.eightFDE, "#ffffff", "#ffffff", "#ffffff", "#111827", "#5d4be8", "#0c6e85")
    ] {
        for isSketch in [false, true] {
            var d = Library.sample(); d.theme.preset = preset; d.theme.sketch = isSketch; d.watermark = true
            let before = d, scene = try Renderer.scene(d), palette = scene.palette
            try expect(palette.backgroundHex == paper)
            try expect(palette.hex(1, role: .container) == container && palette.hex(1, role: .surface) == surface)
            try expect(palette.hex(0.12) == ink && palette.hex(0.32, role: .accent) == accent && palette.hex(0.14, role: .outline) == outline)
            try expect(scene.drawings.filter { $0.stroke == 0.32 || $0.stroke == 0.46 }.allSatisfy { $0.strokeRole == .accent })
            try expect(scene.drawings.filter { $0.fill == 0.12 }.allSatisfy { $0.fillRole == .neutral })
            for (gray, role) in [(CGFloat(1), PaintRole.neutral), (1, .container), (1, .surface), (0.12, .neutral), (0.32, .accent), (0.14, .outline)] {
                let color = palette.color(gray, role: role).components!, hex = palette.hex(gray, role: role)
                let value = UInt32(hex.dropFirst(), radix: 16)!
                try expect(Int((color[0] * 255).rounded()) == Int((value >> 16) & 255))
                try expect(Int((color[1] * 255).rounded()) == Int((value >> 8) & 255))
                try expect(Int((color[2] * 255).rounded()) == Int(value & 255))
            }
            let svg = String(decoding: try Renderer.svg(d), as: UTF8.self)
            try expect(svg.contains("stroke=\"\(accent)\"") && svg.contains("fill=\"\(accent)\""))
            try expect(svg.contains("fill=\"\(ink)\"") && svg.contains("fill=\"\(container)\"") && svg.contains("fill=\"\(surface)\""))
            try expect(svg.contains("stroke=\"\(outline)\""))
            try expect(!svg.contains("blueprint-paper"))
            let source = CGImageSourceCreateWithData(try Renderer.png(d, scale: 1) as CFData, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
            for hex in Set([paper, container, surface, ink, accent, outline]) {
                let value = UInt32(hex.dropFirst(), radix: 16)!, r = UInt8((value >> 16) & 255), g = UInt8((value >> 8) & 255), b = UInt8(value & 255)
                var matches = 0
                for i in stride(from: 0, to: image.width * image.height * 4, by: 4) {
                    if bytes[i] == r && bytes[i + 1] == g && bytes[i + 2] == b && bytes[i + 3] == 255 { matches += 1 }
                }
                try expect(matches > 100)
            }
            let transparent = String(decoding: try Renderer.svg(d, transparent: true), as: UTF8.self)
            try expect(!transparent.contains("<rect") && transparent.contains("opacity=\"0.400\""))
            try expect(d == before && Diagram.decode(d.encoded()) == d)
        }
    }
}

func eightFDEUsesBrandShapeLinesAndWhiteContainers() throws {
    for isSketch in [false, true] {
        var d = Diagram(theme: Theme(preset: .eightFDE, sketch: isSketch, fontFamily: "Helvetica"))
        d.containers["objects"] = Container(label: "Objects", layout: .init(mode: .grid, gap: 60, rows: 2, columns: 5), children: Shape.allCases.map(\.rawValue))
        d.containers[d.root]?.children = ["objects"]
        for shape in Shape.allCases { d.nodes[shape.rawValue] = Node(label: shape.title, shape: shape) }
        d.connectors["relationship"] = Connector(from: Endpoint("rectangle", side: .right), to: Endpoint("roundedRectangle", side: .left), label: "unchanged")
        let original = d, scene = try Renderer.scene(d)
        let shapes = scene.drawings.filter { $0.stroke == 0.14 }
        try expect(shapes.count > Shape.allCases.count)
        try expect(shapes.allSatisfy { $0.strokeRole == .outline && scene.palette.hex($0.stroke!, role: $0.strokeRole) == "#0c6e85" })
        let containers = scene.drawings.filter { $0.fillRole == .container }
        try expect(containers.count == 1 && containers.allSatisfy { scene.palette.hex($0.fill!, role: $0.fillRole) == "#ffffff" })
        let relationships = scene.drawings.filter { $0.stroke == 0.32 }
        try expect(relationships.count == 2 && relationships.allSatisfy { scene.palette.hex($0.stroke!, role: $0.strokeRole) == "#5d4be8" })
        try expect(scene.drawings.filter { $0.fill == 0.12 }.allSatisfy { scene.palette.hex($0.fill!, role: $0.fillRole) == "#111827" })
        var standard = d; standard.theme.preset = .standard
        let standardScene = try Renderer.scene(standard)
        try expect(scene.layout.frames == standardScene.layout.frames && scene.layout.routes == standardScene.layout.routes)
        try expect(zip(scene.drawings, standardScene.drawings).allSatisfy { $0.path == $1.path })
        try expect(d == original && Diagram.decode(d.encoded()) == original)
    }
}

func brandThemesPreserveWhiteLogoContrastAndSchemaChoices() throws {
    let schema = try JSONSerialization.jsonObject(with: Library.schema()) as! [String: Any]
    let definitions = schema["$defs"] as! [String: [String: Any]]
    let properties = definitions["theme"]!["properties"] as! [String: [String: Any]]
    try expect(Set(properties["preset"]!["enum"] as! [String]) == Set(ThemePreset.allCases.map(\.rawValue) + ["signature-sketch"]))
    for preset in [ThemePreset.secondStack, .eightFDE] {
        var d = Library.sample(); d.theme.preset = preset
        for id in d.nodes.keys where d.nodes[id]?.asset != nil { d.nodes[id]?.variant = .black }
        let black = try Renderer.svg(d)
        for id in d.nodes.keys where d.nodes[id]?.asset != nil { d.nodes[id]?.variant = .white }
        let white = try Renderer.svg(d)
        if preset == .secondStack { try expect(white == black) }
        else {
            let scene = try Renderer.scene(d)
            try expect(white != black && scene.drawings.contains { $0.fill == 0.15 })
            try expect(scene.palette.hex(0.15) == "#111827" && scene.palette.hex(1) == "#ffffff")
        }
        let original = d
        d.theme.preset = .standard; d.theme.preset = preset
        try expect(d == original && Diagram.decode(d.encoded()) == d)
    }
}

func allColorThemesSupportIndependentSketchAndCleanExports() throws {
    var source = Library.sample(); source.theme.fontFamily = "Helvetica-Oblique"; source.watermark = true
    source.nodes["lakehouse"]?.strokeWidth = 2.8
    source.connectors["query"]?.strokeWidth = 4
    var exports: Set<Data> = []
    for preset in ThemePreset.allCases {
        var clean = source; clean.theme.preset = preset; clean.theme.sketch = false
        var sketch = clean; sketch.theme.sketch = true
        let before = sketch, a = try Renderer.scene(clean), b = try Renderer.scene(sketch)
        let paper = preset == .secondStack ? "#0b0d10" : preset == .blueprint ? "#0b3d91" : preset == .dark ? "#181818" : "#ffffff"
        try expect(a.palette.backgroundHex == paper && b.palette.backgroundHex == paper)
        try expect(a.layout.frames == b.layout.frames && a.layout.routes == b.layout.routes && a.layout.bounds == b.layout.bounds)
        try expect(a.drawings.count == b.drawings.count)
        for (exact, hand) in zip(a.drawings, b.drawings) {
            try expect(exact.width == hand.width && exact.dashed == hand.dashed && exact.fill == hand.fill && exact.stroke == hand.stroke)
            try expect(exact.fillRole == hand.fillRole && exact.strokeRole == hand.strokeRole)
            if exact.stroke == nil { try expect(exact.path.svgData == hand.path.svgData) }
        }
        let edge = b.drawings.first { $0.stroke == 0.32 }!
        let route = b.layout.routes[clean.connectors.keys.sorted().first!]!
        try expectSketchConnector(edge.path, follows: route)
        try expect(a.drawings.first { $0.stroke == 0.32 }!.path.svgData != edge.path.svgData)
        for d in [clean, sketch] {
            let svg = try Renderer.svg(d), text = String(decoding: svg, as: UTF8.self)
            try expect(exports.insert(svg).inserted)
            try expect(text.contains("fill=\"\(paper)\""))
            try expect(text.contains("id=\"blueprint-grid\"") == (preset == .blueprint))
            try expect(try Renderer.svg(d) == svg && Diagram.decode(d.encoded()) == d)
            try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 0.5) as CFData, nil) != nil)
            try expect(CTFontCopyPostScriptName(Typography.font(d.theme)) as String == "Helvetica-Oblique")
            var automatic = d.theme; automatic.fontFamily = nil
            let expectedFont = d.theme.sketch ? "ChalkboardSE-Regular" : preset == .blueprint ? "Menlo-Regular" : "Helvetica"
            try expect(CTFontCopyPostScriptName(Typography.font(automatic)) as String == expectedFont)
        }
        try expect(sketch == before)
        sketch.theme.sketch = false
        try expect(sketch == clean)
    }
    try expect(exports.count == 10)
}

func canonicalRoundTrip() throws {
    let original = Library.sample()
    let data = try original.encoded()
    let decoded = try Diagram.decode(data)
    try expect(decoded == original)
    try expect(try decoded.encoded() == data)
}

func missingEndpointReportsFieldAndID() throws {
    var d = Library.sample()
    d.connectors["ingest"]?.to.element = "missing"
    let issues = Validator.validate(d)
    try expect(issues.contains { $0.code == "missing-endpoint" && $0.path == "$.connectors.ingest.to.element" && $0.element == "ingest" })
}

func cyclesAndMultipleOwnershipAreRejected() throws {
    var d = Library.sample()
    d.containers["platform"]?.children.append(d.root)
    d.containers[d.root]?.children.append("lakehouse")
    let issues = Validator.validate(d)
    try expect(issues.contains { $0.code == "containment-cycle" })
    try expect(issues.contains { $0.code == "ownership" && $0.element == "lakehouse" })
}

func nestingLimitDoesNotDependOnIDOrder() throws {
    var d = Diagram(root: "zz-canvas")
    var parent = d.root
    for level in 0..<40 {
        let id = String(format: "a-%02d", level)
        d.containers[id] = Container()
        d.containers[parent]?.children.append(id)
        parent = id
    }
    try expect(Validator.validate(d).contains { $0.code == "nesting-limit" })
}

func invalidReparentLeavesOriginalIntact() throws {
    var d = Library.sample()
    let before = d
    try expectThrows { try DiagramEditing.reparent("assistant", into: "platform", position: nil, document: &d) }
    try expect(d == before)
    try expectThrows { try DiagramEditing.reparent("platform", into: "platform", position: nil, document: &d) }
    try expect(d == before)
}

func externalConnectionsPreserveVerticalStack() throws {
    let d = Library.sample(), withEdges = try LayoutEngine.layout(d)
    var without = d; without.connectors = [:]
    let withoutEdges = try LayoutEngine.layout(without)
    try expect(withEdges.frames == withoutEdges.frames)
    try expect(withEdges.frames["ingestion"]!.midX == withEdges.frames["lakehouse"]!.midX)
    try expect(withEdges.frames["ingestion"]!.maxY < withEdges.frames["lakehouse"]!.minY)
}

func freeLayoutMaterializesStackPositions() throws {
    var d = Library.sample()
    let before = try LayoutEngine.layout(d)
    try DiagramEditing.setLayout(.free, container: "platform", document: &d)
    let after = try LayoutEngine.layout(d)
    for child in d.containers["platform"]!.children {
        try expect(before.frames[child] == after.frames[child])
        try expect(d.nodes[child]?.position != nil)
    }
}

func rootPlacementPreservesStacksAndConnections() throws {
    for mode in [LayoutMode.horizontal, .vertical] {
        var d = Library.sample()
        try DiagramEditing.setLayout(mode, container: d.root, document: &d)
        let before = try LayoutEngine.layout(d), edges = d.connectors
        try DiagramEditing.setLayout(.free, container: d.root, document: &d)
        let after = try LayoutEngine.layout(d)
        for id in before.order where id != d.root { try expect(before.frames[id] == after.frames[id]) }
        try expect(before.routes == after.routes && d.connectors == edges)
        try expect(d.containers["platform"]?.layout.mode == .vertical)
        for id in d.containers[d.root]!.children { try expect(d.nodes[id]?.position != nil || d.containers[id]?.position != nil) }
    }
}

func borderlessPlacementKeepsOtherItemsFixedAcrossTheOrigin() throws {
    var d = Library.sample()
    try DiagramEditing.setLayout(.free, container: d.root, document: &d)
    let initial = try LayoutEngine.layout(d)
    let movedIDs = d.descendants(of: "platform")
    for point in [CGPoint(x: -420, y: -340), CGPoint(x: 180, y: -240), CGPoint(x: -380, y: 160), CGPoint(x: 300, y: 220)] {
        let before = try LayoutEngine.layout(d), frame = before.frames["platform"]!
        let position = before.position(at: point, in: d.root, document: d)
        try DiagramEditing.reparent("platform", into: d.root, position: position, document: &d)
        let after = try LayoutEngine.layout(d)
        try expect(after.frames["platform"]!.origin == point)
        for id in initial.order where id != d.root {
            if movedIDs.contains(id) {
                try expect(after.frames[id] == before.frames[id]!.offsetBy(dx: point.x - frame.minX, dy: point.y - frame.minY))
            } else { try expect(after.frames[id] == initial.frames[id]) }
            try expect(after.bounds.contains(after.frames[id]!))
        }
        try expect(after.routes != before.routes)
        for points in after.routes.values {
            for (a, b) in zip(points, points.dropFirst()) { try expect(a.x == b.x || a.y == b.y) }
        }
    }
    let layout = try LayoutEngine.layout(d)
    let position = layout.position(at: CGPoint(x: -510, y: -410), in: d.root, document: d)
    try DiagramEditing.reparent("platform", into: d.root, position: position, document: &d)
    let beforePaste = try LayoutEngine.layout(d), clip = try DiagramClipboard.capture("platform", from: d)
    let pasteAt = beforePaste.position(at: CGPoint(x: clip.origin.x + 24, y: clip.origin.y + 24), in: d.root, document: d)
    let copy = try clip.paste(into: d.root, at: pasteAt, document: &d)
    let afterPaste = try LayoutEngine.layout(d)
    try expect(afterPaste.frames[copy]!.origin == CGPoint(x: -486, y: -386))
    for id in beforePaste.order where id != d.root { try expect(afterPaste.frames[id] == beforePaste.frames[id]) }
    let reopened = try Diagram.decode(d.encoded())
    try expect(try LayoutEngine.layout(reopened).frames == afterPaste.frames)
    try expect(try !Renderer.svg(reopened).isEmpty)
    try expect(CGImageSourceCreateWithData(try Renderer.png(reopened, scale: 0.3) as CFData, nil) != nil)
}

func placementCoordinatesRespectContainerHeadersAndCanvasFreedom() throws {
    var d = Library.sample()
    d.containers["platform"]?.fontSize = 36
    let before = try LayoutEngine.layout(d)
    try DiagramEditing.setLayout(.free, container: "platform", document: &d)
    let after = try LayoutEngine.layout(d), origin = after.contentOrigins["platform"]!
    for id in d.containers["platform"]!.children { try expect(after.frames[id] == before.frames[id]) }
    let frame = after.frames["platform"]!, padding = d.containers["platform"]!.layout.padding
    try expect(origin == CGPoint(x: frame.minX + padding, y: frame.minY + padding + Typography.containerHeaderHeight(d.containers["platform"]!, theme: d.theme)))
    try expect(after.position(at: CGPoint(x: origin.x - 100, y: origin.y - 100), in: "platform", document: d) == Point())
    let canvasOrigin = after.contentOrigins[d.root]!
    try expect(after.position(at: CGPoint(x: canvasOrigin.x - 100, y: canvasOrigin.y - 100), in: d.root, document: d) == Point(x: -100, y: -100))
    // Keyboard nudging must also use the rendered position when a file omits explicit coordinates.
    d.nodes["sources"]?.position = nil
    let implicit = try LayoutEngine.layout(d), source = implicit.frames["sources"]!
    let nudge = implicit.position(at: CGPoint(x: source.minX - 10, y: source.minY - 10), in: d.root, document: d)
    try DiagramEditing.reparent("sources", into: d.root, position: nudge, document: &d)
    try expect(try LayoutEngine.layout(d).frames["sources"] == source.offsetBy(dx: -10, dy: -10))
}

func wideContainersCanSpanBelowTheDiagram() throws {
    var d = Library.sample()
    try DiagramEditing.setLayout(.horizontal, container: d.root, document: &d)
    let before = try LayoutEngine.layout(d)
    try DiagramEditing.setLayout(.free, container: d.root, document: &d)
    d.nodes["metrics"] = Node(label: "Metrics")
    d.nodes["logs"] = Node(label: "Logs")
    d.containers["monitoring"] = Container(label: "Monitoring", layout: .init(mode: .horizontal), children: ["metrics", "logs"])
    d.containers[d.root]?.children.append("monitoring")
    try DiagramEditing.placeContainerBelow("monitoring", document: &d)
    let layout = try LayoutEngine.layout(d), band = layout.frames["monitoring"]!
    let main = d.containers[d.root]!.children.filter { $0 != "monitoring" }.reduce(CGRect.null) { $0.union(layout.frames[$1]!) }
    try expect(band.minX == main.minX && band.width >= main.width && band.minY >= main.maxY + 48)
    for id in before.order where id != d.root { try expect(before.frames[id] == layout.frames[id]) }
    try expect(layout.frames["metrics"]!.midY == layout.frames["logs"]!.midY)
    try expect(band.contains(layout.frames["metrics"]!) && band.contains(layout.frames["logs"]!))
    d.connectors["observe"] = Connector(from: Endpoint("lakehouse", side: .bottom), to: Endpoint("metrics", side: .top))
    let connected = try LayoutEngine.layout(d)
    try expectRightAngleAttachments(connected.routes["observe"]!, source: .bottom, destination: .top)
    let point = d.containers["monitoring"]!.position!
    try DiagramEditing.reparent("monitoring", into: d.root, position: Point(x: point.x, y: point.y + 60), document: &d)
    let moved = try LayoutEngine.layout(d)
    for id in before.order where id != d.root { try expect(before.frames[id] == moved.frames[id]) }
    try expect(moved.frames["metrics"]!.minY == connected.frames["metrics"]!.minY + 60)
    try expect(connected.routes["observe"] != moved.routes["observe"])
    try expectRightAngleAttachments(moved.routes["observe"]!, source: .bottom, destination: .top)
    let decoded = try Diagram.decode(d.encoded())
    let reopened = try LayoutEngine.layout(decoded)
    try expect(decoded == d && reopened.frames == moved.frames)
    for (preset, isSketch) in themeVariants {
        d.theme.preset = preset; d.theme.sketch = isSketch
        let scene = try Renderer.scene(d)
        try expect(scene.layout.frames["monitoring"]!.width >= main.width)
        try expect(try !Renderer.svg(d).isEmpty)
        try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 1) as CFData, nil) != nil)
    }
}

func belowPlacementHandlesNegativeAndInvalidTargets() throws {
    var d = Diagram()
    d.nodes["main"] = Node(position: Point(x: -100, y: -50))
    d.containers["band"] = Container(label: "Band", position: Point(x: -250, y: -150))
    d.containers[d.root]?.children = ["main", "band"]
    let before = try LayoutEngine.layout(d)
    try DiagramEditing.placeContainerBelow("band", document: &d)
    let after = try LayoutEngine.layout(d)
    try expect(before.frames["main"] == after.frames["main"])
    try expect(after.frames["band"]!.minY > after.frames["main"]!.maxY)
    for id in [d.root, "main", "missing"] {
        let original = d
        try expectThrows { try DiagramEditing.placeContainerBelow(id, document: &d) }
        try expect(d == original)
    }
    var empty = Diagram()
    empty.containers["band"] = Container()
    empty.containers[empty.root]?.children = ["band"]
    try DiagramEditing.placeContainerBelow("band", document: &empty)
    try expect(try LayoutEngine.layout(empty).frames["band"]!.width == 640)
    d.containers["band"]?.width = 100001
    let invalid = d
    try expectThrows { try DiagramEditing.placeContainerBelow("band", document: &d) }
    try expect(d == invalid)
}

func containerMinimumSizesRoundTripAndExpand() throws {
    var d = Diagram()
    d.nodes["a"] = Node(label: "A"); d.nodes["b"] = Node(label: "B")
    d.containers["band"] = Container(layout: .init(mode: .horizontal), children: ["a", "b"], width: 1200, height: 200)
    d.containers[d.root]?.children = ["band"]
    let layout = try LayoutEngine.layout(d)
    try expect(layout.frames["band"]!.size == CGSize(width: 1200, height: 200))
    try expect(try Diagram.decode(d.encoded()) == d)
    d.containers["band"]?.width = 20; d.containers["band"]?.height = 20
    let expanded = try LayoutEngine.layout(d)
    try expect(expanded.frames["band"]!.width > 20 && expanded.frames["band"]!.height > 20)
    for child in ["a", "b"] { try expect(expanded.frames["band"]!.contains(expanded.frames[child]!)) }
    for dimension in ["width", "height"] {
        for value in [19.0, 100001.0, Double.infinity, Double.nan] {
            if dimension == "width" { d.containers["band"]?.width = value }
            else { d.containers["band"]?.height = value }
            try expect(Validator.validate(d).contains { $0.path == "$.containers.band.\(dimension)" && $0.code == "numeric-range" })
        }
        d.containers["band"]?.width = nil; d.containers["band"]?.height = nil
    }
}

func sketchSVGIsDeterministicAndSelfContained() throws {
    let d = Library.sample()
    let a = try Renderer.svg(d), b = try Renderer.svg(d)
    try expect(a == b)
    let text = String(decoding: a, as: UTF8.self)
    try expect(!text.contains("<text"))
    try expect(!text.contains("font-family"))
    try expect(text.contains("<path"))
    var standard = d; standard.theme.preset = .standard; standard.theme.sketch = false
    try expect(try Renderer.svg(standard) != a)
}

func sketchStrokesAreVisibleWithTheSameCustomFont() throws {
    for shape in Shape.allCases where shape != .text {
        var standard = Diagram()
        standard.theme = Theme(preset: .standard, sketch: false, fontFamily: "ChalkboardSE-Regular")
        standard.nodes["symbol"] = Node(label: "System", shape: shape)
        standard.containers[standard.root]?.children = ["symbol"]
        var sketch = standard; sketch.theme.sketch = true
        let before = sketch, clean = try Renderer.scene(standard), hand = try Renderer.scene(sketch)
        try expect(hand.layout.frames == clean.layout.frames && hand.layout.routes == clean.layout.routes)
        try expect(hand.drawings.count == clean.drawings.count)
        for (a, b) in zip(clean.drawings, hand.drawings) {
            if a.stroke != nil { try expect(a.path.svgData != b.path.svgData) }
            else { try expect(a.path.svgData == b.path.svgData) }
            try expect(a.width == b.width && a.fill == b.fill && a.stroke == b.stroke)
        }
        // Check the rendered contrast at a common zoom, independent of typography differences.
        func pixels(_ document: Diagram) throws -> [UInt8] {
            let data = try Renderer.png(document, scale: 0.5)
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                   bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Array(UnsafeBufferPointer(start: bitmap.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
        }
        let a = try pixels(standard), b = try pixels(sketch)
        try expect(a.count == b.count)
        let changed = stride(from: 0, to: a.count, by: 4).filter { abs(Int(a[$0]) - Int(b[$0])) > 40 }.count
        let minimumContrast = shape == .actor ? 20 : 30
        guard changed >= minimumContrast else { throw CheckFailure(description: "Sketch \(shape.rawValue) has only \(changed) visibly changed pixels at 50% zoom") }
        let exported = try Renderer.svg(sketch)
        try expect(try Renderer.svg(sketch) == exported)
        sketch.theme.seed += 1
        try expect(try Renderer.svg(sketch) != exported)
        try expect(before == Diagram.decode(before.encoded()))
    }
}

func expectSketchConnector(_ path: CGPath, follows route: [CGPoint]) throws {
    var current = CGPoint.zero
    var segments: [(start: CGPoint, end: CGPoint, controls: [CGPoint])] = []
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: current = e.points[0]
        case .addLineToPoint:
            segments.append((current, e.points[0], [])); current = e.points[0]
        case .addCurveToPoint:
            segments.append((current, e.points[2], [e.points[0], e.points[1]])); current = e.points[2]
        default: break
        }
    }
    try expect(segments.first?.start == route.first && segments.last?.end == route.last)
    try expect(segments.first!.controls.isEmpty && segments.last!.controls.isEmpty)
    let first = segments.first!, last = segments.last!
    try expect(route[0].x == route[1].x ? first.start.x == first.end.x : first.start.y == first.end.y)
    try expect(route[route.count - 2].x == route.last!.x ? last.start.x == last.end.x : last.start.y == last.end.y)
    for point in route.dropFirst() { try expect(segments.contains { $0.end == point }) }
    for (index, segment) in segments.enumerated() {
        if let vertex = route.dropFirst().dropLast().firstIndex(of: segment.end) {
            let departure = segments[index + 1]
            try expect(segment.controls.isEmpty && departure.controls.isEmpty)
            let incoming = CGPoint(x: route[vertex].x - route[vertex - 1].x, y: route[vertex].y - route[vertex - 1].y)
            let outgoing = CGPoint(x: route[vertex + 1].x - route[vertex].x, y: route[vertex + 1].y - route[vertex].y)
            let a = CGPoint(x: segment.end.x - segment.start.x, y: segment.end.y - segment.start.y)
            let b = CGPoint(x: departure.end.x - departure.start.x, y: departure.end.y - departure.start.y)
            try expect(a.x * incoming.y == a.y * incoming.x && b.x * outgoing.y == b.y * outgoing.x)
        }
        // The entire Bezier control polygon stays within 1.1 points of the clean route.
        for point in [segment.start, segment.end] + segment.controls {
            let distance = zip(route, route.dropFirst()).map { a, b in
                let nearest = CGPoint(x: min(max(point.x, min(a.x, b.x)), max(a.x, b.x)),
                                      y: min(max(point.y, min(a.y, b.y)), max(a.y, b.y)))
                return hypot(point.x - nearest.x, point.y - nearest.y)
            }.min()!
            try expect(distance <= 1.100001)
        }
    }
}

func sketchConnectorsKeepRightAnglesAndShapeAttachments() throws {
    for shape in [Shape.rectangle, .roundedRectangle, .cylinder] {
        for side in [Side.left, .right, .top, .bottom] {
            var d = Diagram(); d.theme.fontFamily = "Helvetica"
            d.nodes = ["a": Node(shape: shape, position: Point()), "b": Node(position: Point(x: 400, y: 250))]
            d.containers[d.root]?.children = ["a", "b"]
            d.connectors["edge"] = Connector(from: Endpoint("a", side: side), to: Endpoint("b", side: .left))
            let scene = try Renderer.scene(d), route = scene.layout.routes["edge"]!
            let path = scene.drawings.first { $0.stroke == 0.32 }!.path
            let exact = CGMutablePath(); exact.move(to: route[0])
            for point in route.dropFirst() { exact.addLine(to: point) }
            try expect(path.svgData != exact.svgData)
            try expectSketchConnector(path, follows: route)
            let body = scene.drawings.first { $0.stroke == 0.14 && $0.fill == 1 }!.path
            var anchored = false
            body.applyWithBlock { element in
                let e = element.pointee
                guard e.type == .addCurveToPoint else { return }
                let end = e.points[2], handle = e.points[1]
                if hypot(end.x - route[0].x, end.y - route[0].y) < 0.000001 {
                    let deviation = side == .left || side == .right ? abs(handle.x - end.x) : abs(handle.y - end.y)
                    anchored = deviation < 0.000001
                }
            }
            try expect(anchored)
        }
    }
    var standard = Library.sample(); standard.theme.preset = .standard; standard.theme.sketch = false; standard.theme.fontFamily = "Helvetica"
    var sketch = standard; sketch.theme.sketch = true
    let clean = try Renderer.scene(standard), hand = try Renderer.scene(sketch)
    try expect(clean.layout.frames == hand.layout.frames && clean.layout.routes == hand.layout.routes)
    let cleanLabelsAndMarks = clean.drawings.filter { $0.stroke == nil && $0.fill == 0.12 }.map { $0.path.svgData }
    let handLabelsAndMarks = hand.drawings.filter { $0.stroke == nil && $0.fill == 0.12 }.map { $0.path.svgData }
    try expect(cleanLabelsAndMarks == handLabelsAndMarks)
    try expect(clean.drawings.first { $0.stroke == 0.46 }!.path.svgData != hand.drawings.first { $0.stroke == 0.46 }!.path.svgData)
}

func sketchStrokesStaySubtleAndConnectorsAreSeeded() throws {
    for shape in Shape.allCases where shape != .text {
        var d = Diagram(); d.theme.fontFamily = "Helvetica"; d.nodes["symbol"] = Node(shape: shape)
        d.containers[d.root]?.children = ["symbol"]
        for seed: UInt64 in [1, 42, 1000] {
            d.theme.seed = seed
            let hand = try Renderer.scene(d)
            var standard = d; standard.theme.preset = .standard; standard.theme.sketch = false
            let clean = try Renderer.scene(standard)
            for (a, b) in zip(clean.drawings, hand.drawings) where a.stroke != nil {
                try expect(a.path.boundingBoxOfPath.insetBy(dx: -1.500001, dy: -1.500001).contains(b.path.boundingBoxOfPath))
            }
        }
    }
    var d = Diagram()
    d.nodes = ["a": Node(position: Point()), "b": Node(position: Point(x: 500, y: 250))]
    d.containers[d.root]?.children = ["a", "b"]
    d.connectors["edge"] = Connector(from: Endpoint("a", side: .right), to: Endpoint("b", side: .left), direction: .both, dashed: true,
                                     waypoints: [Point(x: 320, y: 70), Point(x: 320, y: 260)])
    let before = d, hand = try Renderer.scene(d)
    let strokes = hand.drawings.filter { $0.stroke == 0.32 }
    try expect(strokes.count == 3 && strokes[0].dashed && !strokes[1].dashed && !strokes[2].dashed)
    try expectSketchConnector(strokes[0].path, follows: hand.layout.routes["edge"]!)
    let exported = try Renderer.svg(d)
    try expect(exported == Renderer.svg(d) && d == before)
    d.theme.seed += 1
    try expect(try Renderer.scene(d).drawings.first { $0.stroke == 0.32 }!.path.svgData != strokes[0].path.svgData)
    // Nearby items still have clean, perpendicular attachments on short segments.
    d.connectors["edge"]?.waypoints = nil; d.nodes["b"]?.position = Point(x: 198, y: 104)
    let close = try Renderer.scene(d)
    try expectSketchConnector(close.drawings.first { $0.stroke == 0.32 }!.path, follows: close.layout.routes["edge"]!)
}

func pngExportsRealPixelsAndTransparency() throws {
    let data = try Renderer.png(Library.sample(), scale: 1, transparent: true)
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    try expect(image.width > 500 && image.height > 300)
    try expect(image.alphaInfo != .none)
    try expectThrows { _ = try Renderer.png(Library.sample(), scale: 100) }
}

func unknownFieldsCannotBeSilentlyLost() throws {
    var object = try JSONSerialization.jsonObject(with: Library.sample().encoded()) as! [String: Any]
    object["futureSettings"] = true
    try expectThrows { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)) }
    object.removeValue(forKey: "futureSettings"); object["schemaVersion"] = 2
    try expectThrows { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)) }
}

func guardedWritesRejectStaleRevisions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("diagram.json"), d = Library.sample()
    let revision = try DiagramFiles.write(d, to: url)
    var modified = d; modified.title = "Manually changed"
    _ = try DiagramFiles.write(modified, to: url, expectedRevision: revision)
    try expectThrows { _ = try DiagramFiles.write(d, to: url, expectedRevision: revision) }
    try expect(try DiagramFiles.read(url).0.title == "Manually changed")
}

func svgPathSupportsArcsAndRejectsInvalidGeometry() throws {
    let path = try SVGPath.parse("M0 10 A10 10 0 0 1 20 10 L20 30 H0 Z")
    try expect(path.boundingBoxOfPath.width > 19)
    let compact = try SVGPath.parse("M0 10 A10 10 0 0120 10 L20 30 H0 Z")
    try expect(compact.svgData == path.svgData)
    try expectThrows { _ = try SVGPath.parse("M0 0 C1") }
    try expectThrows { _ = try SVGPath.parse("M0 0 R1 2") }
}

func deletingContainerRemovesDescendantsAndAttachedEdges() throws {
    var d = Library.sample(); d.remove("platform")
    try expect(d.nodes.count == 2)
    try expect(d.connectors.isEmpty)
    try expect(Validator.validate(d).isEmpty)
}

func bundledLibraryAssetsValidate() throws {
    try expect(Library.items().count >= 8)
    for item in Library.items() {
        var d = Diagram(); d.nodes[item.id] = item.node(); d.containers[d.root]?.children = [item.id]
        if let asset = item.asset { d.assets[item.id] = asset }
        try expect(Validator.validate(d).isEmpty)
    }
}

func denseNestedDiagramRenders() throws {
    var d = Diagram()
    d.containers[d.root]?.layout.mode = .horizontal
    for column in 0..<10 {
        let group = "group-\(column)"
        d.containers[group] = Container(label: "Group \(column)")
        d.containers[d.root]?.children.append(group)
        for row in 0..<20 {
            let id = "node-\(column)-\(row)"
            d.nodes[id] = Node(label: "System \(row)"); d.containers[group]?.children.append(id)
            if row > 0 { d.connectors["edge-\(id)"] = Connector(from: Endpoint("node-\(column)-\(row - 1)"), to: Endpoint(id)) }
        }
    }
    let scene = try Renderer.scene(d)
    try expect(scene.layout.frames.count == 211)
    try expect(scene.layout.routes.count == 190)
}

func connectorLabelsDoNotEraseNodeBorders() throws {
    let d = Library.sample(), layout = try LayoutEngine.layout(d)
    for rect in layout.labelFrames.values {
        for id in d.nodes.keys { try expect(!rect.intersects(layout.frames[id]!)) }
    }
}

func connectorLabelsStayNearTheRoute() throws {
    let d = Library.sample(), layout = try LayoutEngine.layout(d)
    for (id, rect) in layout.labelFrames {
        let points = layout.routes[id]!
        let nearSegment = zip(points, points.dropFirst()).contains { a, b in
            let segment = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            return segment.insetBy(dx: -60, dy: -60).intersects(rect)
        }
        try expect(nearSegment)
    }
}

func logoVariantsRoundTripAndRender() throws {
    for item in Library.items() where item.asset != nil {
        var d = Diagram(); d.nodes[item.id] = item.node(); d.nodes[item.id]?.variant = .white
        d.containers[d.root]?.children = [item.id]; d.assets[item.id] = item.asset!
        let output = try Renderer.svg(d)
        try expect(output.count > 1000)
        try expect(try Diagram.decode(d.encoded()).nodes[item.id]?.variant == .white)
    }
}

func malformedValuesReportPrecisePaths() throws {
    var object = try JSONSerialization.jsonObject(with: Library.sample().encoded()) as! [String: Any]
    var nodes = object["nodes"] as! [String: [String: Any]]
    nodes["sources"]?["shape"] = "invented-shape"; object["nodes"] = nodes
    do { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)); throw CheckFailure(description: "Invalid shape accepted") }
    catch DiagramError.invalid(let issues) { try expect(issues.first?.path == "$.nodes.sources.shape") }
    object["theme"] = NSNull()
    try expectThrows { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)) }
}

func blueprintExportsBluePaperAndWhiteInk() throws {
    var d = Library.sample(); d.theme.preset = .blueprint
    try expect(try Diagram.decode(d.encoded()).theme.preset == .blueprint)
    let svg = String(decoding: try Renderer.svg(d), as: UTF8.self)
    try expect(svg.contains("fill=\"#0b3d91\""))
    try expect(svg.contains("stroke=\"#ffffff\""))
    try expect(svg.contains("id=\"blueprint-grid\""))
    try expect(svg.contains("stroke-width=\"0.35\""))
    try expect(!svg.contains("#242424"))
    let source = CGImageSourceCreateWithData(try Renderer.png(d, scale: 1) as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
    var white = 0, paper = 0, grid = 0
    for i in stride(from: 0, to: image.width * image.height * 4, by: 4) {
        if bytes[i] == 255 && bytes[i + 1] == 255 && bytes[i + 2] == 255 { white += 1 }
        if bytes[i] == 11 && bytes[i + 1] == 61 && bytes[i + 2] == 145 { paper += 1 }
        if bytes[i] > 11 && bytes[i] < 50 && bytes[i + 1] > 61 && bytes[i + 1] < 100 && bytes[i + 2] > 145 && bytes[i + 2] < 175 { grid += 1 }
    }
    try expect(white > 100 && paper > 1000 && grid > 1000)
}

func darkExportsKeepInkReadableAndGeometryIntact() throws {
    var standard = Library.sample(); standard.theme.preset = .standard; standard.theme.sketch = false; standard.watermark = true
    var dark = standard; dark.theme.preset = .dark
    try expect(try Diagram.decode(dark.encoded()) == dark)
    let plain = try Renderer.scene(standard), scene = try Renderer.scene(dark)
    try expect(scene.layout.frames == plain.layout.frames && scene.layout.routes == plain.layout.routes)
    try expect(scene.layout.bounds == plain.layout.bounds)
    let svgData = try Renderer.svg(dark), svg = String(decoding: svgData, as: UTF8.self)
    try expect(svgData == Renderer.svg(dark))
    try expect(svg.contains("fill=\"#181818\"") && svg.contains("fill=\"#e0e0e0\""))
    try expect(svg.contains("stroke=\"#dbdbdb\"") && svg.contains("stroke=\"#adadad\""))
    try expect(!svg.contains("blueprint-paper") && !svg.contains("#ffffff"))
    for id in dark.nodes.keys { if dark.nodes[id]?.asset != nil { dark.nodes[id]?.variant = .black } }
    let blackVariants = try Renderer.svg(dark)
    for id in dark.nodes.keys { if dark.nodes[id]?.asset != nil { dark.nodes[id]?.variant = .white } }
    try expect(try Renderer.svg(dark) == blackVariants)
    let source = CGImageSourceCreateWithData(try Renderer.png(dark, scale: 1) as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
    var paper = 0, ink = 0
    for i in stride(from: 0, to: image.width * image.height * 4, by: 4) {
        if bytes[i] == 24 && bytes[i + 1] == 24 && bytes[i + 2] == 24 && bytes[i + 3] == 255 { paper += 1 }
        if bytes[i] > 200 && bytes[i + 1] > 200 && bytes[i + 2] > 200 { ink += 1 }
    }
    try expect(paper > image.width * image.height / 2 && ink > 100)
    let transparent = String(decoding: try Renderer.svg(dark, transparent: true), as: UTF8.self)
    try expect(!transparent.contains("<rect") && transparent.contains("fill=\"#e0e0e0\""))
}

func queueUsesStackedGeometry() throws {
    let item = Library.items().first { $0.id == "queue" }!
    try expect(item.shape == .queue)
    let frame = CGRect(x: 0, y: 0, width: 170, height: 76)
    let paths = SymbolGeometry.paths(.queue, in: frame)
    try expect(paths.count == 3)
    try expect(paths[0].boundingBoxOfPath.minX > paths[2].boundingBoxOfPath.minX)
    try expect(paths[0].boundingBoxOfPath.minY < paths[2].boundingBoxOfPath.minY)
    var d = Diagram(); d.nodes["queue"] = item.node(); d.containers[d.root]?.children = ["queue"]
    try expect(try Diagram.decode(d.encoded()).nodes["queue"]?.shape == .queue)
    let scene = try Renderer.scene(d)
    try expect(scene.drawings.filter { $0.stroke != nil }.count == 3)
}

func arrangementChangesReattachAndRerouteConnections() throws {
    var d = Library.sample()
    d.connectors["store"]?.waypoints = [Point(x: 999, y: 999)]
    d.connectors["outside"] = Connector(from: Endpoint("sources"), to: Endpoint("assistant"), waypoints: [Point(x: 80, y: 20)])
    let outside = d.connectors["outside"]!, before = try LayoutEngine.layout(d)
    try DiagramEditing.setLayout(.horizontal, container: "platform", document: &d)
    let after = try LayoutEngine.layout(d), a = after.frames["ingestion"]!, b = after.frames["lakehouse"]!
    try expect(d.connectors["store"]?.waypoints == nil)
    try expect(d.connectors["store"]?.from.side == .auto && d.connectors["store"]?.to.side == .auto)
    try expect(after.routes["store"]!.first == CGPoint(x: a.maxX, y: a.midY))
    try expect(after.routes["store"]!.last == CGPoint(x: b.minX, y: b.midY))
    try expect(before.routes["store"] != after.routes["store"])
    try expect(d.connectors["outside"] == outside)
}

func fileRoundTripsAndExportsWithAttachedConnector() throws {
    let item = Library.items().first { $0.id == "file" }!
    var d = Diagram(); d.nodes = ["file": item.node(), "service": Node(position: Point(x: 240, y: 40))]
    d.containers[d.root]?.children = ["file", "service"]
    d.connectors["read"] = Connector(from: Endpoint("file", side: .right), to: Endpoint("service", side: .left))
    d = try Diagram.decode(d.encoded())
    try expect(d.nodes["file"]?.shape == .file && d.nodes["file"]?.type == "file")
    let layout = try LayoutEngine.layout(d), frame = layout.frames["file"]!
    try expect(frame.width == 144 && frame.height == 192)
    let body = SymbolGeometry.paths(.file, in: frame)[0]
    try expect(body.contains(CGPoint(x: frame.midX, y: frame.midY)))
    try expect(!body.contains(CGPoint(x: frame.maxX - 2, y: frame.minY + 2)))
    try expectRightAngleAttachments(layout.routes["read"]!, source: .right, destination: .left)
    for (preset, isSketch) in themeVariants {
        d.theme.preset = preset; d.theme.sketch = isSketch
        let svg = String(decoding: try Renderer.svg(d), as: UTF8.self)
        try expect(svg.contains("<path") && !svg.contains("<text"))
        try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 1) as CFData, nil) != nil)
    }
}

func watermarkIsOptionalAndRendersInReservedFooter() throws {
    var d = Library.sample()
    var legacy = try JSONSerialization.jsonObject(with: d.encoded()) as! [String: Any]
    legacy.removeValue(forKey: "watermark")
    try expect(!Diagram.decode(JSONSerialization.data(withJSONObject: legacy)).watermark)
    legacy["watermark"] = "t1a"
    do { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: legacy)); throw CheckFailure(description: "Non-boolean watermark accepted") }
    catch DiagramError.invalid(let issues) { try expect(issues.first?.path == "$.watermark") }
    for (preset, isSketch) in themeVariants {
        d.theme.preset = preset; d.theme.sketch = isSketch; d.watermark = false
        let plain = try Renderer.scene(d)
        d.watermark = true
        try expect(try Diagram.decode(d.encoded()) == d)
        let marked = try Renderer.scene(d), bounds = marked.layout.bounds, logo = marked.drawings.last!
        try expect(marked.layout.frames == plain.layout.frames && marked.layout.routes == plain.layout.routes)
        try expect(marked.drawings.count == plain.drawings.count + 1)
        try expect(bounds.height > plain.layout.bounds.height)
        try expect(logo.path.boundingBoxOfPath.minY >= plain.layout.bounds.maxY - 0.001)
        try expect(abs(bounds.maxX - logo.path.boundingBoxOfPath.maxX - 20) < 0.01)
        try expect(abs(bounds.maxY - logo.path.boundingBoxOfPath.maxY - 20) < 0.01)
        let svg = String(decoding: try Renderer.svg(d), as: UTF8.self)
        try expect(svg.contains("opacity=\"0.400\""))
        let source = CGImageSourceCreateWithData(try Renderer.png(d, scale: 1, transparent: true) as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let footer = image.cropping(to: CGRect(x: 0, y: image.height - 44, width: image.width, height: 44))!
        let bitmap = CGContext(data: nil, width: footer.width, height: footer.height, bitsPerComponent: 8, bytesPerRow: footer.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        bitmap.draw(footer, in: CGRect(x: 0, y: 0, width: footer.width, height: footer.height))
        let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
        let alphas = stride(from: 3, to: footer.width * footer.height * 4, by: 4).map { bytes[$0] }
        try expect(alphas.filter { $0 > 0 }.count > 100 && alphas.max()! <= 103)
        d.watermark = false
        try expect(try Renderer.scene(d).layout.bounds == plain.layout.bounds)
    }
    try expect(try Renderer.scene(Diagram(watermark: true)).drawings.count == 1)
}

func groupedLibraryHasProductSymbols() throws {
    let items = Library.items()
    try expect(items.filter { $0.group == "Systems" }.count == 6)
    for group in Library.groups { try expect(items.filter { $0.group == group }.count >= 2) }
    for id in ["unity-catalog", "delta-lake", "genie-agent", "azure-data-lake", "azure-vm", "aws-s3", "aws-ec2"] { try expect(items.contains { $0.id == id && $0.asset != nil }) }
}

func usersKeepCompactMarginsAndRightAngleAttachments() throws {
    let user = Library.items().first { $0.id == "actor" }!
    try expect(user.title == "User" && user.shape == .actor && user.type == "actor" && Shape.actor.title == "User")
    for (preset, isSketch) in themeVariants {
        for fontSize in [10.0, 16, 36] {
            var d = Diagram(theme: Theme(preset: preset, sketch: isSketch, fontSize: fontSize))
            d.nodes["user"] = user.node(); d.containers[d.root]?.children = ["user"]
            let scene = try Renderer.scene(d), frame = scene.layout.frames["user"]!
            let body = SymbolGeometry.paths(.actor, in: frame)[0].boundingBoxOfPath
            let label = scene.drawings.last!.path.boundingBoxOfPath
            try expect(frame.insetBy(dx: 4, dy: 4).contains(label) && label.minY > body.maxY + 3)
            try expect(body.width > 28 && body.height > 65)
            if fontSize <= 16 {
                try expect(frame.width == 74)
                let oldMargin = (170 - body.width) / 2, newMargin = (frame.width - body.width) / 2
                try expect(newMargin / oldMargin > 0.25 && newMargin / oldMargin < 0.34)
            }
            d.nodes["target"] = Node(label: "System", position: Point(x: 250, y: 0))
            d.containers[d.root]?.children.append("target")
            for side in [Side.left, .right, .top, .bottom] {
                d.connectors["edge"] = Connector(from: Endpoint("user", side: side), to: Endpoint("target", side: .left))
                let layout = try LayoutEngine.layout(d), frame = layout.frames["user"]!, route = layout.routes["edge"]!
                try expectRightAngleAttachments(route, source: side, destination: .left)
                if side == .left { try expect(route.first == CGPoint(x: frame.minX, y: frame.midY)) }
                if side == .right { try expect(route.first == CGPoint(x: frame.maxX, y: frame.midY)) }
                try expect(layout.connectionPreview(from: "user", to: "target", at: frame.origin, document: d) != nil)
            }
            d.nodes["user"]?.label = "Existing reviewer"; d.nodes["user"]?.width = 220
            let original = d, reopened = try Diagram.decode(d.encoded())
            try expect(reopened == original && reopened.nodes["user"]?.label == "Existing reviewer")
        }
    }
}

func genieAgentLogoIsPortableInAllStyles() throws {
    let item = Library.items().first { $0.id == "genie-agent" }!
    try expect(item.group == "Databricks" && item.title == "Genie Agent" && item.type == "agent" && item.shape == .roundedRectangle)
    let asset = item.asset!
    try expect(asset.source == "https://www.databricks.com/sites/default/files/2026-05/icon-genie.svg" && asset.paths.count == 3)
    let box = CGRect(x: asset.viewBox[0], y: asset.viewBox[1], width: asset.viewBox[2], height: asset.viewBox[3])
    for path in asset.paths { try expect(box.contains(try SVGPath.parse(path).boundingBoxOfPath)) }
    for (preset, isSketch) in themeVariants {
        for variant in [LogoVariant.black, .white] {
            var d = Diagram(theme: Theme(preset: preset, sketch: isSketch))
            d.nodes[item.id] = item.node(); d.nodes[item.id]?.variant = variant; d.nodes[item.id]?.label = "Custom Genie"
            d.assets[item.id] = asset; d.containers[d.root]?.children = [item.id]
            let original = d, scene = try Renderer.scene(d), frame = scene.layout.frames[item.id]!
            let label = scene.drawings.last!.path.boundingBoxOfPath
            try expect(frame.contains(label) && label.minY > frame.minY + 48)
            try expect(try !Renderer.svg(d).isEmpty && Renderer.svg(d) == Renderer.svg(d))
            try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 0.5) as CFData, nil) != nil)
            try expect(d == original && Diagram.decode(d.encoded()) == original)
        }
    }
}

func t1aPlatformsAndAIAgentStayPortableAcrossStyles() throws {
    let library = Library.items(), brands = library.filter { $0.group == "T1A" }
    try expect(Set(brands.map(\.id)) == ["secondstack", "lakesentry", "8fde", "antares", "t1a"])
    try expect(brands.allSatisfy { $0.shape == .rectangle && $0.type == "service" && $0.asset?.source?.hasPrefix("https://") == true })
    let agent = library.first { $0.id == "ai-agent" }!
    try expect(agent.title == "AI Agent" && agent.group == "Systems" && agent.shape == .roundedRectangle && agent.type == "agent")
    let items = brands + [agent]
    var original = Diagram()
    original.containers["platforms"] = Container(label: "T1A Platforms", layout: .init(mode: .grid, gap: 60, rows: 2, columns: 3),
        children: items.map(\.id), allowedChildTypes: ["service", "agent"])
    original.containers[original.root]?.children = ["platforms"]
    for item in items {
        let asset = item.asset!
        try expect(!asset.paths.isEmpty && asset.rendering != .outline)
        let box = CGRect(x: asset.viewBox[0], y: asset.viewBox[1], width: asset.viewBox[2], height: asset.viewBox[3]).insetBy(dx: -0.01, dy: -0.01)
        for path in asset.paths { try expect(box.contains(try SVGPath.parse(path).boundingBoxOfPath)) }
        original.assets[item.id] = asset
        original.nodes[item.id] = item.node()
        original.nodes[item.id]?.label = "Custom \(item.title) label"
        try expect(original.nodes[item.id]?.asset == item.id && original.nodes[item.id]?.variant == .black)
    }
    original.connectors["agent-platform"] = Connector(from: Endpoint("ai-agent"), to: Endpoint("secondstack"), label: "Invoke")
    for (preset, isSketch) in themeVariants {
        var d = original; d.theme = Theme(preset: preset, sketch: isSketch, fontFamily: "Helvetica")
        let scene = try Renderer.scene(d), before = d
        try expect(try Diagram.decode(d.encoded()) == d)
        try expect(scene.layout.frames.keys.contains("ai-agent") && scene.layout.routes["agent-platform"] != nil)
        for item in items {
            let asset = d.assets[item.id]!, frame = scene.layout.frames[item.id]!
            let target = CGRect(x: frame.midX - 50, y: frame.minY + 14, width: 100, height: 34)
            let scale = min(target.width / asset.viewBox[2], target.height / asset.viewBox[3])
            var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                tx: target.midX - asset.viewBox[2] * scale / 2 - asset.viewBox[0] * scale,
                ty: target.midY - asset.viewBox[3] * scale / 2 - asset.viewBox[1] * scale)
            for data in asset.paths {
                let expected = try SVGPath.parse(data).copy(using: &transform)!.svgData
                try expect(scene.drawings.contains { $0.fill == 0.12 && $0.path.svgData == expected })
            }
        }
        let black = try Renderer.svg(d)
        try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 0.25) as CFData, nil) != nil)
        try expect(d == before)
        for id in d.nodes.keys { d.nodes[id]?.variant = .white }
        try expect(try Diagram.decode(d.encoded()) == d)
        let white = try Renderer.svg(d)
        if RenderPalette(preset).lightInk { try expect(black == white) }
        else { try expect(black != white && Renderer.scene(d).drawings.filter { $0.fill == 0.15 }.count == 6) }
    }
}

func documentPresetsRetainTheirFormatWhenRenamed() throws {
    let items = Library.items().filter { $0.group == Library.documentGroup }
    try expect(Set(items.map(\.id)) == ["file", "xlsx", "pdf", "docx"])
    var d = Diagram(); d.containers[d.root]?.layout = ContainerLayout(mode: .horizontal, gap: 60)
    for item in items {
        var node = item.node(); node.label = "Quarterly plan\nQ4 2026"
        d.nodes[item.id] = node; d.containers[d.root]?.children.append(item.id)
    }
    for id in ["xlsx", "pdf", "docx"] {
        d.connectors[id + "-edge"] = Connector(from: Endpoint("file", side: .right), to: Endpoint(id, side: .left))
    }
    d = try Diagram.decode(d.encoded())
    for item in items {
        try expect(d.nodes[item.id]?.type == "file" && d.nodes[item.id]?.shape.rawValue == item.id)
        try expect(d.nodes[item.id]?.label == "Quarterly plan\nQ4 2026")
    }
    let vendor = Library.items().first { $0.id == "databricks" }!
    d.assets[vendor.id] = vendor.asset; d.nodes["pdf"]?.asset = vendor.id
    for (preset, isSketch) in themeVariants {
        d.theme.preset = preset; d.theme.sketch = isSketch
        let scene = try Renderer.scene(d)
        for id in ["xlsx", "pdf", "docx"] {
            try expectRightAngleAttachments(scene.layout.routes[id + "-edge"]!, source: .right, destination: .left)
            let frame = scene.layout.frames[id]!
            let identity = SymbolGeometry.paths(d.nodes[id]!.shape, in: frame)[2].boundingBoxOfPath
            let logoSpace: CGFloat = d.nodes[id]?.asset == nil ? 0 : 43
            let label = Typography.paths(d.nodes[id]!.label, in: CGRect(x: frame.minX + 22, y: frame.minY + 108 + logoSpace, width: frame.width - 44, height: frame.height - 120 - logoSpace), font: Typography.font(d.theme)).boundingBoxOfPath
            try expect(identity.maxY < label.minY && label.maxY < frame.maxY)
        }
        let a = try Renderer.svg(d)
        try expect(try Renderer.svg(d) == a)
        try expect(!String(decoding: a, as: UTF8.self).contains("<text"))
        try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 1) as CFData, nil) != nil)
    }
}

func documentShapesKeepPortraitThreeByFourWhenResized() throws {
    let vendor = Library.items().first { $0.id == "databricks" }!
    for shape in Shape.allCases where shape.isDocument {
        for (width, height) in [(nil, nil), (320.0, nil), (nil, 300.0), (120.0, 144.0), (192.0, 144.0), (600.0, 80.0), (80.0, 600.0)] as [(Double?, Double?)] {
            var d = Diagram()
            d.nodes["document"] = Node(type: "file", label: "Plan", shape: shape, width: width, height: height)
            d.nodes["other"] = Node(label: "Unchanged", position: Point(x: 1000, y: 0), width: 330, height: 210)
            d.containers[d.root]?.children = ["document", "other"]
            d.connectors["read"] = Connector(from: Endpoint("document", side: .right), to: Endpoint("other", side: .left))
            let original = d, layout = try LayoutEngine.layout(d), frame = layout.frames["document"]!
            try expect(abs(frame.width / frame.height - 3.0 / 4.0) < 0.000001)
            try expect(frame.width >= width ?? shape.defaultWidth)
            try expect(frame.height >= height ?? shape.defaultHeight)
            try expect(layout.frames["other"]!.size == CGSize(width: 330, height: 210))
            try expect(layout.routes["read"]!.first == CGPoint(x: frame.maxX, y: frame.midY))
            try expectRightAngleAttachments(layout.routes["read"]!, source: .right, destination: .left)
            try expect(d == original && Diagram.decode(d.encoded()) == original)
        }
        var small = Diagram(theme: Theme(fontSize: 10))
        small.assets[vendor.id] = vendor.asset
        small.nodes["document"] = Node(type: "file", label: "A", shape: shape, width: 80, height: 20, asset: vendor.id, variant: .white)
        small.containers[small.root]?.children = ["document"]
        let scene = try Renderer.scene(small), frame = scene.layout.frames["document"]!
        try expect(abs(frame.width / frame.height - 3.0 / 4.0) < 0.000001)
        try expect(scene.drawings.filter { $0.stroke == nil }.allSatisfy { frame.contains($0.path.boundingBoxOfPath) })
    }
}

func documentTextGrowthKeepsRatioAcrossLayoutsAndExports() throws {
    let vendor = Library.items().first { $0.id == "databricks" }!
    for (preset, isSketch) in themeVariants {
        for mode in LayoutMode.allCases {
            var d = Diagram(theme: Theme(preset: preset, sketch: isSketch))
            d.assets[vendor.id] = vendor.asset
            d.containers["documents"] = Container(label: "Documents", layout: .init(mode: mode, rows: mode == .grid ? 2 : nil, columns: mode == .grid ? 2 : nil), width: 1300, height: 1000)
            d.containers[d.root]?.layout = .init(mode: .grid, rows: 1, columns: 1)
            d.containers[d.root]?.children = ["documents"]
            for (index, shape) in Shape.allCases.filter(\.isDocument).enumerated() {
                let id = shape.rawValue
                d.nodes[id] = Node(type: "file", label: "Quarterly operations and monitoring report\nSecond line gjpqy", shape: shape,
                    position: Point(x: Double(index % 2) * 650, y: Double(index / 2) * 450), width: 200, height: 150,
                    asset: vendor.id, fontSize: 36)
                d.containers["documents"]?.children.append(id)
            }
            let original = d, scene = try Renderer.scene(d)
            for (id, node) in d.nodes {
                let frame = scene.layout.frames[id]!
                try expect(abs(frame.width / frame.height - 3.0 / 4.0) < 0.000001)
                try expect(frame.width > 200 && frame.height > 150)
                let top: CGFloat = node.shape == .file ? 24 : 108
                let rect = CGRect(x: frame.minX + 22, y: frame.minY + top + 43, width: frame.width - 44, height: frame.height - top - 12 - 43)
                let font = Typography.font(d, for: id)
                let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + 5
                try expect(CGFloat(Typography.lines(node.label, font: font, maxWidth: rect.width).count) * lineHeight <= rect.height)
                let label = Typography.paths(node.label, in: rect, font: font)
                try expect(frame.insetBy(dx: 10, dy: 10).contains(label.boundingBoxOfPath))
                try expect(scene.drawings.contains { $0.path == label })
                let logoBottom = frame.minY + (node.shape == .file ? 14 : 102) + 34
                try expect(label.boundingBoxOfPath.minY > logoBottom)
                if node.shape != .file {
                    let details = SymbolGeometry.paths(node.shape, in: frame)
                    try expect(details.dropFirst(2).allSatisfy { $0.boundingBoxOfPath.maxY < label.boundingBoxOfPath.minY })
                }
            }
            try expect(d == original && Diagram.decode(d.encoded()) == original)
            if mode == .grid {
                let svg = try Renderer.svg(d)
                try expect(try Renderer.svg(d) == svg)
                try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 0.25) as CFData, nil) != nil)
            }
        }
    }
}

func expectRightAngleAttachments(_ points: [CGPoint], source: Side, destination: Side) throws {
    try expect(points.count >= 2)
    for (a, b) in zip(points, points.dropFirst()) {
        try expect(a != b && (a.x == b.x || a.y == b.y))
    }
    let first = CGPoint(x: points[1].x - points[0].x, y: points[1].y - points[0].y)
    let last = CGPoint(x: points[points.count - 2].x - points.last!.x, y: points[points.count - 2].y - points.last!.y)
    for (side, delta) in [(source, first), (destination, last)] {
        switch side {
        case .left: try expect(delta.y == 0 && delta.x < 0)
        case .right: try expect(delta.y == 0 && delta.x > 0)
        case .top: try expect(delta.x == 0 && delta.y < 0)
        case .bottom: try expect(delta.x == 0 && delta.y > 0)
        case .auto: throw CheckFailure(description: "Test requires an explicit side")
        }
    }
}

func connectorsRespectAllAttachmentSides() throws {
    let sides: [Side] = [.left, .right, .top, .bottom]
    let positions = [Point(x: 320, y: 140), Point(x: -320, y: 140), Point(x: 40, y: 300), Point(x: 300, y: -180), Point(x: 198, y: 0), Point(x: 0, y: 104)]
    for position in positions {
        for source in sides { for destination in sides {
            var d = Diagram(); d.nodes = ["a": Node(position: Point()), "b": Node(position: position)]
            d.containers[d.root]?.children = ["a", "b"]
            d.connectors["edge"] = Connector(from: Endpoint("a", side: source), to: Endpoint("b", side: destination))
            try expectRightAngleAttachments(try LayoutEngine.layout(d).routes["edge"]!, source: source, destination: destination)
        } }
    }
}

func manualAndLegacyStraightConnectionsStayPerpendicular() throws {
    var d = Diagram(); d.nodes = ["a": Node(position: Point()), "b": Node(position: Point(x: 380, y: 210))]
    d.containers[d.root]?.children = ["a", "b"]
    let manual = [Point(x: 310, y: 150), Point(x: 370, y: 330)]
    d.connectors["edge"] = Connector(from: Endpoint("a", side: .top), to: Endpoint("b", side: .left), routing: .straight, waypoints: manual)
    let before = d, points = try LayoutEngine.layout(d).routes["edge"]!
    try expectRightAngleAttachments(points, source: .top, destination: .left)
    for p in manual { try expect(points.contains(CGPoint(x: p.x, y: p.y))) }
    try expect(d == before)
    let scene = try Renderer.scene(d), path = scene.drawings.first { $0.stroke == 0.32 }!.path
    var kinds: [CGPathElementType] = []
    path.applyWithBlock { kinds.append($0.pointee.type) }
    try expect(kinds[1] == .addLineToPoint && kinds.last == .addLineToPoint)
    d.connectors["edge"]?.waypoints = nil
    try expectRightAngleAttachments(try LayoutEngine.layout(d).routes["edge"]!, source: .top, destination: .left)
}

func databaseConnectionsMeetCurvedOutlines() throws {
    var d = Diagram(); d.nodes = ["a": Node(shape: .cylinder, position: Point()), "b": Node(shape: .cylinder, position: Point(x: 240, y: 260))]
    d.containers[d.root]?.children = ["a", "b"]
    d.connectors["edge"] = Connector(from: Endpoint("a", side: .bottom), to: Endpoint("b", side: .top))
    let layout = try LayoutEngine.layout(d), points = layout.routes["edge"]!
    try expectRightAngleAttachments(points, source: .bottom, destination: .top)
    try expect(points.first!.y == SymbolGeometry.paths(.cylinder, in: layout.frames["a"]!)[0].boundingBoxOfPath.maxY)
    try expect(points.last!.y == SymbolGeometry.paths(.cylinder, in: layout.frames["b"]!)[0].boundingBoxOfPath.minY)
}

func databaseLabelsAndLogosStayInsideTheOutline() throws {
    let vendor = Library.items().first { $0.id == "databricks" }!
    let labels = ["Database", "Customers\nOrders\nTransactions", "Wrapped database label with descenders gjpqy", "Long_database_identifier\nDetails"]
    for (preset, isSketch) in themeVariants {
        for fontSize in [10.0, 20, 36] {
            for family in [nil, "Helvetica-Oblique"] as [String?] {
                for label in labels {
                    for variant in [nil, LogoVariant.black, .white] as [LogoVariant?] {
                        var d = Diagram(); d.theme = Theme(preset: preset, sketch: isSketch, fontFamily: family, fontSize: fontSize)
                        d.nodes["db"] = Node(label: label, shape: .cylinder, width: 80, height: 20, strokeWidth: 8)
                        d.containers[d.root]?.children = ["db"]
                        if let variant {
                            d.assets[vendor.id] = vendor.asset; d.nodes["db"]?.asset = vendor.id; d.nodes["db"]?.variant = variant
                        }
                        let before = d, scene = try Renderer.scene(d)
                        let body = scene.drawings[0], lip = scene.drawings[1]
                        let labelBounds = scene.drawings.last!.path.boundingBoxOfPath
                        try expect(labelBounds.minY > lip.path.boundingBoxOfPath.maxY + lip.width / 2 + 2)
                        let safe = labelBounds.insetBy(dx: -body.width / 2 - 2, dy: -body.width / 2 - 2)
                        for point in [CGPoint(x: safe.minX, y: safe.minY), CGPoint(x: safe.maxX, y: safe.minY),
                                      CGPoint(x: safe.minX, y: safe.maxY), CGPoint(x: safe.maxX, y: safe.maxY)] {
                            try expect(body.path.contains(point))
                        }
                        if variant != nil {
                            let marks = scene.drawings.dropFirst(2).dropLast()
                            let logoBounds = marks.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
                            try expect(logoBounds.minY > lip.path.boundingBoxOfPath.maxY + lip.width / 2 + 2)
                            try expect(logoBounds.maxY + 6 < labelBounds.minY)
                            try expect(scene.layout.frames["db"]!.insetBy(dx: 10, dy: 0).contains(logoBounds))
                        }
                        try expect(d == before)
                    }
                }
            }
        }
        // The same content placement reaches both image export formats.
        var d = Diagram(); d.theme.preset = preset; d.theme.sketch = isSketch
        d.nodes["db"] = Node(label: "Customer records\nTransactions\nAudit history", shape: .cylinder)
        d.containers[d.root]?.children = ["db"]
        let svg = try Renderer.svg(d), labelPath = try Renderer.scene(d).drawings.last!.path.svgData
        try expect(String(decoding: svg, as: UTF8.self).contains(labelPath))
        try expect(CGImageSourceCreateWithData(try Renderer.png(d, scale: 1) as CFData, nil) != nil)
    }
}

func connectionsToParentBoundariesApproachFromInside() throws {
    var d = Diagram(); d.nodes["worker"] = Node()
    d.containers[d.root]?.children = ["group"]
    d.containers["group"] = Container(label: "Group", children: ["worker"])
    d.connectors["edge"] = Connector(from: Endpoint("worker", side: .right), to: Endpoint("group", side: .right))
    let layout = try LayoutEngine.layout(d), points = layout.routes["edge"]!
    try expectRightAngleAttachments(points, source: .right, destination: .left)
    try expect(points.last!.x == layout.frames["group"]!.maxX)
}

func departureBendsBeforeTheNextSystem() throws {
    var d = Library.sample(); d.containers[d.root]?.layout.mode = .horizontal
    try DiagramEditing.setLayout(.horizontal, container: "platform", document: &d)
    let layout = try LayoutEngine.layout(d), points = layout.routes["query"]!, blocker = layout.frames["catalog"]!
    for (a, b) in zip(points, points.dropFirst()) {
        let crosses = a.y == b.y
            ? a.y > blocker.minY && a.y < blocker.maxY && min(a.x, b.x) < blocker.maxX && max(a.x, b.x) > blocker.minX
            : a.x > blocker.minX && a.x < blocker.maxX && min(a.y, b.y) < blocker.maxY && max(a.y, b.y) > blocker.minY
        try expect(!crosses)
    }
}

func lineWidthEditsAffectOnlyTheirTarget() throws {
    let original = Library.sample()
    for id in ["sources", "platform", "query"] {
        var d = original, expected = original
        try DiagramEditing.setStrokeWidth(3.4, element: id, document: &d)
        if id == "sources" { expected.nodes[id]?.strokeWidth = 3.4 }
        else if id == "platform" { expected.containers[id]?.strokeWidth = 3.4 }
        else { expected.connectors[id]?.strokeWidth = 3.4 }
        try expect(d == expected && d.theme == original.theme)
        try expect(try Diagram.decode(d.encoded()) == expected)
        try expect(d.strokeWidth(for: "ingestion") == original.theme.strokeWidth)
        d.theme.strokeWidth = 2.1
        try expect(d.strokeWidth(for: id) == 3.4 && d.strokeWidth(for: "ingestion") == 2.1)
        d.theme = original.theme
        try DiagramEditing.setStrokeWidth(nil, element: id, document: &d)
        try expect(d == original)
        for width in [-1.0, 0.49, 8.1, Double.infinity, Double.nan] {
            try expectThrows { try DiagramEditing.setStrokeWidth(width, element: id, document: &d) }
            try expect(d == original)
        }
        if id == "sources" { d.nodes[id]?.strokeWidth = 9 }
        else if id == "platform" { d.containers[id]?.strokeWidth = 9 }
        else { d.connectors[id]?.strokeWidth = 9 }
        let collection = id == "sources" ? "nodes" : id == "platform" ? "containers" : "connectors"
        try expect(Validator.validate(d).contains { $0.code == "numeric-range" && $0.path == "$.\(collection).\(id).strokeWidth" && $0.element == id })
    }
    var d = original
    for id in ["missing", d.root] {
        try expectThrows { try DiagramEditing.setStrokeWidth(3, element: id, document: &d) }
        try expect(d == original)
    }
}

func perElementLineWidthsReachImageExports() throws {
    for (preset, isSketch) in themeVariants {
        var plain = Library.sample(); plain.theme.preset = preset; plain.theme.sketch = isSketch
        var marked = plain
        try DiagramEditing.setStrokeWidth(2.8, element: "lakehouse", document: &marked)
        try DiagramEditing.setStrokeWidth(3.2, element: "platform", document: &marked)
        try DiagramEditing.setStrokeWidth(4, element: "query", document: &marked)
        let before = try Renderer.scene(plain), after = try Renderer.scene(marked)
        try expect(before.layout.frames == after.layout.frames && before.layout.routes == after.layout.routes)
        try expect(before.drawings.count == after.drawings.count)
        var changed: [Drawing] = []
        for (a, b) in zip(before.drawings, after.drawings) {
            try expect(a.path.svgData == b.path.svgData && a.stroke == b.stroke && a.fill == b.fill && a.dashed == b.dashed)
            if a.width != b.width { changed.append(b) }
        }
        try expect(changed.count == 5)
        try expect(changed.filter { $0.width == 2.8 && $0.stroke == 0.14 }.count == 2)
        try expect(changed.filter { $0.width == 3.2 && $0.stroke == 0.46 }.count == 1)
        try expect(changed.filter { $0.width == 4 && $0.stroke == 0.32 }.count == 2)
        let svg = String(decoding: try Renderer.svg(marked), as: UTF8.self)
        for width in ["2.800", "3.200", "4.000"] { try expect(svg.contains("stroke-width=\"\(width)\"")) }
        try expect(try Renderer.png(marked, scale: 1) != Renderer.png(plain, scale: 1))
    }
}

func customGridExample() -> Diagram {
    var d = Diagram()
    d.containers[d.root]?.layout = ContainerLayout(mode: .grid, gap: 40, rows: 2, columns: 3, cells: ["monitoring": GridCell(row: 2, column: 1, columnSpan: 3)])
    d.containers[d.root]?.children = ["a", "b", "platform", "monitoring"]
    d.nodes = ["a": Node(label: "Source"), "b": Node(label: "Application", width: 220), "worker": Node(label: "Worker"), "db": Node(label: "Database", shape: .cylinder), "metrics": Node(label: "Metrics"), "logs": Node(label: "Logs")]
    d.containers["platform"] = Container(label: "Platform", children: ["worker", "db"])
    d.containers["monitoring"] = Container(label: "Monitoring", layout: .init(mode: .horizontal), children: ["metrics", "logs"])
    d.connectors["observe"] = Connector(from: Endpoint("a", side: .bottom), to: Endpoint("metrics", side: .top))
    return d
}

func customGridSupportsRowsColumnsAndSpanningContainers() throws {
    let d = customGridExample(), layout = try LayoutEngine.layout(d), grid = layout.grids[d.root]!
    try expect(grid.cells["a"] == GridCell(row: 1, column: 1) && grid.cells["b"] == GridCell(row: 1, column: 2))
    try expect(grid.cells["platform"] == GridCell(row: 1, column: 3))
    let band = layout.frames["monitoring"]!, root = layout.frames[d.root]!
    try expect(band.width == grid.size.width && band.minX == root.minX + d.containers[d.root]!.layout.padding)
    try expect(band.minY > layout.frames["platform"]!.maxY)
    try expect(layout.frames["metrics"]!.midY == layout.frames["logs"]!.midY)
    try expect(layout.frames["worker"]!.midX == layout.frames["db"]!.midX)
    for (a, b) in [("a", "b"), ("b", "platform"), ("platform", "monitoring")] { try expect(!layout.frames[a]!.intersects(layout.frames[b]!)) }
    for id in ["metrics", "logs"] { try expect(band.contains(layout.frames[id]!)) }
    try expectRightAngleAttachments(layout.routes["observe"]!, source: .bottom, destination: .top)
    let cell = grid.frame(GridCell(row: 1, column: 2))
    try expect(grid.cell(at: CGPoint(x: cell.midX, y: cell.midY)) == GridCell(row: 1, column: 2))
    try expect(try Diagram.decode(d.encoded()) == d)
    for (preset, isSketch) in themeVariants {
        var themed = d; themed.theme.preset = preset; themed.theme.sketch = isSketch
        try expect(try Renderer.svg(themed) == Renderer.svg(themed))
        try expect(CGImageSourceCreateWithData(try Renderer.png(themed, scale: 1) as CFData, nil) != nil)
    }
}

func gridEditsSwapItemsAndRerouteConnections() throws {
    var d = customGridExample()
    d.connectors["observe"]?.waypoints = [Point(x: 450, y: 300)]
    let originalNodes = d.nodes
    try DiagramEditing.setGridCell(GridCell(row: 1, column: 2), element: "a", document: &d)
    let plan = try GridLayout.plan(d.containers[d.root]!, id: d.root)
    try expect(plan.cells["a"] == GridCell(row: 1, column: 2) && plan.cells["b"] == GridCell(row: 1, column: 1))
    try expect(plan.cells["platform"] == GridCell(row: 1, column: 3))
    try expect(d.nodes == originalNodes && d.connectors["observe"]?.waypoints == nil)
    try expect(d.connectors["observe"]?.from.side == .auto && d.connectors["observe"]?.to.side == .auto)
    try DiagramEditing.setGridCell(GridCell(row: 1, column: 1, columnSpan: 2), element: "a", document: &d)
    let expanded = try GridLayout.plan(d.containers[d.root]!, id: d.root)
    try expect(expanded.rows == 3 && expanded.cells["b"]!.row == 3)
    let beforeInvalid = d
    try expectThrows { try DiagramEditing.configureGrid(rows: 1, columns: 1, container: d.root, document: &d) }
    try expect(d == beforeInvalid)
    try expectThrows { try DiagramEditing.setGridCell(GridCell(row: 0), element: "a", document: &d) }
    try expect(d == beforeInvalid)
}

func gridCapacityAndAssignmentsAreValidated() throws {
    let original = customGridExample()
    var d = original
    d.containers[d.root]?.layout.cells?["a"] = GridCell(row: 2, column: 1)
    try expect(Validator.validate(d).contains { $0.code == "grid-overlap" })
    d = original; d.containers[d.root]?.layout.cells?["a"] = GridCell(row: 1, column: 3, columnSpan: 2)
    try expect(Validator.validate(d).contains { $0.code == "grid-bounds" })
    d = original; d.containers[d.root]?.layout.cells?["worker"] = GridCell()
    try expect(Validator.validate(d).contains { $0.code == "grid-child" })
    d = original; d.nodes["extra"] = Node(); d.containers[d.root]?.children.append("extra")
    try expect(Validator.validate(d).contains { $0.code == "grid-capacity" })
    try DiagramEditing.ensureGridRoom(container: d.root, document: &d)
    try expect(d.containers[d.root]?.layout.rows == 3 && Validator.validate(d).isEmpty)
    for value in [0, 33, Int.max] {
        d = original; d.containers[d.root]?.layout.rows = value
        try expect(Validator.validate(d).contains { $0.code == "numeric-range" })
        d = original; d.containers[d.root]?.layout.cells?["a"] = GridCell(row: value)
        try expect(Validator.validate(d).contains { $0.code == "grid-bounds" })
    }
    var object = try JSONSerialization.jsonObject(with: original.encoded()) as! [String: Any]
    var containers = object["containers"] as! [String: Any], root = containers[original.root] as! [String: Any], layout = root["layout"] as! [String: Any]
    layout["cells"] = ["monitoring": ["row": 2, "column": 1, "columnSpan": 3, "unknown": true]]
    root["layout"] = layout; containers[original.root] = root; object["containers"] = containers
    try expectThrows { _ = try Diagram.decode(JSONSerialization.data(withJSONObject: object)) }
}

func gridRemovalAndReparentingCleanCellAssignments() throws {
    var d = customGridExample()
    try DiagramEditing.setGridCell(GridCell(row: 1, column: 2), element: "a", document: &d)
    try DiagramEditing.reparent("a", into: "monitoring", position: nil, document: &d)
    try expect(d.containers[d.root]?.layout.cells?["a"] == nil && d.parent(of: "a") == "monitoring")
    d.remove("b")
    try expect(d.containers[d.root]?.layout.cells?["b"] == nil && Validator.validate(d).isEmpty)
    try DiagramEditing.reparent("a", into: d.root, position: nil, document: &d)
    try expect(d.parent(of: "a") == d.root && Validator.validate(d).isEmpty)
    d.remove("monitoring")
    try expect(d.containers[d.root]?.layout.cells?["monitoring"] == nil && Validator.validate(d).isEmpty)
}

func leavingGridPreservesStretchedContainerFrames() throws {
    var d = customGridExample()
    let before = try LayoutEngine.layout(d)
    try DiagramEditing.setLayout(.free, container: d.root, document: &d)
    let after = try LayoutEngine.layout(d)
    for id in before.order where id != d.root { try expect(before.frames[id] == after.frames[id]) }
    try expect(before.routes == after.routes)
    try expect(d.containers["monitoring"]?.width == Double(before.frames["monitoring"]!.width))
}

func belowDiagramCommandKeepsCustomGrid() throws {
    var d = Library.sample()
    try DiagramEditing.setLayout(.grid, container: d.root, document: &d)
    let plan = try GridLayout.plan(d.containers[d.root]!, id: d.root)
    d.containers[d.root]?.layout.cells = plan.cells
    let before = try LayoutEngine.layout(d)
    d.containers["band"] = Container(label: "Monitoring", layout: .init(mode: .horizontal))
    d.containers[d.root]?.children.append("band")
    try DiagramEditing.ensureGridRoom(container: d.root, document: &d)
    try DiagramEditing.placeContainerBelow("band", document: &d)
    try expect(d.containers[d.root]?.layout.mode == .grid)
    let after = try LayoutEngine.layout(d), newPlan = try GridLayout.plan(d.containers[d.root]!, id: d.root)
    try expect(newPlan.cells["band"] == GridCell(row: 2, column: 1, columnSpan: 3))
    try expect(after.frames["band"]!.width == after.grids[d.root]!.size.width)
    for child in plan.cells.keys { try expect(before.frames[child] == after.frames[child]) }
}

func connectionDragPreviewMatchesSavedRoutesWithoutEditing() throws {
    for (preset, isSketch) in themeVariants {
        for (source, target) in [("sources", "assistant"), ("platform", "lakehouse"), ("lakehouse", "platform")] {
            var d = Library.sample(); d.theme.preset = preset; d.theme.sketch = isSketch
            d.connectors["drag-preview"] = Connector(from: Endpoint(source), to: Endpoint(target))
            let layout = try LayoutEngine.layout(d), before = try d.encoded(), pointer = CGPoint(x: 1000, y: 550)
            let preview = layout.connectionPreview(from: source, to: target, at: pointer, document: d)
            try expect(preview == layout.routes["drag-preview"])
            let cursor = layout.connectionPreview(from: source, to: nil, at: pointer, document: d)!
            try expect(cursor.last == pointer && cursor.count >= 2)
            for (a, b) in zip(cursor, cursor.dropFirst()) { try expect(a.x == b.x || a.y == b.y) }
            for invalid in [d.root, "missing", "drag-preview"] {
                try expect(layout.connectionPreview(from: invalid, to: target, at: pointer, document: d) == nil)
                try expect(layout.connectionPreview(from: source, to: invalid, at: pointer, document: d) == nil)
            }
            try expect(layout.connectionPreview(from: source, to: source, at: pointer, document: d) == nil)
            try expect(layout.connectionPreview(from: source, to: nil, at: CGPoint(x: CGFloat.nan, y: 0), document: d) == nil)
            try expect(try d.encoded() == before)
        }
    }
}

struct CheckFailure: Error, CustomStringConvertible { var description: String }
func expect(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    guard try condition() else { throw CheckFailure(description: "Failed expectation at \(file):\(line)") }
}
func expectThrows(_ body: () throws -> Void, line: UInt = #line) throws {
    do { try body() } catch { return }
    throw CheckFailure(description: "Expected an error at line \(line)")
}

let checks: [(String, () throws -> Void)] = [
    ("timelineDependenciesApproachTheStartFromOutsideTheBar", timelineDependenciesApproachTheStartFromOutsideTheBar),
    ("oversizedModeFilesCannotOverwriteReadableDocuments", oversizedModeFilesCannotOverwriteReadableDocuments),
    ("documentModesPreserveLegacyAndStrictRoundTrips", documentModesPreserveLegacyAndStrictRoundTrips),
    ("freehandSmoothingPreservesEndpointsAndRemovesJitter", freehandSmoothingPreservesEndpointsAndRemovesJitter),
    ("freeDrawingBoundsTextAndValidationStayPortable", freeDrawingBoundsTextAndValidationStayPortable),
    ("timelineCalendarMathHandlesLeapYearsAndDST", timelineCalendarMathHandlesLeapYearsAndDST),
    ("timelineValidationRejectsCyclesAndInvalidSchedules", timelineValidationRejectsCyclesAndInvalidSchedules),
    ("timelineGeometryEditingAndExportsAgreeAcrossStyles", timelineGeometryEditingAndExportsAgreeAcrossStyles),
    ("toolboxShortcutsCoverEveryPresetWithoutConflicts", toolboxShortcutsCoverEveryPresetWithoutConflicts),
    ("clipboardDuplicatesNestedContainersAndInternalConnections", clipboardDuplicatesNestedContainersAndInternalConnections),
    ("clipboardPreservesAssetsAcrossFilesAndRejectsInvalidTargets", clipboardPreservesAssetsAcrossFilesAndRejectsInvalidTargets),
    ("clipboardConnectionsRetainEndpointsAndManualRoutes", clipboardConnectionsRetainEndpointsAndManualRoutes),
    ("t1aPlatformsAndAIAgentStayPortableAcrossStyles", t1aPlatformsAndAIAgentStayPortableAcrossStyles),
    ("brandThemesKeepReadableSemanticColorsInPNGAndSVG", brandThemesKeepReadableSemanticColorsInPNGAndSVG),
    ("eightFDEUsesBrandShapeLinesAndWhiteContainers", eightFDEUsesBrandShapeLinesAndWhiteContainers),
    ("brandThemesPreserveWhiteLogoContrastAndSchemaChoices", brandThemesPreserveWhiteLogoContrastAndSchemaChoices),
    ("fontSizeEditsAffectOnlyTheirTargetAndResetToDefaults", fontSizeEditsAffectOnlyTheirTargetAndResetToDefaults),
    ("perElementFontSizesReachExportsWithoutChangingOtherLabels", perElementFontSizesReachExportsWithoutChangingOtherLabels),
    ("individualLargeLabelsFitShapesContainersAndConnectors", individualLargeLabelsFitShapesContainersAndConnectors),
    ("legacyThemesPreserveAppearanceAndSaveSeparateSettings", legacyThemesPreserveAppearanceAndSaveSeparateSettings),
    ("sketchSettingHasStrictBooleanValidation", sketchSettingHasStrictBooleanValidation),
    ("allColorThemesSupportIndependentSketchAndCleanExports", allColorThemesSupportIndependentSketchAndCleanExports),
    ("connectionDragPreviewMatchesSavedRoutesWithoutEditing", connectionDragPreviewMatchesSavedRoutesWithoutEditing),
    ("customGridSupportsRowsColumnsAndSpanningContainers", customGridSupportsRowsColumnsAndSpanningContainers),
    ("gridEditsSwapItemsAndRerouteConnections", gridEditsSwapItemsAndRerouteConnections),
    ("gridCapacityAndAssignmentsAreValidated", gridCapacityAndAssignmentsAreValidated),
    ("gridRemovalAndReparentingCleanCellAssignments", gridRemovalAndReparentingCleanCellAssignments),
    ("leavingGridPreservesStretchedContainerFrames", leavingGridPreservesStretchedContainerFrames),
    ("belowDiagramCommandKeepsCustomGrid", belowDiagramCommandKeepsCustomGrid),
    ("canonicalRoundTrip", canonicalRoundTrip),
    ("missingEndpointReportsFieldAndID", missingEndpointReportsFieldAndID),
    ("cyclesAndMultipleOwnershipAreRejected", cyclesAndMultipleOwnershipAreRejected),
    ("nestingLimitDoesNotDependOnIDOrder", nestingLimitDoesNotDependOnIDOrder),
    ("invalidReparentLeavesOriginalIntact", invalidReparentLeavesOriginalIntact),
    ("externalConnectionsPreserveVerticalStack", externalConnectionsPreserveVerticalStack),
    ("freeLayoutMaterializesStackPositions", freeLayoutMaterializesStackPositions),
    ("rootPlacementPreservesStacksAndConnections", rootPlacementPreservesStacksAndConnections),
    ("borderlessPlacementKeepsOtherItemsFixedAcrossTheOrigin", borderlessPlacementKeepsOtherItemsFixedAcrossTheOrigin),
    ("placementCoordinatesRespectContainerHeadersAndCanvasFreedom", placementCoordinatesRespectContainerHeadersAndCanvasFreedom),
    ("wideContainersCanSpanBelowTheDiagram", wideContainersCanSpanBelowTheDiagram),
    ("belowPlacementHandlesNegativeAndInvalidTargets", belowPlacementHandlesNegativeAndInvalidTargets),
    ("containerMinimumSizesRoundTripAndExpand", containerMinimumSizesRoundTripAndExpand),
    ("sketchSVGIsDeterministicAndSelfContained", sketchSVGIsDeterministicAndSelfContained),
    ("sketchStrokesAreVisibleWithTheSameCustomFont", sketchStrokesAreVisibleWithTheSameCustomFont),
    ("sketchConnectorsKeepRightAnglesAndShapeAttachments", sketchConnectorsKeepRightAnglesAndShapeAttachments),
    ("sketchStrokesStaySubtleAndConnectorsAreSeeded", sketchStrokesStaySubtleAndConnectorsAreSeeded),
    ("pngExportsRealPixelsAndTransparency", pngExportsRealPixelsAndTransparency),
    ("unknownFieldsCannotBeSilentlyLost", unknownFieldsCannotBeSilentlyLost),
    ("guardedWritesRejectStaleRevisions", guardedWritesRejectStaleRevisions),
    ("svgPathSupportsArcsAndRejectsInvalidGeometry", svgPathSupportsArcsAndRejectsInvalidGeometry),
    ("deletingContainerRemovesDescendantsAndAttachedEdges", deletingContainerRemovesDescendantsAndAttachedEdges),
    ("bundledLibraryAssetsValidate", bundledLibraryAssetsValidate),
    ("denseNestedDiagramRenders", denseNestedDiagramRenders),
    ("connectorLabelsDoNotEraseNodeBorders", connectorLabelsDoNotEraseNodeBorders),
    ("connectorLabelsStayNearTheRoute", connectorLabelsStayNearTheRoute),
    ("logoVariantsRoundTripAndRender", logoVariantsRoundTripAndRender),
    ("malformedValuesReportPrecisePaths", malformedValuesReportPrecisePaths),
    ("blueprintExportsBluePaperAndWhiteInk", blueprintExportsBluePaperAndWhiteInk),
    ("darkExportsKeepInkReadableAndGeometryIntact", darkExportsKeepInkReadableAndGeometryIntact),
    ("queueUsesStackedGeometry", queueUsesStackedGeometry),
    ("fileRoundTripsAndExportsWithAttachedConnector", fileRoundTripsAndExportsWithAttachedConnector),
    ("watermarkIsOptionalAndRendersInReservedFooter", watermarkIsOptionalAndRendersInReservedFooter),
    ("arrangementChangesReattachAndRerouteConnections", arrangementChangesReattachAndRerouteConnections),
    ("groupedLibraryHasProductSymbols", groupedLibraryHasProductSymbols),
    ("usersKeepCompactMarginsAndRightAngleAttachments", usersKeepCompactMarginsAndRightAngleAttachments),
    ("genieAgentLogoIsPortableInAllStyles", genieAgentLogoIsPortableInAllStyles),
    ("documentPresetsRetainTheirFormatWhenRenamed", documentPresetsRetainTheirFormatWhenRenamed),
    ("documentShapesKeepPortraitThreeByFourWhenResized", documentShapesKeepPortraitThreeByFourWhenResized),
    ("documentTextGrowthKeepsRatioAcrossLayoutsAndExports", documentTextGrowthKeepsRatioAcrossLayoutsAndExports),
    ("connectorsRespectAllAttachmentSides", connectorsRespectAllAttachmentSides),
    ("manualAndLegacyStraightConnectionsStayPerpendicular", manualAndLegacyStraightConnectionsStayPerpendicular),
    ("databaseConnectionsMeetCurvedOutlines", databaseConnectionsMeetCurvedOutlines),
    ("databaseLabelsAndLogosStayInsideTheOutline", databaseLabelsAndLogosStayInsideTheOutline),
    ("connectionsToParentBoundariesApproachFromInside", connectionsToParentBoundariesApproachFromInside),
    ("departureBendsBeforeTheNextSystem", departureBendsBeforeTheNextSystem),
    ("lineWidthEditsAffectOnlyTheirTarget", lineWidthEditsAffectOnlyTheirTarget),
    ("perElementLineWidthsReachImageExports", perElementLineWidthsReachImageExports),
]
var failures = 0
for (name, check) in checks {
    do { try check(); print("PASS  \(name)") }
    catch { failures += 1; print("FAIL  \(name): \(error)") }
}
print("\(checks.count - failures)/\(checks.count) checks passed")
if failures > 0 { exit(1) }
