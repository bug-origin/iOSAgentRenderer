import Foundation

/// Bounded native graph data. Cycles and self-loops are valid; scripts and arbitrary coordinates are not.
public struct FlowchartGraph: Equatable, Sendable {
    public struct Node: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String
        public let kind: String
        public let status: String
        public let detail: String?
    }
    public struct Edge: Identifiable, Equatable, Sendable {
        public let from: String
        public let to: String
        public let label: String?
        public var id: String { "\(from.utf8.count):\(from)\(to)" }
    }
    public let nodes: [Node]
    public let edges: [Edge]
    public let layers: [[String]]

    public init(nodes rawNodes: JSONValue, edges rawEdges: JSONValue) throws {
        guard let values = rawNodes.array, !values.isEmpty, values.count <= 40,
              let links = rawEdges.array, links.count <= 80 else { throw RendererError("Flowchart requires 1...40 nodes and at most 80 edges") }
        nodes = try values.map { value in
            guard let object = value.object, Set(object.keys).isSubset(of: ["id", "label", "kind", "status", "detail"]),
                  let id = object["id"]?.string, !id.isEmpty, id.count <= 100,
                  let label = object["label"]?.string, !label.isEmpty, label.count <= 200,
                  object["kind"] == nil || ["start", "end", "process", "decision"].contains(object["kind"]?.string ?? ""),
                  object["status"] == nil || ["pending", "active", "completed", "failed"].contains(object["status"]?.string ?? ""),
                  object["detail"] == nil || (object["detail"]?.string != nil && (object["detail"]?.string?.count ?? 0) <= 2000) else {
                throw RendererError("Invalid Flowchart node")
            }
            return Node(id: id, label: label, kind: object["kind"]?.string ?? "process",
                        status: object["status"]?.string ?? "pending", detail: object["detail"]?.string)
        }
        let ids = Set(nodes.map(\.id))
        guard ids.count == nodes.count else { throw RendererError("Duplicate Flowchart node ID") }
        edges = try links.map { value in
            guard let object = value.object, Set(object.keys).isSubset(of: ["from", "to", "label"]),
                  let from = object["from"]?.string, let to = object["to"]?.string,
                  ids.contains(from), ids.contains(to),
                  object["label"] == nil || (object["label"]?.string != nil && (object["label"]?.string?.count ?? 0) <= 100) else {
                throw RendererError("Flowchart edge must reference existing nodes")
            }
            return Edge(from: from, to: to, label: object["label"]?.string)
        }
        guard Set(edges.map(\.id)).count == edges.count else { throw RendererError("Duplicate Flowchart edge") }
        // Longest-path layers for DAGs; deterministic breadth-first fallback handles cyclic graphs.
        var indegree = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        var outgoing: [String: [String]] = [:]
        for edge in edges { indegree[edge.to, default: 0] += 1; outgoing[edge.from, default: []].append(edge.to) }
        var ranks = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, 0) })
        var queue = nodes.filter { indegree[$0.id] == 0 }.map(\.id)
        var visited = 0
        while visited < queue.count {
            let id = queue[visited]; visited += 1
            for target in outgoing[id] ?? [] {
                ranks[target] = max(ranks[target] ?? 0, (ranks[id] ?? 0) + 1)
                indegree[target, default: 0] -= 1
                if indegree[target] == 0 { queue.append(target) }
            }
        }
        if visited != nodes.count {
            ranks = [:]
            func traverse(_ start: String) {
                var pending = [start], cursor = 0
                ranks[start] = 0
                while cursor < pending.count {
                    let id = pending[cursor]; cursor += 1
                    for target in outgoing[id] ?? [] where ranks[target] == nil {
                        ranks[target] = (ranks[id] ?? 0) + 1; pending.append(target)
                    }
                }
            }
            for node in nodes where !edges.contains(where: { $0.to == node.id }) { traverse(node.id) }
            for node in nodes where ranks[node.id] == nil { traverse(node.id) }
        }
        let orderedNodes = nodes
        layers = (0...(ranks.values.max() ?? 0)).map { rank in orderedNodes.filter { ranks[$0.id] == rank }.map(\.id) }
    }
}
