import Foundation

/// Rejects unknown fields before Codable can silently discard them.
enum StrictDocument {
    static func check(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiagramError.message("The diagram must be a JSON object.")
        }
        var diagnostics: [Diagnostic] = []
        func rejectNulls(_ value: Any, path: String) {
            if value is NSNull { diagnostics.append(.init("null-value", path, "Use a value of the documented type, or omit an optional field.")) }
            else if let object = value as? [String: Any] { for key in object.keys.sorted() { rejectNulls(object[key]!, path: path + "." + key) } }
            else if let array = value as? [Any] { for (i, child) in array.enumerated() { rejectNulls(child, path: path + "[\(i)]") } }
        }
        rejectNulls(root, path: "$")
        func keys(_ object: [String: Any], _ allowed: Set<String>, _ path: String) {
            for key in object.keys.sorted() where !allowed.contains(key) {
                diagnostics.append(.init("unknown-field", "\(path).\(key)", "Unknown field. Check the published schema."))
            }
        }
        keys(root, ["schemaVersion", "id", "title", "theme", "watermark", "root", "nodes", "containers", "connectors", "assets"], "$")
        if let theme = root["theme"] as? [String: Any] { keys(theme, ["preset", "version", "seed", "strokeWidth", "fontFamily", "fontSize"], "$.theme") }
        for collection in ["nodes", "containers", "connectors", "assets"] {
            guard let entries = root[collection] as? [String: Any] else { continue }
            for id in entries.keys.sorted() {
                guard let value = entries[id] as? [String: Any] else { continue }
                let p = "$.\(collection).\(id)"
                switch collection {
                case "nodes": keys(value, ["type", "label", "shape", "position", "width", "height", "asset", "variant", "strokeWidth"], p)
                case "containers":
                    keys(value, ["label", "layout", "children", "allowedChildTypes", "position", "width", "height", "strokeWidth"], p)
                    if let layout = value["layout"] as? [String: Any] {
                        keys(layout, ["mode", "gap", "padding", "rows", "columns", "cells"], p + ".layout")
                        if let cells = layout["cells"] as? [String: Any] {
                            for child in cells.keys.sorted() {
                                if let cell = cells[child] as? [String: Any] { keys(cell, ["row", "column", "rowSpan", "columnSpan"], p + ".layout.cells." + child) }
                            }
                        }
                    }
                case "connectors":
                    keys(value, ["from", "to", "label", "direction", "routing", "dashed", "waypoints", "strokeWidth"], p)
                    for side in ["from", "to"] { if let endpoint = value[side] as? [String: Any] { keys(endpoint, ["element", "side"], p + "." + side) } }
                    if let points = value["waypoints"] as? [[String: Any]] { for (index, point) in points.enumerated() { keys(point, ["x", "y"], p + ".waypoints[\(index)]") } }
                default: keys(value, ["name", "source", "viewBox", "paths", "rendering"], p)
                }
                if let point = value["position"] as? [String: Any] { keys(point, ["x", "y"], p + ".position") }
            }
        }
        if !diagnostics.isEmpty { throw DiagramError.invalid(diagnostics) }
    }
}

public enum Validator {
    public static func validate(_ d: Diagram) -> [Diagnostic] {
        var issues: [Diagnostic] = []
        func report(_ code: String, _ path: String, _ message: String, _ id: String? = nil) { issues.append(.init(code, path, message, element: id)) }
        func checkStroke(_ value: Double?, path: String, id: String) {
            if let value, !value.isFinite || !(0.5...8).contains(value) { report("numeric-range", path + ".strokeWidth", "Line width must be between 0.5 and 8.", id) }
        }
        if d.schemaVersion != 1 { report("unsupported-version", "$.schemaVersion", "Use schema version 1. This file will not be rewritten.") }
        if d.theme.version != 1 { report("unsupported-theme", "$.theme.version", "Use theme version 1.") }
        if !(0.5...8).contains(d.theme.strokeWidth) { report("numeric-range", "$.theme.strokeWidth", "Stroke width must be between 0.5 and 8.") }
        if !(10...36).contains(d.theme.fontSize) { report("numeric-range", "$.theme.fontSize", "Font size must be between 10 and 36.") }
        if d.id.isEmpty { report("empty-id", "$.id", "Choose a stable document ID.") }
        if d.containers[d.root] == nil { report("missing-root", "$.root", "Root must reference a container.") }
        let nodeIDs = Set(d.nodes.keys), containerIDs = Set(d.containers.keys), connectorIDs = Set(d.connectors.keys)
        let ids = nodeIDs.union(containerIDs)
        for id in nodeIDs.intersection(containerIDs).union(ids.intersection(connectorIDs)).sorted() {
            report("duplicate-id", "$", "IDs must be unique across nodes, containers, and connectors.", id)
        }
        for id in ids.union(connectorIDs).sorted() where id.isEmpty { report("empty-id", "$", "Element IDs cannot be empty.") }
        var owners: [String: [String]] = [:]
        for id in d.containers.keys.sorted() {
            let c = d.containers[id]!, p = "$.containers.\(id)"
            checkStroke(c.strokeWidth, path: p, id: id)
            for (name, number) in [("width", c.width), ("height", c.height)] {
                if let number, !number.isFinite || !(20...100000).contains(number) { report("numeric-range", p + "." + name, "Minimum size must be between 20 and 100000.", id) }
            }
            if !(0...200).contains(c.layout.gap) || !(0...200).contains(c.layout.padding) { report("numeric-range", p + ".layout", "Gap and padding must be between 0 and 200.", id) }
            for (field, value) in [("rows", c.layout.rows), ("columns", c.layout.columns)] {
                if let value, !(1...32).contains(value) { report("numeric-range", p + ".layout." + field, "Choose 1–32 rows and columns.", id) }
            }
            if c.layout.mode == .grid {
                do { _ = try GridLayout.plan(c, id: id) }
                catch DiagramError.invalid(let diagnostics) { issues += diagnostics }
                catch { report("grid-layout", p + ".layout", error.localizedDescription, id) }
            } else {
                for (child, cell) in c.layout.cells ?? [:] {
                    if !c.children.contains(child) { report("grid-child", p + ".layout.cells." + child, "Grid cells must reference this container's direct children.", id) }
                    if ![cell.row, cell.column, cell.rowSpan, cell.columnSpan].allSatisfy({ (1...32).contains($0) }) { report("numeric-range", p + ".layout.cells." + child, "Cell indices and spans must be between 1 and 32.", id) }
                }
            }
            for child in c.children {
                if !ids.contains(child) { report("missing-child", p + ".children", "Remove or define child '\(child)'.", id) }
                owners[child, default: []].append(id)
                let type = d.nodes[child]?.type ?? "container"
                if let allowed = c.allowedChildTypes, !allowed.contains(type) { report("disallowed-child", p + ".children", "'\(child)' is type '\(type)'. Allowed: \(allowed.joined(separator: ", ")).", id) }
            }
            if let point = c.position, !valid(point) { report("numeric-range", p + ".position", "Coordinates must be finite and within ±100000.", id) }
        }
        for id in ids.sorted() {
            let count = owners[id]?.count ?? 0
            if id == d.root && count != 0 { report("root-parent", "$.root", "The root cannot be a child.", id) }
            if id != d.root && count != 1 { report("ownership", "$", "'\(id)' must appear in exactly one container's children (found \(count)).", id) }
        }
        var active: Set<String> = [], done: Set<String> = []
        func walk(_ id: String, depth: Int) {
            if active.contains(id) { report("containment-cycle", "$.containers.\(id).children", "Containment cannot form a cycle.", id); return }
            if done.contains(id) { return }
            if depth > 32 { report("nesting-limit", "$.containers.\(id)", "Keep nesting within 32 levels.", id); return }
            active.insert(id)
            for child in d.containers[id]?.children ?? [] where d.containers[child] != nil { walk(child, depth: depth + 1) }
            active.remove(id); done.insert(id)
        }
        if d.containers[d.root] != nil { walk(d.root, depth: 0) }
        for id in d.containers.keys.sorted() { walk(id, depth: 0) }
        for id in d.nodes.keys.sorted() {
            let n = d.nodes[id]!, p = "$.nodes.\(id)"
            checkStroke(n.strokeWidth, path: p, id: id)
            if n.type.isEmpty { report("empty-type", p + ".type", "Provide a semantic type.", id) }
            for (name, number) in [("width", n.width), ("height", n.height)] {
                if let number, !(20...4000).contains(number) { report("numeric-range", p + "." + name, "Size must be between 20 and 4000.", id) }
            }
            if let point = n.position, !valid(point) { report("numeric-range", p + ".position", "Coordinates must be finite and within ±100000.", id) }
            if let asset = n.asset, d.assets[asset] == nil { report("missing-asset", p + ".asset", "Embed asset '\(asset)' in the document.", id) }
        }
        for id in d.connectors.keys.sorted() {
            let e = d.connectors[id]!, p = "$.connectors.\(id)"
            checkStroke(e.strokeWidth, path: p, id: id)
            for (name, endpoint) in [("from", e.from), ("to", e.to)] where !ids.contains(endpoint.element) || endpoint.element == d.root {
                report("missing-endpoint", p + "." + name + ".element", "Choose an existing node or non-root container.", id)
            }
            if (e.waypoints ?? []).contains(where: { !valid($0) }) { report("numeric-range", p + ".waypoints", "Waypoints must be finite and within ±100000.", id) }
        }
        for id in d.assets.keys.sorted() {
            let a = d.assets[id]!, p = "$.assets.\(id)"
            if a.viewBox.count != 4 || !a.viewBox.allSatisfy({ $0.isFinite && abs($0) <= 100000 }) || a.viewBox.dropFirst(2).contains(where: { $0 <= 0 }) {
                report("invalid-asset", p + ".viewBox", "Use [x, y, positiveWidth, positiveHeight].", id)
            }
            if a.paths.isEmpty { report("invalid-asset", p + ".paths", "Provide at least one vector path.", id) }
            for path in a.paths { do { _ = try SVGPath.parse(path) } catch { report("invalid-asset", p + ".paths", error.localizedDescription, id); break } }
        }
        if d.nodes.count + d.containers.count > 2000 { report("size-limit", "$", "This prototype supports up to 2000 elements.") }
        return issues
    }
    private static func valid(_ p: Point) -> Bool { p.x.isFinite && p.y.isFinite && abs(p.x) <= 100000 && abs(p.y) <= 100000 }
}
