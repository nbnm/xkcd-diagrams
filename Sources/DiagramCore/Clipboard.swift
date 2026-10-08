import Foundation
import CoreGraphics

/// A portable subtree with frozen marks; standalone connections retain existing endpoints.
public struct DiagramClipboard: Codable {
    public let format: String
    public let version: Int
    public let sourceDocumentID: String
    public let sourceParent: String?
    public let selection: String
    public let origin: Point
    public let content: Diagram
    public let connection: Connector?

    public static func capture(_ id: String, from document: Diagram) throws -> DiagramClipboard {
        guard id != document.root, document.nodes[id] != nil || document.containers[id] != nil || document.connectors[id] != nil else {
            throw DiagramError.message("Select an item to copy.")
        }
        let layout = try LayoutEngine.layout(document)
        let frame = layout.frames[id] ?? .zero
        var content = Diagram(theme: document.theme, root: "clipboard-" + UUID().uuidString.lowercased())
        content.containers[content.root]?.layout.padding = 0
        if document.connectors[id] == nil {
            let descendants = document.descendants(of: id)
            content.nodes = document.nodes.filter { descendants.contains($0.key) }
            content.containers.merge(document.containers.filter { descendants.contains($0.key) }) { _, new in new }
            content.containers[content.root]?.children = [id]
            if content.nodes[id] != nil { content.nodes[id]?.position = Point() }
            else { content.containers[id]?.position = Point() }
            content.connectors = document.connectors.filter { descendants.contains($0.value.from.element) && descendants.contains($0.value.to.element) }
            for key in content.connectors.keys {
                let points = content.connectors[key]?.waypoints
                content.connectors[key]?.waypoints = points?.map { Point(x: $0.x - frame.minX, y: $0.y - frame.minY) }
            }
            for asset in Set(content.nodes.values.compactMap(\.asset)) { content.assets[asset] = document.assets[asset] }
        }
        return .init(format: "com.t1a.diagrams.clipboard", version: 1, sourceDocumentID: document.id,
                     sourceParent: document.parent(of: id), selection: id, origin: Point(x: frame.minX, y: frame.minY),
                     content: content, connection: document.connectors[id])
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> DiagramClipboard {
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    private func validate() throws {
        guard format == "com.t1a.diagrams.clipboard", version == 1, origin.x.isFinite, origin.y.isFinite else {
            throw DiagramError.message("Unsupported diagram clipboard data.")
        }
        _ = try Diagram.decode(content.encoded())
        let roots = content.containers[content.root]?.children ?? []
        guard connection == nil ? roots == [selection] : roots.isEmpty else {
            throw DiagramError.message("Clipboard data must contain one selected item.")
        }
    }

    /// All identifiers, asset references, grid cells, and internal endpoints are remapped together.
    /// Commit only after validation, so a restricted or full destination cannot lose existing work.
    @discardableResult public func paste(into parent: String, at position: Point, document: inout Diagram) throws -> String {
        try validate()
        var next = document
        var used = Set(next.nodes.keys).union(next.containers.keys).union(next.connectors.keys)
        func fresh(_ prefix: String) -> String {
            var id: String
            repeat { id = prefix + "-" + UUID().uuidString.prefix(8).lowercased() } while used.contains(id)
            used.insert(id); return id
        }
        if let connection {
            guard sourceDocumentID == next.id,
                  [connection.from.element, connection.to.element].allSatisfy({ $0 != next.root && (next.nodes[$0] != nil || next.containers[$0] != nil) }) else {
                throw DiagramError.message("Paste this connector into its original diagram, where both endpoints still exist.")
            }
            let id = fresh("connection")
            next.connectors[id] = connection
            let issues = Validator.validate(next)
            guard issues.isEmpty else { throw DiagramError.invalid(issues) }
            document = next; return id
        }
        guard let target = next.containers[parent] else { throw DiagramError.message("Choose a container to paste into.") }
        let ids = Set(content.nodes.keys).union(content.containers.keys.filter { $0 != content.root }).union(content.connectors.keys)
        let mapping = Dictionary(uniqueKeysWithValues: ids.sorted().map { ($0, fresh($0)) })
        var assetMapping: [String: String] = [:]
        for (key, asset) in content.assets {
            var newKey = key
            if let current = next.assets[key], current != asset {
                repeat { newKey = key + "-" + UUID().uuidString.prefix(8).lowercased() } while next.assets[newKey] != nil
            }
            next.assets[newKey] = asset; assetMapping[key] = newKey
        }
        for (id, var node) in content.nodes {
            if let asset = node.asset { node.asset = assetMapping[asset] }
            next.nodes[mapping[id]!] = node
        }
        for (id, var container) in content.containers where id != content.root {
            container.children = container.children.map { mapping[$0]! }
            if let cells = container.layout.cells {
                container.layout.cells = Dictionary(uniqueKeysWithValues: cells.map { (mapping[$0.key]!, $0.value) })
            }
            next.containers[mapping[id]!] = container
        }
        let pasted = mapping[selection]!
        if next.nodes[pasted] != nil { next.nodes[pasted]?.position = target.layout.mode == .free ? position : nil }
        else { next.containers[pasted]?.position = target.layout.mode == .free ? position : nil }
        next.containers[parent]?.children.append(pasted)
        try DiagramEditing.ensureGridRoom(container: parent, document: &next)
        let frame = try LayoutEngine.layout(next).frames[pasted]!
        for (id, var edge) in content.connectors {
            edge.from.element = mapping[edge.from.element]!; edge.to.element = mapping[edge.to.element]!
            edge.waypoints = edge.waypoints?.map { Point(x: $0.x + frame.minX, y: $0.y + frame.minY) }
            next.connectors[mapping[id]!] = edge
        }
        let issues = Validator.validate(next)
        guard issues.isEmpty else { throw DiagramError.invalid(issues) }
        document = next; return pasted
    }
}
