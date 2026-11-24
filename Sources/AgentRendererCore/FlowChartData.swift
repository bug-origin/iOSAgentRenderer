import Foundation

public struct SankeyData: Sendable {
    public struct Node: Sendable { public let id: String; public let label: String; public let layer: Int; public let weight: Double }
    public struct Link: Sendable { public let source: Int; public let target: Int; public let value: Double }
    public let nodes: [Node]
    public let links: [Link]
    public init(props: [String: JSONValue]) throws {
        guard let rawNodes = props["nodes"]?.array, rawNodes.count <= 40, let rawLinks = props["links"]?.array, rawLinks.count <= 80 else { throw RendererError("Sankey supports up to 40 nodes/80 links") }
        var ids: [String: Int] = [:], labels: [String] = [], ordered: [String] = []
        for raw in rawNodes {
            guard let row = raw.object, Set(row.keys) == ["id", "label"], let id = row["id"]?.string, !id.isEmpty, ids[id] == nil, let label = row["label"]?.string, !label.isEmpty else { throw RendererError("Invalid Sankey node") }
            ids[id] = labels.count; labels.append(label); ordered.append(id)
        }
        var links: [Link] = [], edges = Set<String>()
        var incoming = Array(repeating: 0.0, count: labels.count), outgoing = incoming
        var indegree = Array(repeating: 0, count: labels.count)
        for raw in rawLinks {
            guard let row = raw.object, Set(row.keys) == ["source", "target", "value"], let from = row["source"]?.string, let to = row["target"]?.string,
                  let source = ids[from], let target = ids[to], source != target,
                  let value = row["value"]?.number, value.isFinite, value > 0,
                  edges.insert("\(source):\(target)").inserted else { throw RendererError("Invalid Sankey link") }
            incoming[target] += value; outgoing[source] += value; indegree[target] += 1
            guard incoming[target].isFinite, outgoing[source].isFinite else { throw RendererError("Sankey totals overflow") }
            links.append(Link(source: source, target: target, value: value))
        }
        guard incoming.reduce(0, +).isFinite else { throw RendererError("Sankey total overflow") }
        var queue = indegree.indices.filter { indegree[$0] == 0 }, layers = Array(repeating: 0, count: labels.count), cursor = 0
        while cursor < queue.count {
            let node = queue[cursor]; cursor += 1
            for link in links where link.source == node {
                layers[link.target] = max(layers[link.target], layers[node] + 1)
                indegree[link.target] -= 1
                if indegree[link.target] == 0 { queue.append(link.target) }
            }
        }
        guard queue.count == labels.count else { throw RendererError("Sankey requires an acyclic directed graph") }
        self.links = links
        self.nodes = labels.indices.map { Node(id: ordered[$0], label: labels[$0], layer: layers[$0], weight: max(incoming[$0], outgoing[$0])) }
    }
}

public struct SunburstData: Sendable {
    public struct Sector: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let value: Double
        public let depth: Int
        public let start: Double
        public let end: Double
    }
    public let sectors: [Sector]
    public let depth: Int
    public init(data: JSONValue) throws {
        guard let roots = data.array, roots.count <= 40 else { throw RendererError("Sunburst data must be an array") }
        var ids = Set<String>(), weights: [String: Double] = [:], count = 0
        func weight(_ raw: JSONValue, level: Int) throws -> Double {
            count += 1
            guard count <= 200, level < 6, let row = raw.object, Set(row.keys).isSubset(of: ["id", "label", "value", "children"]),
                  let id = row["id"]?.string, !id.isEmpty, ids.insert(id).inserted, row["label"]?.string?.isEmpty == false else { throw RendererError("Invalid Sunburst hierarchy (max200 nodes/6 levels)") }
            let result: Double
            if let children = row["children"]?.array, !children.isEmpty {
                guard row["value"] == nil else { throw RendererError("Sunburst internal value is derived from children") }
                result = try children.reduce(0) { try $0 + weight($1, level: level + 1) }
            } else {
                guard row["children"] == nil || row["children"]?.array != nil, let value = row["value"]?.number, value.isFinite, value >= 0 else { throw RendererError("Sunburst leaf requires nonnegative value") }
                result = value
            }
            guard result.isFinite else { throw RendererError("Sunburst sum overflow") }
            weights[id] = result
            return result
        }
        let total = try roots.reduce(0) { try $0 + weight($1, level: 0) }
        guard total.isFinite else { throw RendererError("Sunburst total overflow") }
        var sectors: [Sector] = []
        func append(_ values: [JSONValue], start: Double, span: Double, level: Int) {
            let sum = values.reduce(0) { $0 + weights[$1.object!["id"]!.text]! }
            guard sum > 0 else { return }
            var cursor = start
            for value in values {
                let row = value.object!, id = row["id"]!.text, weight = weights[id]!, size = span * weight / sum
                if weight > 0 { sectors.append(Sector(id: id, label: row["label"]!.text, value: weight, depth: level, start: cursor, end: cursor + size)) }
                if let children = row["children"]?.array { append(children, start: cursor, span: size, level: level + 1) }
                cursor += size
            }
        }
        append(roots, start: 0, span: 1, level: 0)
        self.sectors = sectors; self.depth = (sectors.map(\.depth).max() ?? 0) + 1
    }
}
