import Foundation

public enum ToolboxAction: Equatable {
    case container, connector, item(String)
}

public struct ToolboxShortcut {
    public let keys: [String]
    public let title: String
    public let action: ToolboxAction
    public var displayKeys: String { keys.map { $0.uppercased() }.joined(separator: " → ") }
}

/// Shared by keyboard handling, menu entries, and tooltips so their keys cannot drift.
public enum ToolboxShortcuts {
    public static let groups = ["T1A", "Databricks", "Azure", "AWS", "OpenAI", "Anthropic"]
    public static let all: [ToolboxShortcut] = [
        .init(keys: ["x"], title: "Container", action: .container),
        .init(keys: ["e"], title: "Connector", action: .connector),
        .init(keys: ["s"], title: "System", action: .item("service")),
        .init(keys: ["d"], title: "Database", action: .item("database")),
        .init(keys: ["q"], title: "Queue", action: .item("queue")),
        .init(keys: ["a"], title: "AI Agent", action: .item("ai-agent")),
        .init(keys: ["u"], title: "User", action: .item("actor")),
        .init(keys: ["t"], title: "Text", action: .item("text")),
        .init(keys: ["f"], title: "File", action: .item("file")),
        .init(keys: ["l"], title: "XLSX", action: .item("xlsx")),
        .init(keys: ["p"], title: "PDF", action: .item("pdf")),
        .init(keys: ["w"], title: "DOCX", action: .item("docx")),
        .init(keys: ["1", "s"], title: "SecondStack", action: .item("secondstack")),
        .init(keys: ["1", "l"], title: "LakeSentry", action: .item("lakesentry")),
        .init(keys: ["1", "8"], title: "8FDE", action: .item("8fde")),
        .init(keys: ["1", "a"], title: "Antares", action: .item("antares")),
        .init(keys: ["1", "t"], title: "T1A", action: .item("t1a")),
        .init(keys: ["2", "d"], title: "Databricks", action: .item("databricks")),
        .init(keys: ["2", "u"], title: "Unity Catalog", action: .item("unity-catalog")),
        .init(keys: ["2", "k"], title: "Delta Lake", action: .item("delta-lake")),
        .init(keys: ["2", "l"], title: "Lakehouse", action: .item("databricks-lakehouse")),
        .init(keys: ["2", "g"], title: "Genie Agent", action: .item("genie-agent")),
        .init(keys: ["3", "a"], title: "Azure", action: .item("azure")),
        .init(keys: ["3", "l"], title: "Data Lake Storage", action: .item("azure-data-lake")),
        .init(keys: ["3", "v"], title: "Virtual Machine", action: .item("azure-vm")),
        .init(keys: ["3", "s"], title: "Storage Account", action: .item("azure-storage")),
        .init(keys: ["3", "q"], title: "SQL Database", action: .item("azure-sql")),
        .init(keys: ["3", "o"], title: "Azure OpenAI", action: .item("azure-openai")),
        .init(keys: ["4", "a"], title: "AWS", action: .item("aws")),
        .init(keys: ["4", "s"], title: "Amazon S3", action: .item("aws-s3")),
        .init(keys: ["4", "e"], title: "Amazon EC2", action: .item("aws-ec2")),
        .init(keys: ["4", "l"], title: "Lambda", action: .item("aws-lambda")),
        .init(keys: ["4", "r"], title: "Amazon RDS", action: .item("aws-rds")),
        .init(keys: ["5", "o"], title: "OpenAI", action: .item("openai")),
        .init(keys: ["5", "a"], title: "OpenAI API", action: .item("openai-api")),
        .init(keys: ["6", "a"], title: "Anthropic", action: .item("anthropic")),
        .init(keys: ["6", "c"], title: "Claude API", action: .item("claude-api"))
    ]
    public static func shortcut(for action: ToolboxAction) -> ToolboxShortcut? { all.first { $0.action == action } }
    public static func matching(_ keys: [String]) -> [ToolboxShortcut] { all.filter { $0.keys.starts(with: keys) } }
    public static func groupHint(_ prefix: String) -> String {
        let tools = matching([prefix])
        guard let number = Int(prefix), groups.indices.contains(number - 1) else { return "" }
        return groups[number - 1] + " · " + tools.map { $0.keys.last!.uppercased() + " " + $0.title }.joined(separator: " · ")
    }
}
