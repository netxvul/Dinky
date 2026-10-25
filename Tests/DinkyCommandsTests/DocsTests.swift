import Foundation
import Testing
import DinkyConfig
@testable import DinkyCommands

/// docs/commands.md is written by hand; `Command.all` owns the names, the docs the prose. These keep them in step.
/// So is the default config docs/configuration.md shows, which is to be the file dinky writes on first run.
struct DocsTests {
    private static func doc(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/\(name)")
        return try! String(contentsOf: url, encoding: .utf8)
    }

    private static let commands = doc("commands.md")

    /// The contents of every `backticked` span in `text`.
    private static func spans(_ text: some StringProtocol) -> [String] {
        text.split(separator: "`", omittingEmptySubsequences: false).enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
    }

    @Test func `Command table lists every command`() {
        // The first table's rows, up to the first line that isn't one.
        let rows = Self.commands.split(separator: "\n").drop { !$0.hasPrefix("|") }.prefix { $0.hasPrefix("|") }
        let names = rows.flatMap { row in
            // Cells split at unescaped pipes; `\|` separates alternatives inside a command.
            let firstCell = row.replacing("\\|", with: "").split(separator: "|", omittingEmptySubsequences: false)[1]
            return Self.spans(firstCell).map { String($0.prefix { $0 != " " }) }
        }
        #expect(!names.isEmpty)
        #expect(Set(names) == Set(Command.all.map(\.name)))
    }

    @Test func `Every format variable is documented`() {
        let documented = Set(Self.spans(Self.commands))
        for name in WorkspaceQuery.variables + WindowQuery.variables + MonitorQuery.variables + Format.special {
            #expect(documented.contains(name) || documented.contains("%{\(name)}"), "\(name)")
        }
    }

    @Test func `Default config page is the file dinky writes`() throws {
        let page = Self.doc("configuration.md")
        let after = try #require(page.components(separatedBy: "## Default config\n\n```toml\n").dropFirst().first)
        let block = try #require(after.components(separatedBy: "\n```").first)
        #expect(block == Config.defaultTOML)
    }
}
