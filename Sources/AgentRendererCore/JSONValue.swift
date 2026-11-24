import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([JSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        }
    }

    public var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    public var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var number: Double? { if case .number(let value) = self { value } else { nil } }
    public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var text: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.formatted(.number.grouping(.never))
        case .bool(let value): value ? "true" : "false"
        case .null: ""
        default: ""
        }
    }

    public var isScalar: Bool {
        switch self { case .array, .object: false; default: true }
    }

    public var truthy: Bool {
        switch self {
        case .null: false
        case .bool(let value): value
        case .number(let value): value != 0
        case .string(let value): !value.isEmpty
        case .array, .object: true
        }
    }

    public func value(at pointer: String) throws -> JSONValue {
        var current = self
        for part in try Self.tokens(pointer) {
            if let object = current.object, let value = object[part] { current = value }
            else if let array = current.array, let index = Self.index(part), array.indices.contains(index) { current = array[index] }
            else { throw RendererError("Missing state path: \(pointer)") }
        }
        return current
    }

    public mutating func set(_ value: JSONValue, at pointer: String) throws {
        let tokens = try Self.tokens(pointer)
        self = try replacing(tokens[...], with: value)
    }

    private func replacing(_ tokens: ArraySlice<String>, with value: JSONValue) throws -> JSONValue {
        guard let head = tokens.first else { return value }
        switch self {
        case .object(var object):
            let existing = object[head] ?? .object([:])
            object[head] = try existing.replacing(tokens.dropFirst(), with: value)
            return .object(object)
        case .array(var array):
            guard let index = Self.index(head), array.indices.contains(index) else {
                throw RendererError("Invalid array index: \(head)")
            }
            array[index] = try array[index].replacing(tokens.dropFirst(), with: value)
            return .array(array)
        default: throw RendererError("Cannot write through a scalar state value")
        }
    }

    public static func tokens(_ pointer: String) throws -> [String] {
        guard pointer.isEmpty || pointer.hasPrefix("/") else { throw RendererError("Expected JSON Pointer: \(pointer)") }
        if pointer.isEmpty { return [] }
        return try pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map { token in
            let raw = String(token)
            let characters = Array(raw)
            for index in characters.indices where characters[index] == "~" {
                guard index + 1 < characters.count, ["0", "1"].contains(characters[index + 1]) else {
                    throw RendererError("Invalid JSON Pointer escape: \(pointer)")
                }
            }
            return raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }

    private static func index(_ token: String) -> Int? {
        guard token == "0" || (!token.hasPrefix("0") && token.allSatisfy(\.isNumber)) else { return nil }
        return Int(token)
    }
}

public struct RendererError: Error, Equatable, Sendable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
