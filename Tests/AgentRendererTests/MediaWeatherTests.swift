import Testing
import AgentRenderer
import AgentRendererCore
import AgentRendererExamples

@Test @MainActor func musicControlsDispatchTheTrackFromTheCard() async throws {
    let sample = try RendererExample.load("music-player")
    var actions: [ActionEnvelope] = []
    let session = try RendererSession(spec: sample.spec, state: sample.state, context: sample.context, catalog: .bundled()) {
        actions.append($0)
        return ActionOutcome(status: .completed, message: "ok")
    }
    let node = try #require(session.root)
    for event in ["play", "pause"] {
        await session.emit(instanceId: node.id, event: event)
        #expect(actions.last?.params["actionId"] == .string("sample.audio." + event))
        #expect(actions.last?.params["trackId"] == .string("tone-1"))
    }
}

@Test func invalidPlaybackTimeAndForecastRangesAreRejected() throws {
    for (name, path, value) in [
        ("music-player", "/data/elapsed", JSONValue.number(91)),
        ("weather-forecast", "/data/forecast/0/high", .number(0)),
        ("weather-forecast", "/data/forecast/0/condition", .string("unknown"))
    ] {
        let sample = try RendererExample.load(name)
        let engine = try RenderEngine(spec: sample.spec, catalog: .bundled())
        var state = sample.state
        try state.set(value, at: path)
        #expect(throws: RendererError.self) { try engine.resolve(state: state) }
    }
}
