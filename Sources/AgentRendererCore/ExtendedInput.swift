import Foundation

public enum ExtendedInput {
    public static let types: Set<String> = ["NumberField", "DatePicker", "TimeField", "DateRangePicker", "CheckboxGroup", "ComboBox", "ToggleGroup"]
    public static func date(_ value: String, time: Bool = false) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = time ? "HH:mm" : "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    public static func string(_ date: Date, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = time ? "HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    /// Dates in the protocol are wall-clock values without a time zone.
    public static func localDefault(_ now: Date = Date(), time: Bool = false, timeZone: TimeZone = .current) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = time ? "HH:mm" : "yyyy-MM-dd"
        return date(formatter.string(from: now), time: time)!
    }
    public static func validate(type: String, props: [String: JSONValue], bindings: [String: String]) throws {
        guard bindings["value"] != nil else { throw RendererError("Input requires value $bindState") }
        guard let value = props["value"] else { throw RendererError("Missing input value") }
        if type == "NumberField" {
            guard let number = value.number, number.isFinite else { throw RendererError("NumberField value must be finite") }
            let min = props["min"]?.number ?? -1e12, max = props["max"]?.number ?? 1e12, step = props["step"]?.number ?? 1
            guard min < max, step > 0, step <= max - min, step.isFinite else { throw RendererError("Invalid NumberField bounds/step") }
            return
        }
        if ["DatePicker", "TimeField"].contains(type) {
            guard let string = value.string, string.isEmpty || date(string, time: type == "TimeField") != nil else { throw RendererError("Date/Time requires empty or ISO date/HH:mm") }
            return
        }
        if type == "DateRangePicker" {
            guard let values = value.array, values.count == 2, values.allSatisfy({ $0.string != nil && ($0.string!.isEmpty || date($0.string!) != nil) }) else { throw RendererError("Date range requires [start,end] ISO strings") }
            return
        }
        guard let options = props["options"]?.array, !options.isEmpty, options.count <= 100 else { throw RendererError("Input requires 1...100 options") }
        var ids = Set<String>()
        for option in options {
            guard let object = option.object, Set(object.keys).isSubset(of: ["label", "value", "disabled", "description"]),
                  object["label"]?.string?.isEmpty == false, let id = object["value"]?.string, !id.isEmpty,
                  ids.insert(id).inserted, object["disabled"] == nil || object["disabled"]?.bool != nil,
                  object["description"] == nil || object["description"]?.string != nil else { throw RendererError("Invalid option") }
        }
        guard let values = value.array, values.allSatisfy({ $0.string != nil }), Set(values.compactMap(\.string)).count == values.count else { throw RendererError("Selection value must be unique string array") }
        if type != "CheckboxGroup", props["multiple"] != .bool(true), values.count > 1 { throw RendererError("Single selection supports at most one value") }
    }
    public static func error(type: String, props: [String: JSONValue]) -> String? {
        let value = props["value"] ?? .null
        let required = props["required"] == .bool(true)
        if type == "NumberField", let number = value.number {
            if number < (props["min"]?.number ?? -1e12) || number > (props["max"]?.number ?? 1e12) { return "数值超出允许范围" }
        } else if type == "DateRangePicker", let values = value.array {
            if required && values.contains(.string("")) { return "请选择完整日期范围" }
            if let start = values.first?.string, let end = values.last?.string, !start.isEmpty, !end.isEmpty, start > end { return "结束日期不能早于开始日期" }
        } else if let values = value.array {
            if required && values.isEmpty { return "请至少选择一项" }
            let options = props["options"]?.array ?? []
            if !values.allSatisfy({ selected in options.contains { $0.object?["value"] == selected && $0.object?["disabled"] != .bool(true) } }) { return "请选择有效选项" }
        } else if required && value.text.isEmpty { return "请填写" + (props["label"]?.text ?? "此字段") }
        return nil
    }
}
