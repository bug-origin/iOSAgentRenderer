import Foundation

/// Versioned host envelope around a json-render-compatible spec and external state.
public struct RenderDocument: Codable, Equatable, Sendable {
    public static let currentProtocolVersion = "agent-ui/0.2"
    private static let protocolVersionKey = CodingUserInfoKey(rawValue: "AgentRenderer.protocolVersion")!

    public let protocolVersion: String
    public let context: RenderContext
    public let spec: RenderSpec
    public let state: JSONValue

    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    /// Use this decoder when a host uses its own version identifier for the same wire format.
    /// The selected identifier is checked on every document, including nested documents in a cache.
    public static func decoder(forProtocolVersion version: String) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[protocolVersionKey] = version
        return decoder
    }

    public init(from decoder: any Decoder) throws {
        let version = decoder.userInfo[Self.protocolVersionKey] as? String ?? Self.currentProtocolVersion
        let raw = try JSONValue(from: decoder)
        guard let object = raw.object,
            Set(object.keys) == ["protocolVersion", "context", "spec", "state"],
            object["protocolVersion"]?.string == version, !version.isEmpty,
            let spec = object["spec"],
            let context = object["context"]?.object,
            Set(context.keys) == ["threadId", "viewId", "revision"],
            let viewId = context["viewId"]?.string, !viewId.isEmpty,
            let revision = context["revision"]?.number, revision >= 1, revision.rounded() == revision,
            let state = object["state"]?.object, Set(state.keys) == ["data", "form", "ui"],
            state.values.allSatisfy({ $0.object != nil })
        else { throw RendererError("Invalid or unsupported render document") }
        self.protocolVersion = version
        self.context = try JSONDecoder().decode(RenderContext.self, from: JSONEncoder().encode(JSONValue.object(context)))
        self.spec = try RenderSpec.decode(JSONEncoder().encode(spec))
        self.state = .object(state)
        _ = try RenderEngine(spec: self.spec, catalog: .bundled()).resolve(state: self.state)
    }
}
