import Foundation

public enum LayoutMode: String, Codable, CaseIterable { case horizontal, vertical, free, grid }
public enum Shape: String, Codable, CaseIterable {
    case rectangle, roundedRectangle, cylinder, queue, file, xlsx, pdf, docx, actor, text
    public var isDocument: Bool {
        switch self { case .file, .xlsx, .pdf, .docx: return true; default: return false }
    }
    public var fixedAspectRatio: Double? { isDocument ? 3.0 / 4.0 : nil }
    public var defaultWidth: Double { isDocument ? 144 : self == .actor ? 74 : 170 }
    public var defaultHeight: Double { isDocument ? 192 : self == .actor ? 100 : 76 }
    public var title: String {
        switch self {
        case .rectangle: return "Box"
        case .roundedRectangle: return "Rounded box"
        case .cylinder: return "Database"
        case .queue: return "Queue"
        case .file: return "File"
        case .xlsx: return "XLSX"
        case .pdf: return "PDF"
        case .docx: return "DOCX"
        case .actor: return "User"
        case .text: return "Text"
        }
    }
}
public enum ThemePreset: String, Codable, CaseIterable {
    case standard, blueprint, dark, secondStack = "secondstack", eightFDE = "8fde"
    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .blueprint: return "Blueprint"
        case .dark: return "Dark"
        case .secondStack: return "SecondStack"
        case .eightFDE: return "8FDE"
        }
    }
}
public enum AssetRendering: String, Codable { case solid, outline }
public enum Side: String, Codable, CaseIterable { case auto, left, right, top, bottom }
public enum Direction: String, Codable, CaseIterable { case none, forward, both }
public enum Routing: String, Codable, CaseIterable { case straight, orthogonal }
public enum LogoVariant: String, Codable, CaseIterable { case black, white }

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
}

public struct Theme: Codable, Equatable {
    public var preset: ThemePreset
    public var sketch: Bool
    public var version: Int
    public var seed: UInt64
    public var strokeWidth: Double
    public var fontFamily: String?
    public var fontSize: Double
    public init(preset: ThemePreset = .standard, sketch: Bool = true, version: Int = 1, seed: UInt64 = 42,
                strokeWidth: Double = 1.6, fontFamily: String? = nil, fontSize: Double = 16) {
        self.preset = preset; self.sketch = sketch; self.version = version; self.seed = seed
        self.strokeWidth = strokeWidth; self.fontFamily = fontFamily; self.fontSize = fontSize
    }
    enum CodingKeys: String, CodingKey { case preset, sketch, version, seed, strokeWidth, fontFamily, fontSize }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Older files encoded sketch as a fourth preset. Preserve their appearance,
        // including the original sketch default when the preset was omitted.
        let savedPreset = try c.decodeIfPresent(String.self, forKey: .preset) ?? "signature-sketch"
        if savedPreset == "signature-sketch" { preset = .standard }
        else if let color = ThemePreset(rawValue: savedPreset) { preset = color }
        else { throw DecodingError.dataCorruptedError(forKey: .preset, in: c, debugDescription: "Unknown color theme '\(savedPreset)'.") }
        sketch = try c.decodeIfPresent(Bool.self, forKey: .sketch) ?? (savedPreset == "signature-sketch")
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 42
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 1.6
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 16
    }
}

public struct Node: Codable, Equatable {
    public var type: String
    public var label: String
    public var shape: Shape
    public var position: Point?
    public var width: Double?
    public var height: Double?
    public var asset: String?
    public var variant: LogoVariant?
    public var strokeWidth: Double?
    public var fontSize: Double?
    public init(type: String = "service", label: String = "Service", shape: Shape = .rectangle,
                position: Point? = nil, width: Double? = nil, height: Double? = nil,
                asset: String? = nil, variant: LogoVariant? = nil, strokeWidth: Double? = nil, fontSize: Double? = nil) {
        self.type = type; self.label = label; self.shape = shape; self.position = position
        self.width = width; self.height = height; self.asset = asset; self.variant = variant
        self.strokeWidth = strokeWidth; self.fontSize = fontSize
    }
    enum CodingKeys: String, CodingKey { case type, label, shape, position, width, height, asset, variant, strokeWidth, fontSize }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        label = try c.decode(String.self, forKey: .label)
        shape = try c.decodeIfPresent(Shape.self, forKey: .shape) ?? .rectangle
        position = try c.decodeIfPresent(Point.self, forKey: .position)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        asset = try c.decodeIfPresent(String.self, forKey: .asset)
        variant = try c.decodeIfPresent(LogoVariant.self, forKey: .variant)
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
    }
}

public struct GridCell: Codable, Equatable {
    public var row: Int
    public var column: Int
    public var rowSpan: Int
    public var columnSpan: Int
    public init(row: Int = 1, column: Int = 1, rowSpan: Int = 1, columnSpan: Int = 1) {
        self.row = row; self.column = column; self.rowSpan = rowSpan; self.columnSpan = columnSpan
    }
    enum CodingKeys: String, CodingKey { case row, column, rowSpan, columnSpan }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        row = try c.decode(Int.self, forKey: .row); column = try c.decode(Int.self, forKey: .column)
        rowSpan = try c.decodeIfPresent(Int.self, forKey: .rowSpan) ?? 1
        columnSpan = try c.decodeIfPresent(Int.self, forKey: .columnSpan) ?? 1
    }
}

public struct ContainerLayout: Codable, Equatable {
    public var mode: LayoutMode
    public var gap: Double
    public var padding: Double
    public var rows: Int?
    public var columns: Int?
    public var cells: [String: GridCell]?
    public init(mode: LayoutMode = .vertical, gap: Double = 28, padding: Double = 28,
                rows: Int? = nil, columns: Int? = nil, cells: [String: GridCell]? = nil) {
        self.mode = mode; self.gap = gap; self.padding = padding
        self.rows = rows; self.columns = columns; self.cells = cells
    }
    enum CodingKeys: String, CodingKey { case mode, gap, padding, rows, columns, cells }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(LayoutMode.self, forKey: .mode)
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? 28
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? 28
        rows = try c.decodeIfPresent(Int.self, forKey: .rows)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns)
        cells = try c.decodeIfPresent([String: GridCell].self, forKey: .cells)
    }
}

public struct Container: Codable, Equatable {
    public var label: String?
    public var layout: ContainerLayout
    public var children: [String]
    public var allowedChildTypes: [String]?
    public var position: Point?
    public var width: Double?
    public var height: Double?
    public var strokeWidth: Double?
    public var fontSize: Double?
    public init(label: String? = nil, layout: ContainerLayout = .init(), children: [String] = [],
                allowedChildTypes: [String]? = nil, position: Point? = nil, width: Double? = nil,
                height: Double? = nil, strokeWidth: Double? = nil, fontSize: Double? = nil) {
        self.label = label; self.layout = layout; self.children = children
        self.allowedChildTypes = allowedChildTypes; self.position = position
        self.width = width; self.height = height
        self.strokeWidth = strokeWidth; self.fontSize = fontSize
    }
}

public struct Endpoint: Codable, Equatable {
    public var element: String
    public var side: Side
    public init(_ element: String, side: Side = .auto) { self.element = element; self.side = side }
    enum CodingKeys: String, CodingKey { case element, side }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        element = try c.decode(String.self, forKey: .element)
        side = try c.decodeIfPresent(Side.self, forKey: .side) ?? .auto
    }
}

public struct Connector: Codable, Equatable {
    public var from: Endpoint
    public var to: Endpoint
    public var label: String?
    public var direction: Direction
    public var routing: Routing
    public var dashed: Bool
    public var waypoints: [Point]?
    public var strokeWidth: Double?
    public var fontSize: Double?
    public init(from: Endpoint, to: Endpoint, label: String? = nil, direction: Direction = .forward,
                routing: Routing = .orthogonal, dashed: Bool = false, waypoints: [Point]? = nil, strokeWidth: Double? = nil, fontSize: Double? = nil) {
        self.from = from; self.to = to; self.label = label; self.direction = direction
        self.routing = routing; self.dashed = dashed; self.waypoints = waypoints
        self.strokeWidth = strokeWidth; self.fontSize = fontSize
    }
    enum CodingKeys: String, CodingKey { case from, to, label, direction, routing, dashed, waypoints, strokeWidth, fontSize }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(Endpoint.self, forKey: .from); to = try c.decode(Endpoint.self, forKey: .to)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        direction = try c.decodeIfPresent(Direction.self, forKey: .direction) ?? .forward
        routing = try c.decodeIfPresent(Routing.self, forKey: .routing) ?? .orthogonal
        dashed = try c.decodeIfPresent(Bool.self, forKey: .dashed) ?? false
        waypoints = try c.decodeIfPresent([Point].self, forKey: .waypoints)
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth)
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
    }
}

/// Frozen vector geometry. Paths use the supported SVG subset, never executable SVG markup.
public struct Asset: Codable, Equatable {
    public var name: String
    public var source: String?
    public var viewBox: [Double]
    public var paths: [String]
    public var rendering: AssetRendering?
    public init(name: String, source: String? = nil, viewBox: [Double], paths: [String], rendering: AssetRendering? = nil) {
        self.name = name; self.source = source; self.viewBox = viewBox; self.paths = paths; self.rendering = rendering
    }
}

public struct Diagram: Codable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var title: String
    public var theme: Theme
    public var watermark: Bool
    public var root: String
    public var nodes: [String: Node]
    public var containers: [String: Container]
    public var connectors: [String: Connector]
    public var assets: [String: Asset]
    public var mode: DocumentMode
    public var drawing: FreeDrawing?
    public var timeline: Timeline?
    public init(id: String = UUID().uuidString.lowercased(), title: String = "Untitled diagram",
                theme: Theme = .init(), watermark: Bool = false, root: String = "canvas", nodes: [String: Node] = [:],
                containers: [String: Container]? = nil, connectors: [String: Connector] = [:], assets: [String: Asset] = [:],
                mode: DocumentMode = .diagram, drawing: FreeDrawing? = nil, timeline: Timeline? = nil) {
        schemaVersion = 1; self.id = id; self.title = title; self.theme = theme; self.watermark = watermark; self.root = root
        self.nodes = nodes; self.containers = containers ?? [root: Container(layout: .init(mode: .free))]
        self.connectors = connectors; self.assets = assets
        self.mode = mode
        self.drawing = drawing ?? (mode == .drawing ? FreeDrawing() : nil)
        self.timeline = timeline ?? (mode == .timeline ? Timeline() : nil)
    }
    enum CodingKeys: String, CodingKey { case schemaVersion, id, title, theme, watermark, root, nodes, containers, connectors, assets, mode, drawing, timeline }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(String.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .init()
        watermark = try c.decodeIfPresent(Bool.self, forKey: .watermark) ?? false
        root = try c.decode(String.self, forKey: .root)
        nodes = try c.decode([String: Node].self, forKey: .nodes)
        containers = try c.decode([String: Container].self, forKey: .containers)
        connectors = try c.decodeIfPresent([String: Connector].self, forKey: .connectors) ?? [:]
        assets = try c.decodeIfPresent([String: Asset].self, forKey: .assets) ?? [:]
        mode = try c.decodeIfPresent(DocumentMode.self, forKey: .mode) ?? .diagram
        drawing = try c.decodeIfPresent(FreeDrawing.self, forKey: .drawing)
        timeline = try c.decodeIfPresent(Timeline.self, forKey: .timeline)
    }
    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try e.encode(self); data.append(10); return data
    }
    public static func decode(_ data: Data) throws -> Diagram {
        try StrictDocument.check(data)
        let diagram: Diagram
        do { diagram = try JSONDecoder().decode(Diagram.self, from: data) }
        catch let error as DecodingError {
            let context: DecodingError.Context
            var missing: CodingKey?
            switch error {
            case .keyNotFound(let key, let c): context = c; missing = key
            case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c): context = c
            @unknown default: throw error
            }
            var keys = context.codingPath; if let missing { keys.append(missing) }
            let path = keys.reduce("$") { $0 + ($1.intValue.map { "[\($0)]" } ?? ".\($1.stringValue)") }
            throw DiagramError.invalid([.init("invalid-value", path, context.debugDescription)])
        }
        let issues = Validator.validate(diagram)
        if !issues.isEmpty { throw DiagramError.invalid(issues) }
        return diagram
    }
    public func parent(of id: String) -> String? {
        containers.keys.sorted().first { containers[$0]!.children.contains(id) }
    }
    public func label(of id: String) -> String { nodes[id]?.label ?? containers[id]?.label ?? connectors[id]?.label ?? timeline?.tasks.first { $0.id == id }?.label ?? (drawing?.strokes.contains { $0.id == id } == true ? "Pen stroke" : id) }
    public func strokeWidthOverride(for id: String) -> Double? { nodes[id]?.strokeWidth ?? containers[id]?.strokeWidth ?? connectors[id]?.strokeWidth }
    public func strokeWidth(for id: String) -> Double { strokeWidthOverride(for: id) ?? theme.strokeWidth }
    public func fontSizeOverride(for id: String) -> Double? { nodes[id]?.fontSize ?? containers[id]?.fontSize ?? connectors[id]?.fontSize }
    public func fontSize(for id: String) -> Double {
        if let size = fontSizeOverride(for: id) { return size }
        // Preserve the established hierarchy in files without individual sizes.
        if connectors[id] != nil { return 12 }
        if containers[id] != nil && id != root { return 14 }
        return theme.fontSize
    }
    public func descendants(of id: String) -> Set<String> {
        var found: Set<String> = [id]
        func visit(_ id: String) { for child in containers[id]?.children ?? [] where found.insert(child).inserted { visit(child) } }
        visit(id); return found
    }
    public mutating func remove(_ id: String) {
        guard id != root else { return }
        drawing?.strokes.removeAll { $0.id == id }
        timeline?.tasks.removeAll { $0.id == id }
        if timeline != nil {
            for index in timeline!.tasks.indices { timeline!.tasks[index].dependencies.removeAll { $0 == id } }
        }
        if connectors.removeValue(forKey: id) != nil { return }
        let removed = descendants(of: id)
        for key in removed { nodes.removeValue(forKey: key); containers.removeValue(forKey: key) }
        for key in containers.keys {
            containers[key]?.children.removeAll { removed.contains($0) }
            for child in removed { containers[key]?.layout.cells?.removeValue(forKey: child) }
        }
        connectors = connectors.filter { !removed.contains($0.value.from.element) && !removed.contains($0.value.to.element) }
    }
}

public struct Diagnostic: Codable, Equatable {
    public var code: String
    public var element: String?
    public var path: String
    public var message: String
    public init(_ code: String, _ path: String, _ message: String, element: String? = nil) {
        self.code = code; self.path = path; self.message = message; self.element = element
    }
}
public enum DiagramError: Error, LocalizedError {
    case invalid([Diagnostic]), message(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let issues): return issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
        case .message(let text): return text
        }
    }
}
