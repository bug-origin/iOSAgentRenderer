import Foundation

/// Safe Mermaid flowchart subset. Unsupported syntax is shown as a local diagnostic, never executed.
public enum DiagramData {
    public static func parse(_ chart: String) throws -> [String: JSONValue] {
        guard chart.count <= 30_000 else { throw RendererError("Diagram source exceeds 30000 characters") }
        var lines = chart.replacingOccurrences(of: ";", with: "\n").components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("%%") }
        guard !lines.isEmpty else { throw RendererError("图示内容为空") }
        let header = lines.removeFirst().split(separator: " ").map(String.init)
        guard header.count == 2, ["flowchart", "graph"].contains(header[0]), ["TD", "TB", "LR", "BT", "RL"].contains(header[1]) else { throw RendererError("支持 flowchart TD／LR 的流程图语法") }
        let reverse = ["BT", "RL"].contains(header[1])
        let regex = try NSRegularExpression(pattern: #"^([A-Za-z_][A-Za-z0-9_-]*)(?:\[([^\[\]]+)\]|\{([^{}]+)\}|\(([^()]+)\))?$"#)
        var ordered: [String] = [], nodes: [String: JSONValue] = [:], edges: [JSONValue] = []
        func node(_ source: String) throws -> String {
            let token = source.trimmingCharacters(in: .whitespaces)
            let range = NSRange(token.startIndex..., in: token)
            guard let match = regex.firstMatch(in: token, range: range) else { throw RendererError("不支持的图示语法：" + String(token.prefix(80))) }
            func capture(_ index: Int) -> String? { Range(match.range(at: index), in: token).map { String(token[$0]) } }
            let id = capture(1)!
            let explicit = capture(2) ?? capture(3) ?? capture(4)
            let label = (explicit ?? id).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if nodes[id] == nil { ordered.append(id) }
            if nodes[id] == nil || explicit != nil {
                nodes[id] = .object(["id": .string(id), "label": .string(label), "kind": .string(capture(3) != nil ? "decision" : capture(4) != nil ? "start" : "process")])
            }
            return id
        }
        for line in lines {
            let parts = line.components(separatedBy: "-->")
            var previous = try node(parts[0])
            for part in parts.dropFirst() {
                var token = part.trimmingCharacters(in: .whitespaces), label: String?
                if token.hasPrefix("|") {
                    token.removeFirst()
                    guard let end = token.firstIndex(of: "|") else { throw RendererError("图示连线标签未结束") }
                    label = String(token[..<end]); token = String(token[token.index(after: end)...])
                }
                let target = try node(token)
                var edge: [String: JSONValue] = ["from": .string(reverse ? target : previous), "to": .string(reverse ? previous : target)]
                if let label { edge["label"] = .string(label) }
                edges.append(.object(edge)); previous = target
            }
        }
        let rawNodes = JSONValue.array(ordered.compactMap { nodes[$0] }), rawEdges = JSONValue.array(edges)
        _ = try FlowchartGraph(nodes: rawNodes, edges: rawEdges)
        return ["nodes": rawNodes, "edges": rawEdges, "direction": .string(["LR", "RL"].contains(header[1]) ? "horizontal" : "vertical")]
    }
}
