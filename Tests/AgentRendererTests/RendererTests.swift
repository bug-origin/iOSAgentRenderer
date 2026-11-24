import Foundation
import Testing
import AgentRenderer
import AgentRendererCore
import AgentRendererExamples

private func nodes(_ root: ResolvedNode?) -> [ResolvedNode] {
    guard let root else { return [] }
    return [root] + root.children.flatMap { nodes($0) } + root.slots.values.flatMap { $0.flatMap { nodes($0) } }
}

private func engine(_ example: RendererExample) throws -> RenderEngine {
    try RenderEngine(spec: example.spec, catalog: .bundled())
}

@Test(arguments: RendererExample.names)
func canonicalExamplesResolve(_ name: String) throws {
    let example = try RendererExample.load(name)
    let tree = try #require(try engine(example).resolve(state: example.state))
    #expect(tree.elementKey == "root")
    #expect(!nodes(tree).isEmpty)
}

@Test
func cardHasTwoFooterActionsWithBoundData() throws {
    let example = try RendererExample.load("sequence-card")
    let tree = try #require(try engine(example).resolve(state: example.state))
    let footer = try #require(tree.slots["footer"]?.first)
    #expect(footer.children.map(\.elementKey) == ["details", "next"])
    let metric = try #require(nodes(tree).first { $0.elementKey == "count" })
    #expect(metric.props["value"] == .number(5))
}

@Test
func filteredRepeatKeepsIdentityAndCorrectObjectContext() throws {
    let example = try RendererExample.load("shape-list")
    let engine = try engine(example)
    let initial = nodes(try engine.resolve(state: example.state)).filter { $0.elementKey == "shape" }
    #expect(initial.count == 3)
    var state = example.state
    try state.set(.string("polygon"), at: "/ui/filter")
    let filtered = nodes(try engine.resolve(state: state)).filter { $0.elementKey == "shape" }
    #expect(filtered.count == 2)
    #expect(filtered.map(\.id) == [initial[0].id, initial[2].id])
    #expect(filtered.map { $0.scope?.item.object?["id"] } == [.string("triangle"), .string("square")])
}

@Test
func pointerEscapesAndArrayIndexesAreDeterministic() throws {
    var state = JSONValue.object(["a/b": .object(["~name": .array([.string("one"), .string("two")])])])
    #expect(try state.value(at: "/a~1b/~0name/1") == .string("two"))
    try state.set(.string("changed"), at: "/a~1b/~0name/0")
    #expect(try state.value(at: "/a~1b/~0name/0") == .string("changed"))
    #expect(throws: RendererError.self) { try state.value(at: "/a~2b") }
    #expect(throws: RendererError.self) { try state.value(at: "/a~1b/~0name/01") }
}

@Test
func graphCycleMissingReferenceAndUnknownSlotAreRejected() throws {
    let catalog = try RenderCatalog.bundled()
    #expect(throws: RendererError.self) {
        try catalog.validate(RenderSpec(root: "a", elements: ["a": RenderElement(type: "Stack", children: ["a"])]))
    }
    #expect(throws: RendererError.self) {
        try catalog.validate(RenderSpec(root: "a", elements: ["a": RenderElement(type: "Stack", children: ["missing"])]))
    }
    #expect(throws: RendererError.self) {
        try catalog.validate(RenderSpec(root: "a", elements: ["a": RenderElement(type: "Card", slots: ["unknown": []])]))
    }
}

@Test
func unsupportedProfileFeaturesAndUnknownComponentsAreRejected() throws {
    let unsupported = Data(#"{"root":"a","elements":{"a":{"type":"Card","props":{},"children":[],"watch":{}}}}"#.utf8)
    #expect(throws: RendererError.self) { try RenderSpec.decode(unsupported) }
    #expect(throws: RendererError.self) {
        try RenderCatalog.bundled().validate(RenderSpec(root: "a", elements: ["a": RenderElement(type: "RunCode")]))
    }
}

@Test
func absentDataInvalidPropertyAndDuplicateRepeatKeysFailClosed() throws {
    let example = try RendererExample.load("sequence-card")
    #expect(throws: RendererError.self) { try engine(example).resolve(state: .object([:])) }
    let malformed = RenderSpec(root: "a", elements: ["a": RenderElement(type: "Button", props: ["label": .number(12)])])
    #expect(throws: RendererError.self) { try RenderEngine(spec: malformed, catalog: .bundled()).resolve(state: .object([:])) }
    let shapes = try RendererExample.load("shape-list")
    var state = shapes.state
    let first = try state.value(at: "/data/shapes/0")
    try state.set(.array([first, first]), at: "/data/shapes")
    #expect(throws: RendererError.self) { try engine(shapes).resolve(state: state) }
}

@Test @MainActor
func registryImplementsTheCompleteCatalog() throws {
    let catalog = try RenderCatalog.bundled()
    #expect(ComponentRegistry.standard().types == Set(catalog.components.keys))
    var registry = ComponentRegistry.standard()
    #expect(throws: RendererError.self) { try registry.register("Card") { $0.children } }
}

@Test @MainActor
func formValidationBlocksDispatchThenSubmitsLatestInput() async throws {
    let example = try RendererExample.load("note-form")
    var captured: [ActionEnvelope] = []
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) {
        captured.append($0)
        return ActionOutcome(status: .accepted, message: "accepted")
    }
    session.setInput(.string(""), at: "/form/note/name")
    let submit = try #require(nodes(session.root).first { $0.elementKey == "submit" })
    await session.emit(instanceId: submit.id, event: "press")
    #expect(captured.isEmpty)
    #expect(session.validationErrors["/form/note/name"] != nil)
    session.setInput(.string("B"), at: "/form/note/name")
    await session.emit(instanceId: submit.id, event: "press")
    let action = try #require(captured.first)
    #expect(action.params["input"]?.object?["name"] == .string("B"))
    #expect(action.context == example.context)
    #expect(action.componentId == "submit")
    #expect(!action.requestId.isEmpty)
    #expect(session.outcome?.status == .accepted)
}

@Test @MainActor
func localEditsCannotChangeReadOnlyData() throws {
    let example = try RendererExample.load("sequence-card")
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) { _ in
        ActionOutcome(status: .completed, message: "unused")
    }
    session.setInput(.number(99), at: "/data/sequence/count")
    #expect(session.state == example.state)
    #expect(session.errorMessage != nil)
    #expect(throws: RendererError.self) { try RenderEngine.validateWritePath("/form") }
    #expect(throws: RendererError.self) { try RenderEngine.validateWritePath("/ui~1private/value") }
}

@Test @MainActor
func clearActionChangesDraftWithoutCallingHost() async throws {
    let example = try RendererExample.load("note-form")
    var calls = 0
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) { _ in
        calls += 1
        return ActionOutcome(status: .completed, message: "unexpected")
    }
    let clear = try #require(nodes(session.root).first { $0.elementKey == "clear" })
    await session.emit(instanceId: clear.id, event: "press")
    #expect(try session.state.value(at: "/form/note/name") == .string(""))
    #expect(calls == 0)
}

@Test @MainActor
func repeatedActionCarriesTheSelectedShape() async throws {
    let example = try RendererExample.load("shape-list")
    var captured: ActionEnvelope?
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) {
        captured = $0
        return ActionOutcome(status: .accepted, message: "accepted")
    }
    let buttons = nodes(session.root).filter { $0.elementKey == "selectShape" }
    await session.emit(instanceId: buttons[1].id, event: "press")
    #expect(captured?.params["shapeId"] == .string("circle"))
    session.setInput(.string("polygon"), at: "/ui/filter")
    captured = nil
    await session.emit(instanceId: buttons[1].id, event: "press")
    #expect(captured == nil)
}

@Test @MainActor
func pendingClickIsDeduplicatedAndOldCompletionCannotOverwriteNewView() async throws {
    let example = try RendererExample.load("sequence-card")
    var continuation: CheckedContinuation<ActionOutcome, Never>?
    var calls = 0
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) { _ in
        calls += 1
        return await withCheckedContinuation { continuation = $0 }
    }
    let button = try #require(nodes(session.root).first { $0.elementKey == "next" })
    let first = Task { await session.emit(instanceId: button.id, event: "press") }
    for _ in 0..<100 where continuation == nil { await Task.yield() }
    let waiting = try #require(continuation)
    await session.emit(instanceId: button.id, event: "press")
    #expect(calls == 1)
    try session.replace(spec: example.spec, state: example.state,
                        context: RenderContext(threadId: "alternate-view", viewId: example.name, revision: 2))
    waiting.resume(returning: ActionOutcome(status: .completed, message: "old result"))
    await first.value
    #expect(session.outcome == nil)
    #expect(session.lastAction == nil)
    #expect(session.pendingInstances.isEmpty)
    #expect(session.context.threadId == "alternate-view")
}

@Test @MainActor
func transportFailureIsUnknownAndNotAutomaticallyRetried() async throws {
    let example = try RendererExample.load("sequence-card")
    var calls = 0
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) { _ in
        calls += 1
        throw RendererError("response lost")
    }
    let button = try #require(nodes(session.root).first { $0.elementKey == "next" })
    await session.emit(instanceId: button.id, event: "press")
    #expect(session.outcome?.status == .unknown)
    #expect(calls == 1)
    #expect(session.lastAction != nil)
}

@Test @MainActor
func olderRevisionAndInvalidReplacementPreserveCurrentState() throws {
    let example = try RendererExample.load("sequence-card")
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) { _ in
        ActionOutcome(status: .accepted, message: "unused")
    }
    #expect(throws: RendererError.self) {
        try session.replace(spec: example.spec, state: example.state,
                            context: RenderContext(threadId: example.context.threadId, viewId: example.context.viewId, revision: 0))
    }
    #expect(throws: RendererError.self) { try session.replace(spec: example.spec, state: .object([:]), context: example.context) }
    #expect(session.state == example.state)
    #expect(session.context == example.context)
}

@Test
func versionedDocumentRejectsUnknownVersionAndMalformedState() throws {
    let example = try RendererExample.load("note-form")
    var raw: [String: JSONValue] = [
        "protocolVersion": .string("agent-ui/0.2"),
        "context": .object(["threadId": .string(""), "viewId": .string("standalone"), "revision": .number(1)]),
        "spec": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(example.spec)),
        "state": example.state,
    ]
    let document = try RenderDocument.decode(JSONEncoder().encode(raw))
    #expect(document.context.threadId.isEmpty)
    let hostDecoder = RenderDocument.decoder(forProtocolVersion: "sample-app/0.1")
    #expect(throws: RendererError.self) { try hostDecoder.decode(RenderDocument.self, from: JSONEncoder().encode(raw)) }
    raw["protocolVersion"] = .string("sample-app/0.1")
    let hostData = try JSONEncoder().encode([raw])
    #expect(throws: RendererError.self) { try JSONDecoder().decode([RenderDocument].self, from: hostData) }
    let cached = try hostDecoder.decode([RenderDocument].self, from: hostData)
    #expect(cached.first?.protocolVersion == "sample-app/0.1")
    #expect(try hostDecoder.decode([RenderDocument].self, from: JSONEncoder().encode(cached)) == cached)
    raw["protocolVersion"] = .string("agent-ui/99")
    #expect(throws: RendererError.self) { try RenderDocument.decode(JSONEncoder().encode(raw)) }
    raw["protocolVersion"] = .string("agent-ui/0.2")
    raw["state"] = .object(["data": .object([:])])
    #expect(throws: RendererError.self) { try RenderDocument.decode(JSONEncoder().encode(raw)) }
}

@Test(arguments: ["line", "area", "bar", "scatter", "pie", "donut"])
func chartKindsAndLocalDataUpdatesResolve(_ kind: String) throws {
    let example = try RendererExample.load("chart-gallery")
    var state = example.state
    try state.set(.string(kind), at: "/ui/chartKind")
    let tree = try engine(example).resolve(state: state)
    let chart = try #require(nodes(tree).first { $0.elementKey == "chart" })
    #expect(chart.props["kind"] == .string(kind))
    #expect(chart.props["points"]?.array?.count == 5)
}

@Test
func chartRejectsAmbiguousIdentityAndInvalidCircularValues() throws {
    let example = try RendererExample.load("chart-gallery")
    let render = try engine(example)
    var state = example.state
    let point: JSONValue = .object(["x": .string("A"), "y": .number(3)])
    try state.set(.array([point, point]), at: "/ui/chartPoints")
    #expect(throws: RendererError.self) { try render.resolve(state: state) }
    try state.set(.string("pie"), at: "/ui/chartKind")
    try state.set(.array([.object(["x": .string("A"), "y": .number(-1)])]), at: "/ui/chartPoints")
    #expect(throws: RendererError.self) { try render.resolve(state: state) }
    try state.set(.array([.object(["x": .string("A"), "y": .number(1), "series": .string("S")])]), at: "/ui/chartPoints")
    #expect(throws: RendererError.self) { try render.resolve(state: state) }
    try state.set(.string("unknown"), at: "/ui/chartKind")
    #expect(throws: RendererError.self) { try render.resolve(state: state) }
}

@Test @MainActor
func inputFocusBlurAndStepNavigationPreserveDrafts() throws {
    let example = try RendererExample.load("form-wizard")
    var calls = 0
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) { _ in
        calls += 1
        return .init(status: .completed, message: "done")
    }
    let name = try #require(nodes(session.root).first { $0.elementKey == "name" })
    let steps = try #require(nodes(session.root).first { $0.elementKey == "wizard" })
    session.setFocus(name.id)
    #expect(session.focusedInstanceId == name.id)
    #expect(try session.state.value(at: "/ui/lastEvent") == .string("focus"))
    session.setFocus(nil)
    #expect(try session.state.value(at: "/ui/lastEvent") == .string("blur"))
    #expect(session.validationErrors["/form/note/name"] != nil)
    #expect(!session.moveStep(instanceId: steps.id, offset: 1))
    session.setInput(.string("A"), at: "/form/note/name")
    #expect(session.moveStep(instanceId: steps.id, offset: 1))
    #expect(!session.moveStep(instanceId: steps.id, offset: 1))
    #expect(session.validationErrors["/form/note/notes"] != nil)
    session.setInput(.string("sample text"), at: "/form/note/notes")
    #expect(session.moveStep(instanceId: steps.id, offset: -1))
    #expect(try session.state.value(at: "/form/note/notes") == .string("sample text"))
    #expect(!session.moveStep(instanceId: steps.id, offset: -1))
    #expect(session.moveStep(instanceId: steps.id, offset: 1))
    #expect(session.moveStep(instanceId: steps.id, offset: 1))
    #expect(!session.moveStep(instanceId: steps.id, offset: 1))
    #expect(calls == 0)
}

@Test
func stepsAndTextAreaRejectInvalidProtocol() throws {
    let example = try RendererExample.load("form-wizard")
    var state = example.state
    try state.set(.number(3), at: "/ui/step")
    #expect(throws: RendererError.self) { try engine(example).resolve(state: state) }
    let spec = RenderSpec(root: "a", elements: ["a": RenderElement(type: "TextArea",
        props: ["label": .string("Notes"), "value": .object(["$bindState": .string("/form/note/notes")]), "rows": .number(99)])])
    #expect(throws: RendererError.self) { try RenderEngine(spec: spec, catalog: .bundled()).resolve(state: example.state) }
    let badFocus = RenderSpec(root: "a", elements: ["a": RenderElement(type: "TextField",
        props: ["label": .string("Name"), "value": .object(["$bindState": .string("/form/note/name")])],
        on: ["focus": ActionBinding(action: "dispatch", params: ["actionId": .string("sample.apply")])])])
    #expect(throws: RendererError.self) { try RenderCatalog.bundled().validate(badFocus) }
}

@Test
func flowchartLayoutSupportsBranchesCyclesAndDisconnectedNodes() throws {
    func node(_ id: String) -> JSONValue { .object(["id": .string(id), "label": .string(id)]) }
    func edge(_ from: String, _ to: String) -> JSONValue { .object(["from": .string(from), "to": .string(to)]) }
    let graph = try FlowchartGraph(nodes: .array([node("a"), node("b"), node("c"), node("d")]),
                                  edges: .array([edge("a", "b"), edge("a", "c"), edge("b", "d"), edge("c", "d")]))
    #expect(graph.layers == [["a"], ["b", "c"], ["d"]])
    let cyclic = try FlowchartGraph(nodes: .array([node("a"), node("b"), node("c"), node("d")]),
                                   edges: .array([edge("a", "b"), edge("b", "a"), edge("b", "b")]))
    #expect(Set(cyclic.layers.flatMap { $0 }) == ["a", "b", "c", "d"])
    #expect(cyclic.edges.count == 3)
}

@Test
func flowchartRejectsInvalidEndpointsDuplicatesAndUnknownNodeTypes() throws {
    let node: JSONValue = .object(["id": .string("a"), "label": .string("Start")])
    #expect(throws: RendererError.self) { try FlowchartGraph(nodes: .array([node, node]), edges: .array([])) }
    #expect(throws: RendererError.self) { try FlowchartGraph(nodes: .array([node]), edges: .array([
        .object(["from": .string("a"), "to": .string("missing")])])) }
    #expect(throws: RendererError.self) { try FlowchartGraph(nodes: .array([
        .object(["id": .string("a"), "label": .string("Start"), "kind": .string("script")])]), edges: .array([])) }
    #expect(throws: RendererError.self) { try FlowchartGraph(nodes: .array([]), edges: .array([])) }
}
