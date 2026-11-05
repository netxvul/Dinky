import CoreGraphics
import Testing
@testable import KexLayout

/// Tree shape as text: "h[1 v[2 3]]", accordions prefixed with "a", e.g. "ah[1 2]", `auto` as "*".
func shape(_ c: Container) -> String {
    let axis = switch c.orientation {
    case .horizontal: "h"
    case .vertical: "v"
    case .auto: "*"
    }
    let kind = (c.mode == .accordion ? "a" : "") + axis
    let inner = c.children.map { node -> String in
        switch node {
        case .window(let id): "\(id)"
        case .container(let child): shape(child)
        }
    }
    return kind + "[" + inner.joined(separator: " ") + "]"
}

/// A workspace with windows 1...n inserted in order.
func workspace(_ n: Int, bounds: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 600),
               gaps: Gaps = .zero, algorithm: TilingAlgorithm = .dwindle(.tiles), padding: CGFloat = 30) -> Workspace {
    var ws = Workspace(bounds: bounds, gaps: gaps, accordionPadding: padding, algorithm: algorithm)
    for id in 0..<n { ws.insert(WindowID(id + 1)) }
    return ws
}

func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: w, height: h)
}

func assertRatios(_ actual: [Double], _ expected: [Double],
                  fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) {
    let location = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    #expect(actual.count == expected.count, sourceLocation: location)
    for (a, e) in zip(actual, expected) { #expect(abs(a - e) <= 1e-9, sourceLocation: location) }
    #expect(abs(actual.reduce(0, +) - 1) <= 1e-9, sourceLocation: location)
}
