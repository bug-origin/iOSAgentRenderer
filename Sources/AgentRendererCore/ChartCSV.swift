import Foundation

public enum ChartCSV {
    public static func encode(_ rows: [[String: JSONValue]]) -> String {
        let keys = Set(rows.flatMap(\.keys)).sorted()
        func cell(_ value: String) -> String {
            // Prevent spreadsheet formula execution when opening agent-produced text.
            let text = ["=", "+", "-", "@", "\t", "\r"].contains(where: value.hasPrefix) ? "'" + value : value
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return ([keys.map(cell).joined(separator: ",")] + rows.map { row in
            keys.map { key in
                if let number = row[key]?.number { return String(number) }
                return cell(row[key]?.text ?? "")
            }.joined(separator: ",")
        }).joined(separator: "\r\n")
    }
}
