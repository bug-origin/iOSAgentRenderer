import Testing
import AgentRenderer
import AgentRendererCore
import AgentRendererExamples

@Test func safeDiagramParserResolvesBranchesAndRejectsScripts() throws {
    let props = try DiagramData.parse("flowchart LR\nA[Start] --> B{OK?}\nB -->|Yes| C[Done]\nB -->|No| A")
    let graph = try FlowchartGraph(nodes: props["nodes"]!, edges: props["edges"]!)
    #expect(graph.nodes.count == 3)
    #expect(graph.edges.count == 3)
    #expect(props["direction"] == .string("horizontal"))
    #expect(graph.nodes.first(where: { $0.id == "B" })?.kind == "decision")
    #expect(throws: RendererError.self) { try DiagramData.parse("broken") }
    #expect(throws: RendererError.self) { try DiagramData.parse("flowchart TD\nclick A javascript:alert(1)") }
    #expect(throws: RendererError.self) { try DiagramData.parse("flowchart TD\nA -->|missing B") }
}

@Test @MainActor func followupDispatchesChosenPromptThroughStandardAction() async throws {
    let example = try RendererExample.load("composition-gallery")
    var captured: [ActionEnvelope] = []
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) {
        captured.append($0); return ActionOutcome(status: .accepted, message: "ok")
    }
    let followup = try #require(session.root?.children.first { $0.elementKey == "followup" })
    await session.chooseFollowup(instanceId: followup.id, index: 1)
    #expect(captured.first?.params["input"] == .string("隐藏网格"))
    #expect(captured.first?.componentId == "followup")
    await session.chooseFollowup(instanceId: followup.id, index: 100)
    #expect(captured.count == 1)
}
