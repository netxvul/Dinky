import Testing
@testable import KexConfig

/// Expects `toml` to fail at `path`, on `line` when given, with a description naming the path and containing `text`.
func assertError(_ toml: String, path: String, line: Int? = nil, contains text: String,
                 fileID: String = #fileID, filePath: String = #filePath, sourceLine: Int = #line, column: Int = #column) {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: sourceLine, column: column)
    let error = #expect(throws: ConfigError.self, "expected an error for \(path)", sourceLocation: sourceLocation) {
        try Config.parse(toml)
    }
    guard let error else { return }
    #expect(error.path == path, sourceLocation: sourceLocation)
    if let line { #expect(error.line == line, "\(error)", sourceLocation: sourceLocation) }
    #expect(error.description.contains(text), "\(error)", sourceLocation: sourceLocation)
    #expect(error.description.contains(path), "\(error)", sourceLocation: sourceLocation)
}
