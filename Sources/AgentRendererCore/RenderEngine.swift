import Foundation

public struct RepeatScope: Equatable, Sendable {
    public let item: JSONValue
    public let index: Int
    public init(item: JSONValue, index: Int) { self.item = item; self.index = index }
}

public struct ResolvedNode: Equatable, Sendable, Identifiable {
    public let id: String
    public let elementKey: String
    public let type: String
    public let props: [String: JSONValue]
    public let bindings: [String: String]
    public let children: [ResolvedNode]
    public let slots: [String: [ResolvedNode]]
    public let scope: RepeatScope?
}

public struct RenderEngine: Sendable {
    public let spec: RenderSpec
    public let catalog: RenderCatalog

    public init(spec: RenderSpec, catalog: RenderCatalog) throws {
        try catalog.validate(spec)
        self.spec = spec; self.catalog = catalog
    }

    public func resolve(state: JSONValue) throws -> ResolvedNode? {
        guard state.object != nil else { throw RendererError("Expected state object") }
        var count = 0
        func build(_ key: String, path: String, scope: RepeatScope?) throws -> ResolvedNode? {
            count += 1
            guard count <= 2048, let element = spec.elements[key], let definition = catalog.components[element.type] else {
                throw RendererError("Expanded node limit or missing component")
            }
            if let visible = element.visible, try !isVisible(visible, state: state, scope: scope) { return nil }
            var props: [String: JSONValue] = [:]
            var bindings: [String: String] = [:]
            for (name, value) in element.props {
                let resolved = try resolveValue(value, state: state, scope: scope)
                guard let property = definition.properties[name] else { throw RendererError("Unknown property") }
                try property.validate(resolved, name: "\(key).\(name)")
                props[name] = resolved
                if let pointer = value.object?["$bindState"]?.string {
                    guard property.writable == true else { throw RendererError("Property cannot be two-way bound: \(name)") }
                    try Self.validateWritePath(pointer)
                    bindings[name] = pointer
                }
            }
            try validateComponent(element.type, props: props, bindings: bindings)
            var children: [ResolvedNode] = []
            if let repetition = element.repeat {
                guard let items = try state.value(at: repetition.statePath).array, items.count <= 200 else {
                    throw RendererError("Repeat requires an array of at most 200 items")
                }
                var identities = Set<String>()
                for (index, item) in items.enumerated() {
                    guard let identity = item.object?[repetition.key], identity.string != nil || identity.number != nil else {
                        throw RendererError("Repeat requires a stable scalar key: \(repetition.key)")
                    }
                    let encoded = try JSONEncoder().encode(identity).base64EncodedString()
                    guard identities.insert(encoded).inserted else { throw RendererError("Duplicate repeat key") }
                    let itemScope = RepeatScope(item: item, index: index)
                    for child in element.children {
                        if let node = try build(child, path: path + "/item:" + encoded + "/" + child, scope: itemScope) {
                            children.append(node)
                        }
                    }
                }
            } else {
                for child in element.children {
                    if let node = try build(child, path: path + "/" + child, scope: scope) { children.append(node) }
                }
            }
            var slots: [String: [ResolvedNode]] = [:]
            for (slot, keys) in element.slots ?? [:] {
                slots[slot] = try keys.compactMap { try build($0, path: path + "/slot:" + slot + "/" + $0, scope: scope) }
            }
            if ["Tabs", "Accordion"].contains(element.type) {
                guard element.repeat == nil, let labels = props["labels"]?.array,
                      !labels.isEmpty, labels.count <= 20, labels.allSatisfy({ $0.string?.isEmpty == false }),
                      labels.count == children.count else { throw RendererError("Tabs/Accordion need one visible child per nonempty label (1...20)") }
                if let index = props["defaultValue"]?.number {
                    guard index.rounded() == index, index >= 0, index < Double(labels.count) else { throw RendererError("Invalid default tab") }
                }
            }
            if element.type == "Steps" {
                guard element.repeat == nil, children.count == props["labels"]?.array?.count else {
                    throw RendererError("Steps requires one visible child per label and no repeat")
                }
            }
            return ResolvedNode(id: path, elementKey: key, type: element.type, props: props,
                                bindings: bindings, children: children, slots: slots, scope: scope)
        }
        return try build(spec.root, path: spec.root, scope: nil)
    }

    public func resolveValue(_ value: JSONValue, state: JSONValue, scope: RepeatScope? = nil, depth: Int = 0) throws -> JSONValue {
        guard depth <= 16 else { throw RendererError("Expression depth limit") }
        if let object = value.object {
            let expressionKeys = object.keys.filter { $0.hasPrefix("$") }
            if !expressionKeys.isEmpty {
                guard object.count == 1, let expression = expressionKeys.first else { throw RendererError("Unsupported expression shape") }
                switch expression {
                case "$state", "$bindState":
                    guard let pointer = object[expression]?.string else { throw RendererError("Expected state pointer") }
                    return try state.value(at: pointer)
                case "$item":
                    guard let field = object[expression]?.string, let scope else { throw RendererError("$item requires repeat scope") }
                    if field.isEmpty { return scope.item }
                    guard !field.contains("."), !field.contains("/"), let item = scope.item.object?[field] else {
                        throw RendererError("Missing or unsupported repeat field: \(field)")
                    }
                    return item
                case "$index":
                    guard object[expression] == .bool(true), let scope else { throw RendererError("$index requires repeat scope") }
                    return .number(Double(scope.index))
                default: throw RendererError("Unsupported expression: \(expression)")
                }
            }
            return .object(try object.mapValues { try resolveValue($0, state: state, scope: scope, depth: depth + 1) })
        }
        if let array = value.array {
            return .array(try array.map { try resolveValue($0, state: state, scope: scope, depth: depth + 1) })
        }
        return value
    }

    public func isVisible(_ condition: JSONValue, state: JSONValue, scope: RepeatScope? = nil, depth: Int = 0) throws -> Bool {
        guard depth <= 16 else { throw RendererError("Condition depth limit") }
        if let bool = condition.bool { return bool }
        guard let object = condition.object else { throw RendererError("Expected visibility condition") }
        for operation in ["$and", "$or"] where object[operation] != nil {
            guard object.count == 1, let conditions = object[operation]?.array, !conditions.isEmpty else {
                throw RendererError("Invalid condition group")
            }
            let values = try conditions.map { try isVisible($0, state: state, scope: scope, depth: depth + 1) }
            return operation == "$and" ? values.allSatisfy { $0 } : values.contains(true)
        }
        let sources = ["$state", "$item", "$index"].filter { object[$0] != nil }
        guard sources.count == 1, let source = sources.first,
              Set(object.keys).isSubset(of: [source, "eq", "neq", "not"]),
              !(object["eq"] != nil && object["neq"] != nil),
              object["not"] == nil || object["not"] == .bool(true) else {
            throw RendererError("Unsupported visibility comparison")
        }
        guard let sourceValue = object[source] else { throw RendererError("Missing visibility source") }
        let value = try resolveValue(.object([source: sourceValue]), state: state, scope: scope)
        let result: Bool
        if let expected = object["eq"] ?? object["neq"] {
            guard value.isScalar, expected.isScalar else { throw RendererError("Equality supports scalar values only") }
            result = object["eq"] != nil ? value == expected : value != expected
        } else { result = value.truthy }
        return object["not"] == .bool(true) ? !result : result
    }

    public static func validateWritePath(_ pointer: String) throws {
        let parts = try JSONValue.tokens(pointer)
        guard parts.count >= 2, let namespace = parts.first, ["form", "ui"].contains(namespace) else {
            throw RendererError("Only /form/* and /ui/* are writable")
        }
    }

    private func validateComponent(_ type: String, props: [String: JSONValue], bindings: [String: String]) throws {
        if let format = props["format"] { try ValueFormat.validate(format) }
        if type == "ComposedChart" {
            guard let rows = props["data"]?.array, rows.count <= 500 else { throw RendererError("ComposedChart data limit") }
            var magnitude = 0.0
            var identities = Set<String>(), styles: [String: String] = [:]
            for row in rows {
                guard let item = row.object, Set(item.keys).isSubset(of: ["x", "y", "series", "mark", "axis"]),
                      let x = item["x"]?.string, !x.isEmpty, let series = item["series"]?.string, !series.isEmpty, item["y"]?.number?.isFinite == true,
                      let mark = item["mark"]?.string, ["line", "area", "bar"].contains(mark),
                      item["axis"] == nil || ["left", "right"].contains(item["axis"]?.text ?? "") else { throw RendererError("Invalid ComposedChart row") }
                guard identities.insert("\(series.utf8.count):\(series)\(x)").inserted else { throw RendererError("Duplicate composed category/series") }
                let style = mark + (item["axis"]?.text ?? "left")
                guard styles[series] == nil || styles[series] == style else { throw RendererError("Series mark/axis must be consistent") }
                styles[series] = style
                magnitude += abs(item["y"]!.number!)
                guard magnitude.isFinite else { throw RendererError("Composed numeric range overflow") }
            }
        }
        if type == "ListBlock" {
            guard let items = props["items"]?.array, items.count <= 100, items.allSatisfy({ item in
                guard let row = item.object else { return false }
                return Set(row.keys).isSubset(of: ["label", "value", "description"]) && row["label"]?.string != nil && (row["value"] == nil || row["value"]?.string != nil || row["value"]?.number != nil) && (row["description"] == nil || row["description"]?.string != nil)
            }) else { throw RendererError("Invalid list block rows") }
        }
        if type == "SunburstChart" { _ = try SunburstData(data: props["data"] ?? .null) }
        if type == "SankeyChart" { _ = try SankeyData(props: props) }
        if type == "Followup" {
            guard bindings["value"] != nil, let prompts = props["prompts"]?.array, prompts.count <= 12, prompts.allSatisfy({ $0.string?.isEmpty == false }) else { throw RendererError("Followup needs a writable value and up to 12 prompts") }
        }
        if type == "MusicPlayer" {
            if let artwork = props["artwork"] { try InformationData.validateImage(artwork) }
            guard props["title"]?.string?.isEmpty == false else { throw RendererError("MusicPlayer needs a title") }
            if props["duration"] != nil || props["elapsed"] != nil {
                let elapsed = props["elapsed"]?.number ?? 0
                guard let duration = props["duration"]?.number, duration > 0, duration <= Double(Int32.max),
                      (0...duration).contains(elapsed) else { throw RendererError("Invalid playback time in seconds") }
            }
        }
        if type == "Weather" {
            guard props["location"]?.string?.isEmpty == false, props["temperature"]?.number?.isFinite == true else {
                throw RendererError("Weather needs a location and a finite temperature")
            }
            if let days = props["forecast"]?.array {
                let conditions = catalog.components["Weather"]?.properties["condition"]?.values ?? []
                guard days.count <= 14 else { throw RendererError("Forecast supports up to 14 days") }
                for day in days {
                    guard let row = day.object, Set(row.keys) == ["label", "low", "high", "condition"],
                          row["label"]?.string?.isEmpty == false, let condition = row["condition"], conditions.contains(condition),
                          let low = row["low"]?.number, let high = row["high"]?.number, low.isFinite, high.isFinite, low <= high
                    else { throw RendererError("Invalid daily forecast") }
                }
            }
        }
        if type == "Map" { try MapData.validate(props) }
        if ExtendedInput.types.contains(type) { try ExtendedInput.validate(type: type, props: props, bindings: bindings) }
        if type == "Icon", let size = props["size"]?.number {
            guard size >= 12, size <= 64 else { throw RendererError("Icon size must be 12...64") }
        }
        if InformationData.types.contains(type) { try InformationData.validate(type: type, props: props) }
        if AdvancedChartData.types.contains(type) { try AdvancedChartData.validate(type: type, props: props) }
        if ["Progress", "Rating", "Spacer", "Heading"].contains(type) {
            let key = type == "Spacer" ? "size" : type == "Heading" ? "level" : "value"
            if let number = props[key]?.number {
                let limit: Double = type == "Rating" ? 5 : type == "Heading" ? 6 : type == "Spacer" ? 200 : 100
                guard number >= (type == "Heading" ? 1 : 0), number <= limit else { throw RendererError("Invalid \(type) \(key)") }
            }
        }
        if ["TagList", "List"].contains(type) {
            let key = type == "TagList" ? "tags" : "items"
            guard let items = props[key]?.array, items.count <= 100, items.allSatisfy({ $0.string != nil }) else { throw RendererError("\(type) requires up to 100 strings") }
        }
        if type == "Rating", let count = props["count"]?.number { guard count >= 0, count <= 1e9, count.rounded() == count else { throw RendererError("Invalid rating count") } }
        if type == "Timeline" {
            guard let steps = props["steps"]?.array, steps.count <= 40, steps.allSatisfy({ $0.object?["title"]?.string != nil && Set($0.object!.keys).isSubset(of: ["title", "description", "status", "image"]) }) else { throw RendererError("Invalid timeline steps") }
            for step in steps {
                if let image = step.object?["image"] { try InformationData.validateImage(image) }
                if let status = step.object?["status"] { guard ["completed", "current", "active", "pending"].contains(status.text) else { throw RendererError("Invalid timeline status") } }
                if let description = step.object?["description"] { guard description.string != nil else { throw RendererError("Invalid timeline description") } }
            }
        }
        if ["TextField", "TextArea", "Select", "Slider", "Switch", "Radio", "Checkbox"].contains(type), bindings["value"] == nil {
            throw RendererError("Input value must use $bindState")
        }
        if ["TextField", "TextArea"].contains(type), let limit = props["maxLength"]?.number {
            guard limit >= 1, limit <= 100_000, limit.rounded() == limit else { throw RendererError("Invalid input maxLength") }
        }
        if type == "TextArea", let rows = props["rows"]?.number {
            guard rows >= 3, rows <= 12, rows.rounded() == rows else { throw RendererError("TextArea rows must be 3...12") }
        }
        if type == "Steps" {
            guard let pointer = bindings["value"], try JSONValue.tokens(pointer).first == "ui",
                  let index = props["value"]?.number, index >= 0, index.rounded() == index,
                  let labels = props["labels"]?.array, !labels.isEmpty, labels.count <= 12,
                  labels.allSatisfy({ $0.string?.isEmpty == false }), index < Double(labels.count) else {
                throw RendererError("Steps requires a /ui index and 1...12 nonempty labels")
            }
        }
        if type == "Select" {
            guard let options = props["options"]?.array, !options.isEmpty, options.count <= 100 else { throw RendererError("Invalid Select options") }
            let keys = try options.map { option -> String in
                guard let object = option.object, let label = object["label"]?.string,
                      let value = object["value"]?.string, !label.isEmpty else { throw RendererError("Invalid Select option") }
                return value
            }
            guard Set(keys).count == keys.count else { throw RendererError("Duplicate Select value") }
        }
        if type == "Slider" {
            let range = try SliderRange(props: props)
            guard let value = props["value"]?.number, range.contains(value) else {
                throw RendererError("Slider value must lie on a step within min...max")
            }
        }
        if type == "Radio" {
            guard let options = props["options"]?.array, !options.isEmpty, options.count <= 20 else {
                throw RendererError("Radio requires 1...20 options")
            }
            let values = try options.map { option -> String in
                guard let object = option.object,
                      Set(object.keys).isSubset(of: ["label", "value", "description", "disabled"]),
                      object["label"]?.string?.isEmpty == false,
                      let value = object["value"]?.string, !value.isEmpty,
                      object["description"] == nil || object["description"]?.string != nil,
                      object["disabled"] == nil || object["disabled"]?.bool != nil else {
                    throw RendererError("Invalid Radio option")
                }
                return value
            }
            guard Set(values).count == values.count else { throw RendererError("Duplicate Radio value") }
        }
        if type == "Flowchart" {
            _ = try FlowchartGraph(nodes: props["nodes"] ?? .null, edges: props["edges"] ?? .null)
        }
        if type == "Chart" {
            if let size = props["windowSize"]?.number { guard size.rounded() == size, (2...200).contains(size) else { throw RendererError("Chart windowSize must be 2...200") } }
            if props["mode"] == .string("diverging") { guard ["line", "area"].contains(props["kind"]?.string ?? "line"), props["stacked"] != .bool(true) else { throw RendererError("Diverging mode requires an unstacked line or area chart") } }
            if let baseline = props["baseline"]?.number { guard baseline.isFinite else { throw RendererError("Chart baseline must be finite") } }

            if let ranges = props["ranges"]?.array {
                guard !ranges.isEmpty, ranges.count <= 12 else { throw RendererError("Chart supports 1...12 range options") }
                var ids = Set<String>()
                for range in ranges {
                    guard let row = range.object, Set(row.keys) == ["id", "label", "count"], let id = row["id"]?.string, !id.isEmpty, ids.insert(id).inserted,
                          row["label"]?.string?.isEmpty == false, let count = row["count"]?.number, count.rounded() == count, (1...500).contains(count) else { throw RendererError("Invalid chart range") }
                }
                if let selected = props["defaultRangeId"]?.string { guard ids.contains(selected) else { throw RendererError("Unknown default chart range") } }
            } else if props["defaultRangeId"] != nil { throw RendererError("Default chart range requires ranges") }
            if props["layout"] == .string("horizontal"), props["kind"] != .string("bar") { throw RendererError("Horizontal layout requires bar chart") }
            if props["stacked"] == .bool(true), !["bar", "area"].contains(props["kind"]?.text ?? "line") { throw RendererError("Only bar/area charts stack") }

            guard let points = props["points"]?.array, points.count <= 200 else { throw RendererError("Chart point limit") }
            let circular = ["pie", "donut"].contains(props["kind"]?.string ?? "line")
            var identities: Set<String> = []
            var total = 0.0
            for point in points {
                guard let object = point.object, Set(object.keys).isSubset(of: ["x", "y", "series"]),
                      let x = object["x"]?.string, !x.isEmpty,
                      let y = object["y"]?.number, y.isFinite,
                      object["series"] == nil || object["series"]?.string?.isEmpty == false else {
                    throw RendererError("Chart requires nonempty string x, finite numeric y and optional nonempty series")
                }
                let series = object["series"]?.string ?? "数值"
                let identity = "\(series.utf8.count):\(series)\(x)"
                guard identities.insert(identity).inserted else { throw RendererError("Duplicate Chart category within series") }
                if circular {
                    guard y >= 0, object["series"] == nil else { throw RendererError("Pie/donut requires nonnegative y and no series") }
                }
                total += abs(y)
                guard total.isFinite else { throw RendererError("Chart numeric range exceeded") }
            }
        }
        if type == "Table" {
            guard let columns = props["columns"]?.array, !columns.isEmpty, columns.count <= 12,
                  let rows = props["rows"]?.array, rows.count <= 200 else { throw RendererError("Table dimensions exceed profile") }
            var keys = Set<String>()
            for column in columns {
                guard let object = column.object, Set(object.keys).isSubset(of: ["key", "label", "format"]),
                      let key = object["key"]?.string, !key.isEmpty, keys.insert(key).inserted, object["label"]?.string?.isEmpty == false else { throw RendererError("Invalid/duplicate Table column") }
                if let format = object["format"] { try ValueFormat.validate(format) }
            }
            guard rows.allSatisfy({ row in
                guard let object = row.object else { return false }
                return object.values.allSatisfy { value in value.isScalar && (value.number == nil || value.number?.isFinite == true) }
            }) else { throw RendererError("Table rows must contain scalar cells") }

        }
    }
}

public struct ActionEnvelope: Codable, Equatable, Sendable {
    public let requestId: String
    public let context: RenderContext
    public let componentId: String
    public let instanceId: String
    public let event: String
    public let action: String
    public let params: [String: JSONValue]

    public init(requestId: String = UUID().uuidString, context: RenderContext, node: ResolvedNode,
                event: String, action: String, params: [String: JSONValue]) {
        self.requestId = requestId; self.context = context; self.componentId = node.elementKey
        self.instanceId = node.id; self.event = event; self.action = action; self.params = params
    }
}

public struct ActionOutcome: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case accepted, completed, rejected, unknown }
    public let status: Status
    public let message: String
    public init(status: Status, message: String) { self.status = status; self.message = message }
}
