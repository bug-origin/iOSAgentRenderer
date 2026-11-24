import Foundation
import AgentRendererCore

public struct RendererExample: Codable, Sendable {
    public let name: String
    public let title: String
    public let context: RenderContext
    public let spec: RenderSpec
    public let state: JSONValue

    public static let names = [
        "sequence-card", "note-form", "shape-list", "chart-gallery",
        "form-wizard", "controls-gallery", "extended-input-gallery", "composition-gallery", "flowchart-demo",
    ]
    public static func load(_ name: String) throws -> RendererExample {
        guard names.contains(name), let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw RendererError("Unknown renderer example: \(name)")
        }
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let spec = raw.object?["spec"] else { throw RendererError("Example missing Spec") }
        _ = try RenderSpec.decode(JSONEncoder().encode(spec))
        return try JSONDecoder().decode(RendererExample.self, from: data)
    }
}
