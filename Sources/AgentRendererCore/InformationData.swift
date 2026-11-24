import Foundation

public enum InformationData {
    public static let types: Set<String> = ["MetricGrid", "KPIGrid", "ComparisonList", "MeterList", "Image", "RecordCard"]
    public static func validateImage(_ value: JSONValue) throws {
        guard let row = value.object, Set(row.keys) == ["src", "alt"], let raw = row["src"]?.string, let url = URL(string: raw), url.scheme == "https", url.host != nil, row["alt"]?.string != nil else { throw RendererError("Image requires HTTPS src and alt") }
    }
    public static func validate(type: String, props: [String: JSONValue]) throws {
        let key = type == "Image" ? "images" : type == "RecordCard" ? "fields" : ["MetricGrid", "KPIGrid"].contains(type) ? "metrics" : "items"
        guard let rows = props[key]?.array ?? (type == "RecordCard" ? [] : nil), rows.count <= (type == "Image" ? 20 : 50) else { throw RendererError("Invalid \(type) rows") }
        if type == "RecordCard" {
            if let image = props["image"] { try validateImage(image) }
            if let status = props["status"] { guard let object = status.object, Set(object.keys).isSubset(of: ["label", "tone"]), object["label"]?.string?.isEmpty == false, object["tone"] == nil || ["accent", "neutral", "success", "warning", "danger"].contains(object["tone"]!.text) else { throw RendererError("Invalid record status") } }
        }
        for row in rows {
            guard let object = row.object else { throw RendererError("Expected \(type) object") }
            if type == "Image" {
                guard let src = object["src"]?.string, let url = URL(string: src), url.scheme == "https", url.host != nil,
                      object["alt"]?.string != nil, Set(object.keys).isSubset(of: ["src", "alt", "caption", "aspectRatio"]) else { throw RendererError("Images require HTTPS src and alt") }
                if let ratio = object["aspectRatio"] { guard ["square", "portrait", "wide", "landscape"].contains(ratio.text) else { throw RendererError("Invalid image aspect ratio") } }
                if let caption = object["caption"] { guard caption.string != nil else { throw RendererError("Invalid image caption") } }
                continue
            }
            let allowed: Set<String>
            switch type {
            case "MeterList": allowed = ["label", "value", "min", "max", "description", "tone", "format"]
            case "ComparisonList": allowed = ["label", "value", "change", "note", "format"]
            case "KPIGrid": allowed = ["label", "value", "change", "trend", "format"]
            case "MetricGrid": allowed = ["label", "value", "change", "format"]
            default: allowed = ["label", "value", "format"]
            }
            guard Set(object.keys).isSubset(of: allowed), object["label"]?.string?.isEmpty == false,
                  let value = object["value"], value.string != nil || value.number?.isFinite == true else { throw RendererError("Invalid \(type) row") }
            if let format = object["format"] { try ValueFormat.validate(format) }
            for key in ["change", "min", "max"] where object[key] != nil {
                guard object[key]?.number?.isFinite == true else { throw RendererError("Invalid numeric metadata") }
            }
            for key in ["note", "description", "tone"] where object[key] != nil {
                guard object[key]?.string != nil else { throw RendererError("Invalid descriptive metadata") }
            }
            if type == "KPIGrid" {
                guard let trend = object["trend"]?.array, trend.count <= 200, trend.allSatisfy({ $0.number?.isFinite == true }) else { throw RendererError("KPI needs a numeric trend, which can be empty") }
            }
            if type == "MeterList", let tone = object["tone"] { guard ["accent", "neutral", "success", "warning", "danger"].contains(tone.text) else { throw RendererError("Invalid meter tone") } }
            if type == "MeterList" {
                let lower = object["min"]?.number ?? 0, upper = object["max"]?.number ?? 100
                guard lower < upper, (upper - lower).isFinite, let value = value.number, (lower...upper).contains(value) else { throw RendererError("Invalid meter range") }
            }
        }
    }
}
