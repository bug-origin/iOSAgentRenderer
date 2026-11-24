import Foundation
import Testing
import AgentRenderer
import AgentRendererCore
import AgentRendererExamples

@Test func sliderQuantizationAndInvalidBounds() throws {
    let range = try SliderRange(props: ["min": .number(-1), "max": .number(1), "step": .number(0.1)])
    #expect(abs(range.snapped(0.26) - 0.3) < 1e-10)
    #expect(range.snapped(-4) == -1)
    #expect(range.snapped(4) == 1)
    #expect(range.contains(0.3))
    #expect(!range.contains(0.35))
    for props: [String: JSONValue] in [
        ["min": .number(1), "max": .number(1)],
        ["step": .number(0)], ["step": .number(3)],
        ["max": .number(.infinity)], ["step": .number(1e-20)]
    ] {
        #expect(throws: RendererError.self) { try SliderRange(props: props) }
    }
}

@MainActor private func descendants(_ root: ResolvedNode?) -> [ResolvedNode] {
    guard let root else { return [] }
    return [root] + root.children.flatMap { descendants($0) }
}

@Test @MainActor func controlsPreserveTypesAndRejectDisabledOrInvalidValues() async throws {
    let example = try RendererExample.load("controls-gallery")
    var actions: [ActionEnvelope] = []
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) {
        actions.append($0)
        return ActionOutcome(status: .accepted, message: "ok")
    }
    func id(_ key: String) throws -> String {
        try #require(descendants(session.root).first { $0.elementKey == key }).id
    }
    let size = try id("size"), mode = try id("mode"), enabled = try id("enabled")
    #expect(!session.setControlValue(.number(43), instanceId: size))
    #expect(session.setControlValue(.number(65), instanceId: size, emitChange: false))
    #expect(!session.setControlValue(.string("65"), instanceId: size))
    #expect(!session.setControlValue(.bool(true), instanceId: try id("disabled")))
    #expect(!session.setControlValue(.string("missing"), instanceId: mode))
    #expect(!session.setControlValue(.string("unavailable"), instanceId: mode))
    session.setFocus(size)
    session.setFocus(nil)
    #expect(actions.isEmpty)
    let submit = try id("submit")
    await session.emit(instanceId: submit, event: "press")
    #expect(actions.isEmpty)
    #expect(!session.validationErrors.isEmpty)
    #expect(session.setControlValue(.string("expanded"), instanceId: mode))
    #expect(session.setControlValue(.bool(true), instanceId: enabled))
    await session.emit(instanceId: submit, event: "press")
    let input = try #require(actions.first?.params["input"]?.object)
    #expect(input["size"] == .number(65))
    #expect(input["mode"] == .string("expanded"))
    #expect(input["enabled"] == .bool(true))
}
