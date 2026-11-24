import Foundation
import Testing
import AgentRenderer
import AgentRendererCore
import AgentRendererExamples

@Test func calendarValuesAndMultiSelectionValidateStrictly() throws {
    #expect(ExtendedInput.date("2026-02-29") == nil)
    #expect(ExtendedInput.date("2028-02-29") != nil)
    #expect(ExtendedInput.date("9:00", time: true) == nil)
    #expect(ExtendedInput.date("23:59", time: true) != nil)
    #expect(ExtendedInput.date("24:00", time: true) == nil)
    #expect(ExtendedInput.error(type: "DateRangePicker", props: ["value": .array([.string("2000-01-03"), .string("2000-01-01")])]) != nil)
    #expect(ExtendedInput.error(type: "CheckboxGroup", props: ["value": .array([]), "required": .bool(true)]) != nil)
    #expect(throws: RendererError.self) {
        try ExtendedInput.validate(type: "ComboBox", props: ["value": .array([.string("a"), .string("b")]), "options": .array([.object(["label": .string("A"), "value": .string("a")])])], bindings: ["value": "/form/value"])
    }
}

@Test @MainActor func extendedInputsBlockInvalidDraftAndSubmitTypedValues() async throws {
    let example = try RendererExample.load("extended-input-gallery")
    var captured: [ActionEnvelope] = []
    let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) {
        captured.append($0); return ActionOutcome(status: .accepted, message: "ok")
    }
    func node(_ key: String) throws -> ResolvedNode { try #require(session.root?.children.first { $0.elementKey == key }) }
    let date = try node("date"), range = try node("range"), layers = try node("layers"), count = try node("count"), submit = try node("submit")
    #expect(!session.setControlValue(.array([.string("disabled")]), instanceId: layers.id))
    #expect(session.setControlValue(.string("2000-01-01"), instanceId: date.id))
    #expect(session.setControlValue(.array([.string("2000-01-01"), .string("2000-01-03")]), instanceId: range.id))
    #expect(session.setControlValue(.array([.string("grid")]), instanceId: layers.id))
    session.setDraftError("请输入有效数字", instanceId: count.id)
    await session.emit(instanceId: submit.id, event: "press")
    #expect(captured.isEmpty)
    session.setDraftError(nil, instanceId: count.id)
    #expect(session.setControlValue(.number(3), instanceId: count.id))
    await session.emit(instanceId: submit.id, event: "press")
    let input = try #require(captured.first?.params["input"]?.object)
    #expect(input["count"] == .number(3))
    #expect(input["layers"] == .array([.string("grid")]))
    #expect(input["range"] == .array([.string("2000-01-01"), .string("2000-01-03")]))
}

@Test func localCalendarDefaultsPreserveWallClockAcrossMidnight() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-15T18:30:00Z"))
    let zone = try #require(TimeZone(secondsFromGMT: 8 * 3600))
    #expect(ExtendedInput.string(ExtendedInput.localDefault(instant, timeZone: zone)) == "2026-10-16")
    #expect(ExtendedInput.string(ExtendedInput.localDefault(instant, time: true, timeZone: zone), time: true) == "02:30")
}
