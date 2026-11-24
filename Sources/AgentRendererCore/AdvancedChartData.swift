import Foundation

/// Specialized charts use explicit shapes rather than interpreting arbitrary nested payloads.
public enum AdvancedChartData {
    public static let types: Set<String> = ["GaugeChart", "RadarChart", "FunnelChart", "Heatmap", "CandlestickChart", "NumericScatterChart", "RadialChart"]
    public static func validate(type: String, props: [String: JSONValue]) throws {
        if type == "GaugeChart" {
            if let notches = props["notches"]?.number { guard notches.rounded() == notches, (2...100).contains(notches) else { throw RendererError("Gauge notches must be 2...100") } }
            let lower = props["min"]?.number ?? 0, upper = props["max"]?.number ?? 100
            guard let value = props["value"]?.number, lower.isFinite, upper.isFinite, lower < upper,
                  (upper - lower).isFinite, value >= lower, value <= upper else { throw RendererError("Invalid gauge bounds/value") }
            return
        }
        guard let data = props["data"]?.array, data.count <= 500 else { throw RendererError("Chart requires at most 500 data rows") }
        if type == "RadialChart", data.count > 6 { throw RendererError("RadialChart supports up to 6 rings") }
        if type == "FunnelChart", data.count > 40 { throw RendererError("FunnelChart supports up to 40 stages") }
        var identities = Set<String>()
        for row in data {
            guard let object = row.object else { throw RendererError("Chart row must be an object") }
            let required: Set<String>
            switch type {
            case "CandlestickChart": required = ["x", "open", "high", "low", "close"]
            case "NumericScatterChart": required = ["x", "y"]
            case "Heatmap": required = ["x", "y", "value"]
            default: required = ["label", "value"]
            }
            let allowed = required.union(type == "NumericScatterChart" ? ["series", "label", "size"] : type == "RadarChart" ? ["series"] : [])
            if let size = object["size"] { guard let number = size.number, number.isFinite, number > 0 else { throw RendererError("Bubble size must be positive and finite") } }
            if let label = object["label"], type == "NumericScatterChart" { guard label.string?.isEmpty == false else { throw RendererError("Scatter label must be nonempty") } }
            guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: allowed) else { throw RendererError("Unknown/missing chart row field") }
            for key in required {
                if key == "label" || (key == "x" && type != "NumericScatterChart") || (key == "y" && type == "Heatmap") {
                    guard object[key]?.string?.isEmpty == false else { throw RendererError("Empty chart category") }
                } else {
                    guard object[key]?.number?.isFinite == true else { throw RendererError("Chart value must be finite") }
                }
            }
            if let series = object["series"] { guard series.string?.isEmpty == false else { throw RendererError("Invalid chart series") } }
            if ["FunnelChart", "RadarChart", "RadialChart"].contains(type) {
                guard (object["value"]?.number ?? -1) >= 0 else { throw RendererError("Chart values must be nonnegative") }
            }
            if type == "CandlestickChart" {
                let low = object["low"]!.number!, high = object["high"]!.number!
                guard low <= high, (low...high).contains(object["open"]!.number!), (low...high).contains(object["close"]!.number!) else { throw RendererError("OHLC prices exceed low/high") }
            }
            let id: String
            if type == "NumericScatterChart" { id = "\(object["series"]?.text ?? "")|\(object["x"]!.number!)|\(object["y"]!.number!)" }
            else if type == "Heatmap" { id = "\(object["x"]!.text.utf8.count):\(object["x"]!.text)\(object["y"]!.text)" }
            else { id = "\(object["series"]?.text.utf8.count ?? 0):\(object["series"]?.text ?? "")\(object["label"]?.text ?? object["x"]!.text)" }
            guard identities.insert(id).inserted else { throw RendererError("Duplicate chart category/point") }
        }
        if type == "RadarChart", !data.isEmpty {
            let grouped = Dictionary(grouping: data, by: { $0.object?["series"]?.text ?? "" })
            guard grouped.count <= 6 else { throw RendererError("Radar supports up to 6 series") }
            let axes = grouped.values.map { Set($0.compactMap { $0.object?["label"]?.string }) }
            guard let first = axes.first, first.count >= 3, first.count <= 12, axes.allSatisfy({ $0 == first }) else { throw RendererError("Radar needs 3...12 matching axes per series") }
        }
        if ["RadialChart", "RadarChart"].contains(type), let max = props["max"]?.number {
            guard max > 0, data.allSatisfy({ ($0.object?["value"]?.number ?? 0) <= max }) else { throw RendererError("Invalid radial/radar max") }
        }
    }
}
