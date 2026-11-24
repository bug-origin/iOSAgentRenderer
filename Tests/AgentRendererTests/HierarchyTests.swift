import Testing
import AgentRendererCore

@Test func sankeyValidatesFlowsAndComputesLayers() throws {
    let nodes = JSONValue.array([.object(["id": .string("a"), "label": .string("A")]), .object(["id": .string("b"), "label": .string("B")])])
    let ab = JSONValue.object(["source": .string("a"), "target": .string("b"), "value": .number(0.5)])
    let ba = JSONValue.object(["source": .string("b"), "target": .string("a"), "value": .number(0.5)])
    let chart = try SankeyData(props: ["nodes": nodes, "links": .array([ab])])
    #expect(chart.nodes.map(\.layer) == [0, 1])
    #expect(chart.nodes.map(\.weight) == [0.5, 0.5])
    #expect(throws: RendererError.self) { try SankeyData(props: ["nodes": nodes, "links": .array([ab, ba])]) }
    #expect(throws: RendererError.self) { try SankeyData(props: ["nodes": nodes, "links": .array([ab, ab])]) }
}

@Test func sunburstDerivesHierarchyAndRejectsDuplicateOrAmbiguousValues() throws {
    let child = JSONValue.object(["id": .string("child"), "label": .string("Child"), "value": .number(25)])
    var parent: [String: JSONValue] = ["id": .string("parent"), "label": .string("Parent"), "children": .array([child])]
    let chart = try SunburstData(data: .array([.object(parent)]))
    #expect(chart.depth == 2)
    #expect(chart.sectors.map(\.value) == [25, 25])
    #expect(chart.sectors.allSatisfy { $0.start == 0 && $0.end == 1 })
    parent["value"] = .number(30)
    #expect(throws: RendererError.self) { try SunburstData(data: .array([.object(parent)])) }
    #expect(throws: RendererError.self) { try SunburstData(data: .array([child, child])) }
    #expect(try SunburstData(data: .array([])).sectors.isEmpty)
}
