import Foundation

public struct RenderSpec: Codable, Equatable, Sendable {
    public let root: String
    public let elements: [String: RenderElement]

    public init(root: String, elements: [String: RenderElement]) {
        self.root = root
        self.elements = elements
    }

    public static func decode(_ data: Data) throws -> RenderSpec {
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = raw.object, Set(object.keys) == ["root", "elements"] else {
            throw RendererError("This profile requires root and elements; initial state is supplied by the host")
        }
        guard let elements = object["elements"]?.object else { throw RendererError("Expected elements map") }
        let allowed: Set<String> = ["type", "props", "children", "slots", "visible", "on", "repeat"]
        for (key, value) in elements {
            guard let element = value.object, Set(element.keys).isSubset(of: allowed),
                  element["children"]?.array != nil, element["props"]?.object != nil else {
                throw RendererError("Unsupported or malformed element: \(key)")
            }
            for binding in element["on"]?.object?.values ?? Dictionary<String, JSONValue>().values {
                guard let action = binding.object, Set(action.keys).isSubset(of: ["action", "params"]) else {
                    throw RendererError("Only single action/params event bindings are supported")
                }
            }
            if let repeatValue = element["repeat"] {
                guard let repeatObject = repeatValue.object, Set(repeatObject.keys).isSubset(of: ["statePath", "key"]) else {
                    throw RendererError("Unsupported repeat definition: \(key)")
                }
            }
        }
        return try JSONDecoder().decode(RenderSpec.self, from: data)
    }
}

public struct RenderElement: Codable, Equatable, Sendable {
    public let type: String
    public let props: [String: JSONValue]
    public let children: [String]
    public let slots: [String: [String]]?
    public let visible: JSONValue?
    public let on: [String: ActionBinding]?
    public let `repeat`: RepeatDefinition?

    public init(type: String, props: [String: JSONValue] = [:], children: [String] = [],
                slots: [String: [String]]? = nil, visible: JSONValue? = nil,
                on: [String: ActionBinding]? = nil, repeat repetition: RepeatDefinition? = nil) {
        self.type = type; self.props = props; self.children = children
        self.slots = slots; self.visible = visible; self.on = on; self.repeat = repetition
    }
}

public struct RepeatDefinition: Codable, Equatable, Sendable {
    public let statePath: String
    public let key: String
    public init(statePath: String, key: String) { self.statePath = statePath; self.key = key }
}

public struct ActionBinding: Codable, Equatable, Sendable {
    public let action: String
    public let params: [String: JSONValue]?
    public init(action: String, params: [String: JSONValue]? = nil) { self.action = action; self.params = params }
}

public struct RenderContext: Codable, Equatable, Sendable {
    public let threadId: String
    public let viewId: String
    public let revision: Int
    public init(threadId: String, viewId: String, revision: Int) {
        self.threadId = threadId; self.viewId = viewId; self.revision = revision
    }
}

public struct ComponentDefinition: Codable, Sendable {
    public let properties: [String: PropertyDefinition]
    public let slots: [String]
    public let events: [String]
    public let required: [String]
}

public struct PropertyDefinition: Codable, Sendable {
    public let type: String
    public let values: [JSONValue]?
    public let writable: Bool?

    public func validate(_ value: JSONValue, name: String) throws {
        let valid: Bool
        switch type {
        case "string": valid = value.string != nil
        case "number": valid = value.number?.isFinite == true
        case "boolean": valid = value.bool != nil
        case "array": valid = value.array != nil
        case "object": valid = value.object != nil
        case "scalar": valid = value.isScalar
        default: throw RendererError("Unsupported Catalog property type: \(type)")
        }
        guard valid, values?.contains(value) ?? true else { throw RendererError("Invalid property: \(name)") }
    }
}

public struct RenderCatalog: Codable, Sendable {
    public let version: String
    public let components: [String: ComponentDefinition]
    public let actions: [String]

    private static let bundledCatalog = Result {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw RendererError("Missing bundled Catalog")
        }
        return try JSONDecoder().decode(RenderCatalog.self, from: Data(contentsOf: url))
    }

    public static func bundled() throws -> RenderCatalog { try bundledCatalog.get() }

    public func validate(_ spec: RenderSpec) throws {
        guard version == RenderDocument.currentProtocolVersion else { throw RendererError("Unsupported Catalog version") }
        guard !spec.elements.isEmpty, spec.elements.count <= 256, spec.elements[spec.root] != nil else {
            throw RendererError("Invalid root or element count")
        }
        for (key, element) in spec.elements {
            guard !key.isEmpty, let component = components[element.type] else {
                throw RendererError("Unregistered component: \(element.type)")
            }
            guard Set(element.props.keys).isSubset(of: Set(component.properties.keys)),
                  Set(component.required).isSubset(of: Set(element.props.keys)) else {
                throw RendererError("Unknown or missing properties: \(key)")
            }
            if !element.children.isEmpty && !component.slots.contains("default") {
                throw RendererError("Component has no default slot: \(key)")
            }
            for slot in element.slots?.keys ?? Dictionary<String, [String]>().keys {
                guard slot != "default", component.slots.contains(slot) else { throw RendererError("Unknown named slot: \(slot)") }
            }
            for (event, binding) in element.on ?? [:] {
                guard component.events.contains(event), actions.contains(binding.action) else {
                    throw RendererError("Unregistered event or action: \(key).\(event)")
                }
                guard binding.params != nil else { throw RendererError("Action parameters required") }
                if ["focus", "blur", "change"].contains(event), binding.action != "setState" {
                    throw RendererError("Focus/blur/change events must use local setState")
                }
            }
            if element.repeat != nil && (!component.slots.contains("default") || element.slots != nil) {
                throw RendererError("Repeat requires a default-slot container without named slots")
            }
        }
        var active = Set<String>()
        var reachable = Set<String>()
        var visits = 0
        func visit(_ key: String, depth: Int) throws {
            visits += 1
            guard visits <= 2048, depth <= 16, let element = spec.elements[key] else { throw RendererError("Missing reference or graph budget: \(key)") }
            guard !active.contains(key) else { throw RendererError("Cycle in element graph: \(key)") }
            active.insert(key); reachable.insert(key)
            let references = element.children + (element.slots ?? [:]).values.flatMap { $0 }
            guard Set(references).count == references.count else { throw RendererError("Duplicate child reference: \(key)") }
            for child in references { try visit(child, depth: depth + 1) }
            active.remove(key)
        }
        try visit(spec.root, depth: 0)
        guard reachable.count == spec.elements.count else { throw RendererError("Unreachable elements are not supported") }
    }
}
