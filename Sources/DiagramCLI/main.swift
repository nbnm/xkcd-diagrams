import Foundation
import DiagramCore
import Darwin

let args = Array(CommandLine.arguments.dropFirst())
let json = args.contains("--json")
func option(_ name: String) -> String? { guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }; return args[i + 1] }
func output<T: Encodable>(_ value: T) throws {
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try e.encode(value)); print("")
}
func file(_ index: Int = 1) throws -> URL {
    guard args.count > index, !args[index].hasPrefix("--") else { throw DiagramError.message("Missing diagram file. Run 'diagram help'.") }
    return URL(fileURLWithPath: args[index])
}
let help = """
XKCD Diagrams — local diagram tools

diagram init <file.diagram.json> [--mode diagram|drawing|timeline] [--example]
diagram validate <file> [--json]
diagram inspect <file> [--json]
diagram revision <file>
diagram render <file> --format svg|png --output <path> [--scale 2] [--transparent]
diagram write <file> --from <candidate.json> --expect <sha256>
diagram library list
diagram schema

Files use schema version 1. Render works without the editor.
"""
do {
    switch args.first ?? "help" {
    case "help", "--help", "-h": print(help)
    case "init":
        let url = try file()
        let modeValue = option("--mode") ?? "diagram"
        guard let mode = DocumentMode(rawValue: modeValue), !args.contains("--mode") || option("--mode") != nil else { throw DiagramError.message("Use --mode diagram, drawing, or timeline.") }
        var d = mode.blank()
        if args.contains("--example") {
            switch mode {
            case .diagram: d = Library.sample()
            case .timeline: d.title = "Project timeline"; d.timeline = .example()
            case .drawing:
                d.title = "Free drawing"
                d.drawing?.strokes = [InkStroke(points: [Point(x: 40, y: 80), Point(x: 90, y: 45), Point(x: 145, y: 82), Point(x: 195, y: 46), Point(x: 250, y: 80)]), InkStroke(points: [Point(x: 55, y: 170), Point(x: 220, y: 170), Point(x: 205, y: 155), Point(x: 220, y: 170), Point(x: 205, y: 185)])]
                d.nodes["note"] = Node(type: "text", label: "Ideas, sketches, and notes", shape: .text, position: Point(x: 25, y: 210), width: 280)
                d.containers[d.root]?.children = ["note"]
            }
        }
        let revision = try DiagramFiles.write(d, to: url)
        if json { try output(["file": url.path, "revision": revision]) } else { print("Created \(url.path)") }
    case "schema": FileHandle.standardOutput.write(try Library.schema())
    case "library":
        guard args.count > 1 && args[1] == "list" else { throw DiagramError.message("Use 'diagram library list'.") }
        try output(Library.items())
    case "validate":
        let (d, revision) = try DiagramFiles.read(file())
        if json { try output(ValidationReceipt(valid: true, revision: revision, schemaVersion: d.schemaVersion)) }
        else { print("Valid schema 1 \(d.mode.rawValue): \(d.nodes.count) nodes, \(d.drawing?.strokes.count ?? 0) strokes, \(d.timeline?.tasks.count ?? 0) tasks") }
    case "revision": print(try DiagramFiles.read(file()).1)
    case "inspect":
        let (d, revision) = try DiagramFiles.read(file())
        struct Inspection: Codable { var id: String; var title: String; var revision: String; var mode: DocumentMode; var drawing: FreeDrawing?; var timeline: Timeline?; var nodes: [String: Node]; var containers: [String: Container]; var connectors: [String: Connector] }
        try output(Inspection(id: d.id, title: d.title, revision: revision, mode: d.mode, drawing: d.drawing, timeline: d.timeline, nodes: d.nodes, containers: d.containers, connectors: d.connectors))
    case "render":
        let (d, _) = try DiagramFiles.read(file())
        guard let format = option("--format"), ["svg", "png"].contains(format), let path = option("--output") else { throw DiagramError.message("Supply --format svg|png and --output <path>.") }
        let scale: Double
        if let value = option("--scale") { guard let number = Double(value) else { throw DiagramError.message("Invalid --scale value.") }; scale = number } else { scale = 2 }
        let data = try format == "svg" ? Renderer.svg(d, transparent: args.contains("--transparent")) : Renderer.png(d, scale: scale, transparent: args.contains("--transparent"))
        let destination = URL(fileURLWithPath: path), input = try file()
        guard destination.standardizedFileURL != input.standardizedFileURL else { throw DiagramError.message("Export destination cannot overwrite the source document.") }
        try DiagramFiles.writeData(data, to: destination)
        if json { try output(["file": destination.path, "format": format]) } else { print("Exported \(destination.path)") }
    case "write":
        guard let source = option("--from"), let expected = option("--expect") else { throw DiagramError.message("Supply --from <candidate.json> and --expect <sha256>.") }
        let (d, _) = try DiagramFiles.read(URL(fileURLWithPath: source))
        let revision = try DiagramFiles.write(d, to: file(), expectedRevision: expected)
        if json { try output(["revision": revision]) } else { print(revision) }
    default: throw DiagramError.message("Unknown command. Run 'diagram help'.")
    }
} catch {
    if json {
        struct Failure: Codable { var valid = false; var diagnostics: [Diagnostic] }
        let diagnostics: [Diagnostic]
        if case DiagramError.invalid(let issues) = error { diagnostics = issues }
        else { diagnostics = [.init("invalid-document", "$", error.localizedDescription)] }
        try? output(Failure(diagnostics: diagnostics))
    } else { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)) }
    exit(2)
}

struct ValidationReceipt: Encodable {
    var valid: Bool
    var revision: String
    var schemaVersion: Int
}
