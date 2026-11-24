import SwiftUI
import AgentRendererCore

@MainActor
struct HierarchyChartComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: String?
    @State private var entranceRevealed: Int
    private var revealed: Int { reduceMotion ? Int.max : entranceRevealed }
    @State private var showsTable = false
    init(context: ComponentRenderContext) {
        self.context = context
        let entered = context.session.presentationValue(for: context.node.id, key: "motion.chart") != nil
        _entranceRevealed = State(initialValue: entered ? Int.max : 0)
    }
    private var p: [String: JSONValue] { context.node.props }
    private var exportRows: [[String: JSONValue]] {
        if context.node.type == "SunburstChart", let chart = try? SunburstData(data: p["data"] ?? .null) {
            return chart.sectors.map { ["id": .string($0.id), "label": .string($0.label), "value": .number($0.value), "depth": .number(Double($0.depth))] }
        }
        return (p["links"]?.array ?? []).compactMap(\.object)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChartPresentationHeader(title: p["title"]?.text ?? context.node.type, description: context.node.props["description"]?.string, rows: exportRows, showsTable: $showsTable)
            if showsTable { ChartDataTable(rows: exportRows) }
            else if context.node.type == "SunburstChart", let chart = try? SunburstData(data: p["data"] ?? .null) { sunburst(chart) }
            else if let chart = try? SankeyData(props: p) { sankey(chart) }
        }.overlayPreferenceValue(ChartSelectedAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let anchor, let detail = selectionDetails {
                    let rect = geometry[anchor]
                    ChartFloatingTooltip(anchor: CGPoint(x: rect.midX, y: rect.midY)) {
                        ChartTooltip(title: detail.0, entries: [("数值", ValueFormat.text(.number(detail.1), format: p["format"]), accent)])
                    }
                }
            }.allowsHitTesting(false)
        }
            .onChange(of: p) { _, _ in selected = nil }
            .animation(reduceMotion ? nil : RenderMotion.feedback, value: selected)
    }
    private var selectionDetails: (String, Double)? {
        guard let selected else { return nil }
        if context.node.type == "SunburstChart", let chart = try? SunburstData(data: p["data"] ?? .null), let sector = chart.sectors.first(where: { $0.id == selected }) {
            return (sector.label, sector.value)
        }
        if let chart = try? SankeyData(props: p), let node = chart.nodes.first(where: { $0.id == selected }) { return (node.label, node.weight) }
        return nil
    }
    private func color(_ index: Int) -> Color { RenderChartPalette.color(index, accent) }
    private func sunburst(_ data: SunburstData) -> some View {
        VStack(spacing: 16) {
            if data.sectors.isEmpty { Text("暂无图表数据").font(.subheadline).foregroundStyle(RenderTheme.muted).frame(height: 220) }
            else {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    ZStack {
                        ForEach(Array(data.sectors.enumerated()), id: \.element.id) { index, sector in
                            let step = 0.75 / Double(data.depth)
                            SunburstSector(start: sector.start, end: sector.end, inner: 0.2 + Double(sector.depth) * step, outer: 0.2 + Double(sector.depth + 1) * step, progress: index < revealed ? 1 : 0)
                                .fill(RenderChartPalette.gradient(color(index))).shadow(color: color(index).opacity(0.18), radius: 2, x: 0, y: 2).opacity(selected == nil || selected == sector.id ? 1 : 0.35)
                                .overlay { SunburstSector(start: sector.start, end: sector.end, inner: 0.2 + Double(sector.depth) * step, outer: 0.2 + Double(sector.depth + 1) * step, progress: index < revealed ? 1 : 0).stroke(RenderTheme.surface, lineWidth: 2) }
                                .opacity(index < revealed ? 1 : 0)
                                .onTapGesture { selected = selected == sector.id ? nil : sector.id }
                                .accessibilityLabel("\(sector.label)：\(ValueFormat.text(.number(sector.value), format: p["format"]))").accessibilityAddTraits(.isButton)
                            let angle = (sector.start + sector.end) / 2 * 2 * .pi - .pi / 2
                            let radius = size / 2 * (0.2 + (Double(sector.depth) + 0.5) * step)
                            Color.clear.frame(width: 1, height: 1)
                                .chartTooltipAnchor(selected: selected == sector.id)
                                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                                .allowsHitTesting(false)
                        }
                    }.frame(width: size, height: size).frame(maxWidth: .infinity)
                }.frame(height: 250).chartPlotBackground().chartSelectionFocus(selected != nil) { selected = nil }
                    .modifier(ChartEntrance(count: data.sectors.count, revealed: $entranceRevealed, session: context.session, instanceId: context.node.id))
                if let sector = data.sectors.first(where: { $0.id == selected }) { Text("\(sector.label) · \(ValueFormat.text(.number(sector.value), format: p["format"]))").font(.subheadline.weight(.medium)).contentTransition(.numericText()) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(Array(data.sectors.enumerated()).filter { $0.element.depth == 0 }, id: \.element.id) { index, sector in
                        Button { selected = selected == sector.id ? nil : sector.id } label: {
                            HStack(spacing: 6) { Circle().fill(color(index)).frame(width: 7, height: 7); Text(sector.label).font(.caption); Text(ValueFormat.text(.number(sector.value), format: p["format"])).font(.caption.monospacedDigit()).foregroundStyle(RenderTheme.muted) }
                        }.buttonStyle(RenderPlainButtonStyle())
                    }
                }
            }
        }
    }
    private func sankey(_ chart: SankeyData) -> some View {
        let layers = (chart.nodes.map(\.layer).max() ?? 0) + 1
        let rowCount = Dictionary(grouping: chart.nodes, by: \.layer).values.map(\.count).max() ?? 0
        let height = CGFloat(max(220, rowCount * 38 + 40))
        return VStack(alignment: .leading, spacing: 12) {
            if chart.nodes.isEmpty { Text("暂无图表数据").font(.subheadline).foregroundStyle(RenderTheme.muted).frame(height: 220) }
            else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        let width = max(geometry.size.width, CGFloat(layers * 110))
                        let layout = SankeyLayout(chart: chart, width: width, height: height)
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(chart.links.enumerated()), id: \.offset) { index, link in
                                SankeyRibbon(start: layout.starts[index], end: layout.ends[index], thickness: max(0.5, CGFloat(link.value) * layout.scale))
                                    .fill(LinearGradient(colors: [color(link.source), color(link.target)], startPoint: .leading, endPoint: .trailing)).opacity(selected == nil || selected == chart.nodes[link.source].id || selected == chart.nodes[link.target].id ? 0.32 : 0.06)
                                    .opacity(index < revealed ? 1 : 0)
                                    .accessibilityLabel("\(chart.nodes[link.source].label) → \(chart.nodes[link.target].label)：\(ValueFormat.text(.number(link.value), format: p["format"]))")
                            }
                            ForEach(Array(chart.nodes.enumerated()), id: \.element.id) { index, node in
                                let rect = layout.rects[index]
                                Button { selected = selected == node.id ? nil : node.id } label: {
                                    RoundedRectangle(cornerRadius: 3).fill(RenderChartPalette.gradient(color(index))).frame(width: rect.width, height: max(4, rect.height))
                                }.buttonStyle(RenderPlainButtonStyle()).shadow(color: color(index).opacity(0.18), radius: 2, x: 0, y: 2)
                                    .chartTooltipAnchor(selected: selected == node.id)
                                    .opacity(node.layer < revealed ? 1 : 0).position(x: rect.midX, y: rect.midY)
                                    .accessibilityLabel("\(node.label)：\(ValueFormat.text(.number(node.weight), format: p["format"]))")
                                    .accessibilityAddTraits(selected == node.id ? .isSelected : [])
                                Text(node.label).font(.system(size: 10, weight: .medium)).foregroundStyle(RenderTheme.foreground).lineLimit(2)
                                    .frame(width: 90, alignment: node.layer == layers - 1 ? .trailing : .leading)
                                    .position(x: node.layer == layers - 1 ? rect.minX - 48 : rect.maxX + 48, y: rect.midY)
                                    .opacity(node.layer < revealed ? 1 : 0)
                                    .allowsHitTesting(false)
                            }
                        }.frame(width: width, height: height)
                    }.scrollIndicators(.hidden)
                }.frame(height: height).chartPlotBackground().chartSelectionFocus(selected != nil) { selected = nil }
                    .modifier(ChartEntrance(count: max(layers, chart.links.count), revealed: $entranceRevealed, session: context.session, instanceId: context.node.id))
                if let selected, let node = chart.nodes.first(where: { $0.id == selected }) {
                    Text("\(node.label) · \(ValueFormat.text(.number(node.weight), format: p["format"]))").font(.subheadline.weight(.medium)).transition(.opacity)
                }
            }
        }
    }
}

private struct SunburstSector: Shape {
    let start: Double
    let end: Double
    let inner: Double
    let outer: Double
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2
        let startAngle = Angle.degrees(start * 360 - 90), endAngle = Angle.degrees((start + (end - start) * progress) * 360 - 90)
        return Path { path in
            path.addArc(center: center, radius: radius * outer, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            path.addArc(center: center, radius: radius * inner, startAngle: endAngle, endAngle: startAngle, clockwise: true)
            path.closeSubpath()
        }
    }
}

private struct SankeyLayout {
    let rects: [CGRect]
    let starts: [CGPoint]
    let ends: [CGPoint]
    let scale: CGFloat
    init(chart: SankeyData, width: CGFloat, height: CGFloat) {
        let grouped = Dictionary(grouping: chart.nodes.indices, by: { chart.nodes[$0].layer })
        let layers = (chart.nodes.map(\.layer).max() ?? 0) + 1
        let floorWeight = max((chart.nodes.map(\.weight).max() ?? 0) * 0.001, 1e-9)
        let scales: [Double] = grouped.values.map { group in
            let total: Double = group.reduce(0.0) { $0 + max(chart.nodes[$1].weight, floorWeight) }
            return Double(height - CGFloat(max(0, group.count - 1)) * 14) / total
        }
        let scale: Double = scales.min() ?? 1
        self.scale = CGFloat(scale)
        var rects = Array(repeating: CGRect.zero, count: chart.nodes.count)
        for layer in grouped.keys.sorted() {
            let group = grouped[layer]!
            let sum: Double = group.reduce(0.0) { $0 + max(chart.nodes[$1].weight, floorWeight) }
            let total: CGFloat = CGFloat(sum * scale) + CGFloat(max(0, group.count - 1)) * 14
            var y = (height - total) / 2
            for index in group {
                let nodeHeight = CGFloat(max(chart.nodes[index].weight, floorWeight) * scale)
                let x = layers == 1 ? width / 2 - 6 : CGFloat(layer) / CGFloat(layers - 1) * (width - 24) + 6
                rects[index] = CGRect(x: x, y: y, width: 12, height: nodeHeight); y += nodeHeight + 14
            }
        }
        var outOffsets = Array(repeating: 0.0, count: chart.nodes.count), inOffsets = outOffsets
        var starts: [CGPoint] = [], ends: [CGPoint] = []
        for link in chart.links {
            starts.append(CGPoint(x: rects[link.source].maxX, y: rects[link.source].minY + CGFloat(outOffsets[link.source])))
            ends.append(CGPoint(x: rects[link.target].minX, y: rects[link.target].minY + CGFloat(inOffsets[link.target])))
            outOffsets[link.source] += link.value * scale; inOffsets[link.target] += link.value * scale
        }
        self.rects = rects; self.starts = starts; self.ends = ends
    }
}
private struct SankeyRibbon: Shape {
    let start: CGPoint
    let end: CGPoint
    let thickness: CGFloat
    func path(in rect: CGRect) -> Path {
        let middle = (start.x + end.x) / 2
        return Path { path in
            path.move(to: start)
            path.addCurve(to: end, control1: CGPoint(x: middle, y: start.y), control2: CGPoint(x: middle, y: end.y))
            path.addLine(to: CGPoint(x: end.x, y: end.y + thickness))
            path.addCurve(to: CGPoint(x: start.x, y: start.y + thickness), control1: CGPoint(x: middle, y: end.y + thickness), control2: CGPoint(x: middle, y: start.y + thickness))
            path.closeSubpath()
        }
    }
}
