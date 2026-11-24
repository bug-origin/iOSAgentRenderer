import Testing
import AgentRendererCore

@Test func recordMediaSupportsEmptyFieldsAndRejectsUnsafeImages() throws {
    let image: JSONValue = .object(["src": .string("https://example.com/photo.jpg"), "alt": .string("Photo")])
    try InformationData.validate(type: "RecordCard", props: ["image": image, "status": .object(["label": .string("Top match"), "tone": .string("success")])])
    #expect(throws: RendererError.self) { try InformationData.validate(type: "RecordCard", props: ["image": .object(["src": .string("javascript:alert(1)"), "alt": .string("Unsafe")])]) }
    #expect(throws: RendererError.self) { try InformationData.validate(type: "RecordCard", props: ["status": .object(["label": .string("Unknown"), "tone": .string("arbitrary")])]) }
    #expect(throws: RendererError.self) { try InformationData.validate(type: "RecordCard", props: ["image": .object(["src": .string("https://example.com/photo.jpg")])]) }
}
