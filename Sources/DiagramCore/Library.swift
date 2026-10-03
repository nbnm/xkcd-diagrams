import Foundation

public struct LibraryItem: Codable, Identifiable {
    public var id: String
    public var title: String
    public var group: String
    public var type: String
    public var shape: Shape
    public var symbol: String
    public var asset: Asset?
    public func node(at position: Point? = nil) -> Node { Node(type: type, label: title, shape: shape, position: position, asset: asset == nil ? nil : id, variant: asset == nil ? nil : .black) }
}

public enum Library {
    public static let documentGroup = "Documents"
    public static let groups = ["T1A", "Databricks", "Azure", "AWS", "OpenAI", "Anthropic"]
    public static func items() -> [LibraryItem] {
        guard let url = Bundle.module.url(forResource: "library", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([LibraryItem].self, from: data) else { return [] }
        return items
    }
    public static func schema() throws -> Data {
        guard let url = Bundle.module.url(forResource: "diagram.schema", withExtension: "json", subdirectory: "Resources") else { throw DiagramError.message("Schema resource is missing.") }
        return try Data(contentsOf: url)
    }
    public static func sample() -> Diagram {
        var d = Diagram(id: "t1a-data-platform", title: "T1A Data Platform")
        d.nodes = [
            "sources": Node(type: "application", label: "Enterprise Systems", position: Point(x: 30, y: 165)),
            "ingestion": Node(type: "service", label: "Ingestion"),
            "lakehouse": Node(type: "database", label: "Lakehouse", shape: .cylinder),
            "catalog": Node(type: "service", label: "Unity Catalog"),
            "assistant": Node(type: "application", label: "AI Application", position: Point(x: 680, y: 165))
        ]
        d.containers[d.root]?.children = ["sources", "platform", "assistant"]
        d.containers["platform"] = Container(label: "Databricks Platform", children: ["ingestion", "lakehouse", "catalog"],
            allowedChildTypes: ["service", "database"], position: Point(x: 345, y: 40))
        d.connectors = [
            "ingest": Connector(from: Endpoint("sources", side: .right), to: Endpoint("ingestion", side: .left), label: "Batch / CDC"),
            "store": Connector(from: Endpoint("ingestion", side: .bottom), to: Endpoint("lakehouse", side: .top), label: "Delta"),
            "govern": Connector(from: Endpoint("catalog", side: .top), to: Endpoint("lakehouse", side: .bottom), label: "Governance", dashed: true),
            "query": Connector(from: Endpoint("lakehouse", side: .right), to: Endpoint("assistant", side: .left), label: "SQL / API")
        ]
        if let item = items().first(where: { $0.id == "databricks" }), let asset = item.asset {
            d.assets[item.id] = asset; d.nodes["lakehouse"]?.asset = item.id
        }
        if let layout = try? LayoutEngine.layout(d), let database = layout.frames["lakehouse"], let application = layout.frames["assistant"] {
            d.nodes["assistant"]?.position?.y = Double(database.midY - application.height / 2) - d.containers[d.root]!.layout.padding
        }
        return d
    }
}
