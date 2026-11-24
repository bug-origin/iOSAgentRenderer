import Foundation

public enum ValueFormat {
    public static func validate(_ value: JSONValue) throws {
        guard let object = value.object, Set(object.keys).isSubset(of: ["style", "currency", "compact", "minimumFractionDigits", "maximumFractionDigits"]),
              object["style"] == nil || ["number", "currency", "percent"].contains(object["style"]?.text ?? ""),
              object["compact"] == nil || object["compact"]?.bool != nil else { throw RendererError("Invalid value format") }
        if object["style"] == .string("currency") || object["currency"] != nil {
            guard let code = object["currency"]?.string, code.count == 3, code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { throw RendererError("Currency format needs uppercase three-letter code") }
        }
        let minimum = object["minimumFractionDigits"]?.number ?? 0, maximum = object["maximumFractionDigits"]?.number ?? 2
        guard minimum.rounded() == minimum, maximum.rounded() == maximum, (0...8).contains(minimum), (0...8).contains(maximum), minimum <= maximum else { throw RendererError("Invalid fraction digit range") }
    }
    public static func text(_ value: JSONValue, format: JSONValue?) -> String {
        guard let number = value.number, let object = format?.object else { return value.text }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = object["style"] == .string("currency") ? .currency : object["style"] == .string("percent") ? .percent : .decimal
        if let code = object["currency"]?.string { formatter.currencyCode = code }
        formatter.minimumFractionDigits = Int(object["minimumFractionDigits"]?.number ?? 0)
        formatter.maximumFractionDigits = Int(object["maximumFractionDigits"]?.number ?? 2)
        var divisor = 1.0, suffix = ""
        if object["compact"] == .bool(true), formatter.numberStyle != .percent {
            for (bound, unit) in [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")] where abs(number) >= bound { divisor = bound; suffix = unit; break }
        }
        return (formatter.string(from: NSNumber(value: number / divisor)) ?? value.text) + suffix
    }
}
