import Foundation

public enum MapData {
    public static func validate(_ props: [String: JSONValue]) throws {
        guard let locations = props["locations"]?.array, locations.count <= 100 else { throw RendererError("Map requires at most 100 locations") }
        var ids = Set<String>()
        for location in locations {
            guard let row = location.object, Set(row.keys).isSubset(of: ["id", "title", "latitude", "longitude", "address", "description", "category", "rating", "reviewCount", "images", "website"]),
                  let id = row["id"]?.string, !id.isEmpty, ids.insert(id).inserted, row["title"]?.string?.isEmpty == false,
                  validCoordinate(row), row["address"] == nil || row["address"]?.string != nil,
                  row["description"] == nil || row["description"]?.string != nil else { throw RendererError("Invalid map location") }
            for key in ["category", "website"] where row[key] != nil {
                guard row[key]?.string?.isEmpty == false else { throw RendererError("Invalid map location text") }
            }
            if let website = row["website"]?.string { guard validURL(website) else { throw RendererError("Map website requires HTTPS") } }
            if let rating = row["rating"] { guard let value = rating.number, (0...5).contains(value) else { throw RendererError("Map rating must be 0...5") } }
            if let count = row["reviewCount"] { guard let value = count.number, value >= 0, value <= 1e9, value.rounded() == value else { throw RendererError("Invalid review count") } }
            if let images = row["images"] {
                guard let items = images.array, items.count <= 10 else { throw RendererError("Map supports up to 10 images per location") }
                for image in items { guard let item = image.object, Set(item.keys).isSubset(of: ["src", "alt"]), let src = item["src"]?.string, validURL(src), item["alt"]?.string?.isEmpty == false else { throw RendererError("Map images require HTTPS src and alt") } }
            }
        }
        if let initial = props["initialLocationId"]?.string { guard ids.contains(initial) else { throw RendererError("Unknown initial map location") } }
        for key in ["routes", "arcs"] {
            if let value = props[key] {
                guard let lines = value.array, lines.count <= 40 else { throw RendererError("Map supports up to 40 paths") }
                var pathIDs = Set<String>()
                for line in lines {
                    if let row = line.object {
                        guard Set(row.keys).isSubset(of: ["id", "label", "stopIds", "fromId", "toId", "mode"]), let id = row["id"]?.string, !id.isEmpty, pathIDs.insert(id).inserted,
                              row["label"] == nil || row["label"]?.string?.isEmpty == false else { throw RendererError("Invalid map path") }
                        if let mode = row["mode"] { guard ["walking", "driving", "cycling", "transit"].contains(mode.text) else { throw RendererError("Invalid route mode") } }
                        let stops = key == "arcs" ? [row["fromId"] ?? .null, row["toId"] ?? .null] : row["stopIds"]?.array ?? []
                        guard (2...100).contains(stops.count), stops.allSatisfy({ $0.string.map(ids.contains) == true }) else { throw RendererError("Map path references unknown location") }
                    } else {
                        guard let coordinates = line.array, (2...200).contains(coordinates.count), coordinates.allSatisfy({ $0.object.map(validCoordinate) == true }) else { throw RendererError("Invalid map path coordinates") }
                    }
                }
            }
        }
    }
    public static func coordinates(_ path: JSONValue, locations: [[String: JSONValue]], arc: Bool = false) -> [[String: JSONValue]] {
        if let values = path.array { return values.compactMap(\.object) }
        guard let row = path.object else { return [] }
        let stops = arc ? [row["fromId"] ?? .null, row["toId"] ?? .null] : row["stopIds"]?.array ?? []
        return stops.compactMap { stop in locations.first { $0["id"] == stop } }
    }
    private static func validURL(_ text: String) -> Bool { guard let url = URL(string: text) else { return false }; return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil }
    private static func validCoordinate(_ row: [String: JSONValue]) -> Bool {
        guard let lat = row["latitude"]?.number, let lon = row["longitude"]?.number else { return false }
        return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
    }
}
