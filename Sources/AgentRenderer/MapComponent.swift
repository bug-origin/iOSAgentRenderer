import MapKit
import SwiftUI
import AgentRendererCore

@MainActor
struct MapComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: String?
    @State private var selectedRoute: Int?
    @State private var previewImage: String?
    init(context: ComponentRenderContext) {
        self.context = context
        let initial = context.node.props["initialLocationId"]?.string
        _selection = State(initialValue: initial)
        if let location = (context.node.props["locations"]?.array ?? []).compactMap(\.object).first(where: { $0["id"]?.string == initial }),
            let latitude = location["latitude"]?.number, let longitude = location["longitude"]?.number {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                latitudinalMeters: 6000, longitudinalMeters: 6000)))
        }
    }
    private var p: [String: JSONValue] { context.node.props }
    private var locations: [[String: JSONValue]] { (p["locations"]?.array ?? []).compactMap(\.object) }
    private var selected: [String: JSONValue]? { locations.first { $0["id"]?.string == selection } }
    private func coordinate(_ row: [String: JSONValue]) -> CLLocationCoordinate2D { .init(latitude: row["latitude"]!.number!, longitude: row["longitude"]!.number!) }
    private func paths(_ key: String) -> [[CLLocationCoordinate2D]] { (p[key]?.array ?? []).map { MapData.coordinates($0, locations: locations, arc: key == "arcs").map(coordinate) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = p["title"]?.string { Text(title).font(.system(size: 14, weight: .medium)) }
            if locations.isEmpty { Text("暂无地点").font(.subheadline).foregroundStyle(RenderTheme.muted).frame(maxWidth: .infinity, minHeight: 220) }
            else {
                Map(position: $position, selection: $selection) {
                    ForEach(Array(locations.enumerated()), id: \.offset) { _, location in
                        Marker(location["title"]!.text, coordinate: coordinate(location)).tint(accent).tag(location["id"]!.text)
                    }
                    ForEach(Array(paths("routes").enumerated()), id: \.offset) { index, coordinates in
                        MapPolyline(coordinates: coordinates).stroke(selectedRoute == nil || selectedRoute == index ? accent : accent.opacity(0.2), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    }
                    ForEach(Array(paths("arcs").enumerated()), id: \.offset) { _, coordinates in
                        MapPolyline(MKGeodesicPolyline(coordinates: coordinates, count: coordinates.count)).stroke(accent.opacity(0.65), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }.mapControls { MapCompass(); MapScaleView() }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel(p["title"]?.text ?? "地点地图")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(locations.enumerated()), id: \.offset) { _, location in
                            Button { select(location) } label: {
                                Text(location["title"]!.text).font(.caption.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10)
                                    .foregroundStyle(selection == location["id"]?.string ? accent : RenderTheme.foreground)
                                    .background(selection == location["id"]?.string ? accent.opacity(0.1) : RenderTheme.neutral, in: Capsule())
                            }.buttonStyle(RenderPlainButtonStyle()).accessibilityAddTraits(selection == location["id"]?.string ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                if let routes = p["routes"]?.array, routes.contains(where: { $0.object != nil }) {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(routes.enumerated()), id: \.offset) { index, route in
                                Button(route.object?["label"]?.text ?? "路线 \(index + 1)") {
                                    withAnimation(reduceMotion ? nil : RenderMotion.chart) {
                                        selectedRoute = selectedRoute == index ? nil : index
                                        let coordinates = paths("routes")[index]
                                        if let first = coordinates.first { position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 12000, longitudinalMeters: 12000)) }
                                    }
                                }.buttonStyle(RenderButtonStyle(primary: selectedRoute == index))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                if let selected {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selected["title"]!.text).font(.subheadline.weight(.semibold))
                        if let address = selected["address"]?.string { Text(address).font(.caption).foregroundStyle(RenderTheme.muted) }
                        if let category = selected["category"]?.string { Text(category).font(.caption).foregroundStyle(RenderTheme.muted) }
                        if let rating = selected["rating"]?.number {
                            HStack(spacing: 5) {
                                Image("lucide-star", bundle: .module).resizable().scaledToFit().frame(width: 12, height: 12).foregroundStyle(RenderTheme.warning)
                                Text(rating.formatted(.number.precision(.fractionLength(1))))
                                if let reviews = selected["reviewCount"]?.number { Text("(\(Int(reviews)))").foregroundStyle(RenderTheme.muted) }
                            }.font(.caption)
                        }
                        if let images = selected["images"]?.array {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                                        Button { previewImage = image.object?["src"]?.string } label: {
                                            remoteImage(image.object?["src"]?.string).frame(width: 150, height: 100).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                        }.buttonStyle(RenderPlainButtonStyle()).accessibilityLabel(image.object?["alt"]?.text ?? "图片")
                                            .renderFullScreen(isPresented: Binding(get: { previewImage != nil && previewImage == image.object?["src"]?.string }, set: { if !$0 { previewImage = nil } })) { RenderImageViewer(url: image.object?["src"]?.string.flatMap(URL.init(string:))) }
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                        if let website = selected["website"]?.string, let url = URL(string: website) { Link("访问网站", destination: url).buttonStyle(RenderButtonStyle(primary: false)) }
                        if let description = selected["description"]?.string { Text(description).font(.subheadline) }
                        Button("在地图中打开") {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(selected)))
                            item.name = selected["title"]!.text
                            item.openInMaps()
                        }.buttonStyle(RenderButtonStyle(primary: false))
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 16)).transition(.opacity)
                }
            }
        }
            .onChange(of: p["locations"]) { _, _ in selection = nil; selectedRoute = nil; position = .automatic }
            .animation(reduceMotion ? nil : RenderMotion.feedback, value: selection)
            .sensoryFeedback(.selection, trigger: selection)

    }
    private func remoteImage(_ source: String?) -> some View {
        AsyncImage(url: source.flatMap(URL.init(string:)), transaction: RenderMotion.imageLoad(reduceMotion)) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            case .failure: Text("图片暂不可用").font(.caption).foregroundStyle(RenderTheme.muted)
            default: ProgressView()
            }
        }.background(RenderTheme.neutral)
    }
    private func select(_ location: [String: JSONValue]) {
        context.session.setFocus(nil)
        withAnimation(reduceMotion ? nil : RenderMotion.chart) {
            selection = location["id"]!.text
            position = .region(MKCoordinateRegion(center: coordinate(location), latitudinalMeters: 6000, longitudinalMeters: 6000))
        }
    }
}
