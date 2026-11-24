import Charts
import SwiftUI
import AgentRendererCore

private struct ChartDatum: Identifiable, Equatable {
    let x: String
    let y: Double
    let series: String
    var id: String { "\(series.utf8.count):\(series)\(x)" }
}

/// Native Swift Charts. Selection stays local; JSON cannot execute chart gestures or scripts.
struct ChartComponent: View {
    let context: ComponentRenderContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderAccent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var entranceRevealed: Int
    private var revealed: Int { reduceMotion ? Int.max : entranceRevealed }
    @State private var showsTable = false
    @State private var hiddenSeries = Set<String>()
    @State private var rangeId: String?
    @State private var selectedX: String?
    @State private var selectedAngle: Double?

    private var kind: String { context.node.props["kind"]?.string ?? "line" }
    private var divergesAroundBaseline: Bool { context.node.props["mode"] == .string("diverging") }
    private var baseline: Double { context.node.props["baseline"]?.number ?? 0 }
    private var baselineGradient: LinearGradient {
        let split = min(1, max(0, (yDomain.upperBound - baseline) / (yDomain.upperBound - yDomain.lowerBound)))
        return LinearGradient(stops: [.init(color: RenderChartPalette.positive.opacity(0.55), location: 0), .init(color: RenderChartPalette.positive, location: split), .init(color: RenderChartPalette.negative, location: split), .init(color: RenderChartPalette.negative.opacity(0.55), location: 1)], startPoint: .top, endPoint: .bottom)
    }
    private var circular: Bool { kind == "pie" || kind == "donut" }
    private let allPoints: [ChartDatum]
    private let series: [String]

    init(context: ComponentRenderContext) {
        self.context = context
        let entered = context.session.presentationValue(for: context.node.id, key: "motion.chart") != nil
        _entranceRevealed = State(initialValue: entered ? Int.max : 0)
        let points = (context.node.props["points"]?.array ?? []).compactMap { point -> ChartDatum? in
            guard let x = point.object?["x"]?.string, let y = point.object?["y"]?.number else { return nil }
            return ChartDatum(x: x, y: y, series: point.object?["series"]?.string ?? "数值")
        }
        allPoints = points
        series = points.reduce(into: []) { if !$0.contains($1.series) { $0.append($1.series) } }
    }
    private var points: [ChartDatum] { rangedPoints.filter { !hiddenSeries.contains($0.series) } }
    private var exportRows: [[String: JSONValue]] { points.map { ["x": .string($0.x), "y": .number($0.y), "series": .string($0.series)] } }
    private var rangedPoints: [ChartDatum] {
        guard let count = ranges.first(where: { $0.object?["id"]?.string == rangeId })?.object?["count"]?.number ?? (context.node.props["mode"] == .string("live") ? context.node.props["windowSize"]?.number ?? 8 : nil) else { return allPoints }
        let categories = allPoints.reduce(into: [String]()) { if !$0.contains($1.x) { $0.append($1.x) } }
        let included = Set(categories.suffix(Int(count)))
        return allPoints.filter { included.contains($0.x) }
    }
    private var ranges: [JSONValue] { context.node.props["ranges"]?.array ?? [] }
    private var horizontal: Bool { kind == "bar" && context.node.props["layout"] == .string("horizontal") }
    private var stacked: Bool { context.node.props["stacked"] == .bool(true) }
    private var categories: [String] { points.reduce(into: []) { if !$0.contains($1.x) { $0.append($1.x) } } }
    private var palette: [Color] {
        RenderChartPalette.colors(accent)
    }
    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.y)
        if divergesAroundBaseline { values.append(baseline) }
        if stacked {
            values = []
            for group in Dictionary(grouping: points, by: \.x).values {
                var positive = 0.0, negative = 0.0
                for point in group { if point.y >= 0 { positive += point.y } else { negative += point.y } }
                values.append(positive); values.append(negative)
            }
        }
        let lower = min(0, values.min() ?? 0)
        let upper = max(0, values.max() ?? 0)
        let padding = max((upper - lower) * 0.1, 1)
        return (lower < 0 ? lower - padding : 0)...(upper + padding)
    }
    private var selected: [ChartDatum] {
        if circular, let angle = selectedAngle {
            var total = 0.0
            for point in points {
                total += point.y
                if angle < total { return [point] }
            }
            return []
        }
        return points.filter { $0.x == selectedX }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartPresentationHeader(title: context.node.props["title"]?.text ?? "图表", description: context.node.props["description"]?.string, rows: exportRows, showsTable: $showsTable)
            if !ranges.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(ranges.enumerated()), id: \.offset) { _, range in
                            Button { withAnimation(reduceMotion ? nil : RenderMotion.chart) { rangeId = range.object?["id"]?.string; clearSelection() } } label: {
                                Text(range.object?["label"]?.text ?? "").font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8)
                                    .foregroundStyle(rangeId == range.object?["id"]?.string ? accent : RenderTheme.muted)
                                    .background(rangeId == range.object?["id"]?.string ? accent.opacity(0.1) : RenderTheme.neutral, in: Capsule())
                            }.buttonStyle(RenderPlainButtonStyle()).accessibilityAddTraits(rangeId == range.object?["id"]?.string ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            if context.node.props["showSummary"] == .bool(true) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(series, id: \.self) { name in
                        if let latest = points.last(where: { $0.series == name }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name).font(.caption).foregroundStyle(RenderTheme.muted)
                                Text(ValueFormat.text(.number(latest.y), format: context.node.props["format"])).font(.system(size: 24, weight: .semibold)).contentTransition(.numericText())
                            }
                        }
                    }
                }
            }
            if showsTable { ChartDataTable(rows: exportRows) }
            else if points.isEmpty || (circular && !points.contains { $0.y > 0 }) {
                Text("暂无图表数据").font(.callout).foregroundStyle(RenderTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Group {
                    if circular { sectorChart }
                    else { cartesianChart }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let point = selected.first, let plot = proxy.plotFrame {
                            let frame = geometry[plot]
                            let anchor = tooltipAnchor(point, proxy: proxy, frame: frame)
                            ChartFloatingTooltip(anchor: anchor) {
                                ChartTooltip(title: point.x, entries: selected.map { datum in
                                    (datum.series, ValueFormat.text(.number(datum.y), format: context.node.props["format"]), palette[((circular ? categories.firstIndex(of: datum.x) : series.firstIndex(of: datum.series)) ?? 0) % palette.count])
                                })
                            }
                        }
                    }.allowsHitTesting(false)
                }
                .chartSelectionFocus(!selected.isEmpty, clear: clearSelection)
                .chartPlotStyle { $0.chartPlotBackground() }
                .frame(height: 220)
                .accessibilityLabel(context.node.props["title"]?.text ?? "图表")
                .accessibilityIdentifier("render-chart-" + kind)
                .accessibilityValue(points.map { "\($0.x)，\($0.series)，\($0.y.formatted())" }.joined(separator: "；"))
                // Stable x/series identities let Swift Charts interpolate new values.
                .animation(reduceMotion ? nil : RenderMotion.chart, value: points)
                .animation(reduceMotion ? nil : RenderMotion.chart, value: kind)
            }
            if circular { ChartLegendItems(names: categories, colors: palette) }
            else { ChartSeriesControls(series: series, colors: palette, hidden: $hiddenSeries) }
            if !selected.isEmpty && !showsTable {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(selected) { point in
                        Text("\(point.x) · \(point.series)：\(ValueFormat.text(.number(point.y), format: context.node.props["format"]))")
                            .font(.caption.monospacedDigit()).foregroundStyle(RenderTheme.muted)
                            .contentTransition(.numericText())
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 14))
                    .transition(.opacity)
                    .accessibilityIdentifier("render-chart-selection")
            }
        }
        .modifier(ChartEntrance(count: showsTable ? 0 : points.count, identity: kind + (rangeId ?? "") + points.map { $0.id + String($0.y) }.joined(separator: "|"), revealed: $entranceRevealed, session: context.session, instanceId: context.node.id))
        .onAppear {
            rangeId = context.node.props["defaultRangeId"]?.string ?? ranges.first?.object?["id"]?.string
        }
        .onChange(of: points) { clearSelection() }
        .onChange(of: kind) { clearSelection() }
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: selected)
        .sensoryFeedback(.selection, trigger: selected) { _, new in !new.isEmpty }
    }

    @ViewBuilder private var cartesianChart: some View {
        if horizontal { cartesianMarks.chartYScale(domain: categories).chartXScale(domain: yDomain).chartYSelection(value: $selectedX).chartGesture { proxy in chartSelectionGesture(proxy, horizontal: true) }.chartXAxis { formattedAxis } }
        else {
            let labels = categories
            let chart = cartesianMarks
                .chartXScale(domain: labels).chartYScale(domain: yDomain)
                .chartXSelection(value: $selectedX)
                .chartGesture { proxy in chartSelectionGesture(proxy, horizontal: false) }
                .chartYAxis { formattedAxis }
            if typeSize.isAccessibilitySize {
                let ticks = labels.count > 3 ? [labels[0], labels[(labels.count - 1) / 2], labels[labels.count - 1]] : labels
                chart.chartXAxis {
                    AxisMarks(values: ticks) { value in
                        AxisGridLine(centered: true)
                        AxisTick(centered: true)
                        if let label = value.as(String.self) {
                            AxisValueLabel(centered: true, collisionResolution: .disabled) {
                                Text(label).font(.caption2).lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                chart
            }
        }
    }
    private var formattedAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let number = value.as(Double.self) { Text(ValueFormat.text(.number(number), format: context.node.props["format"])) }
            }
        }
    }
    private var animatedPoints: [ChartDatum] {
        kind == "line" || kind == "area" ? Array(points.prefix(revealed)) : points
    }
    private var cartesianMarks: some View {
        let palette = palette
        return Chart {
            if divergesAroundBaseline { RuleMark(y: .value("基线", baseline)).foregroundStyle(RenderTheme.muted.opacity(0.5)).lineStyle(StrokeStyle(dash: [4, 4])) }
            ForEach(Array(animatedPoints.enumerated()), id: \.element.id) { index, point in
                let visible = index < revealed
                switch kind {
                case "bar":
                    if horizontal {
                        if stacked {
                            BarMark(x: .value("数值", visible ? point.y : 0), y: .value("类别", point.x)).foregroundStyle(by: .value("系列", point.series)).foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count])).cornerRadius(4).shadow(color: accent.opacity(0.16), radius: 2, x: 0, y: 2).opacity(visible ? 1 : 0)
                        } else {
                            BarMark(x: .value("数值", visible ? point.y : 0), y: .value("类别", point.x)).foregroundStyle(by: .value("系列", point.series)).position(by: .value("系列", point.series)).foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count])).cornerRadius(4).shadow(color: accent.opacity(0.16), radius: 2, x: 0, y: 2).opacity(visible ? 1 : 0)
                        }
                    } else if stacked {
                        BarMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : 0)).foregroundStyle(by: .value("系列", point.series)).foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count])).cornerRadius(4).shadow(color: accent.opacity(0.16), radius: 2, x: 0, y: 2).opacity(visible ? 1 : 0)
                    } else {
                        BarMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : 0)).foregroundStyle(by: .value("系列", point.series)).position(by: .value("系列", point.series)).foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count])).cornerRadius(4).shadow(color: accent.opacity(0.16), radius: 2, x: 0, y: 2).opacity(visible ? 1 : 0)
                    }
                case "scatter":
                    PointMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : 0))
                        .foregroundStyle(by: .value("系列", point.series)).foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count])).symbolSize(visible ? 55 : 0)
                default:
                    if kind == "area" {
                        if divergesAroundBaseline {
                            AreaMark(x: .value("类别", point.x), yStart: .value("基线", baseline), yEnd: .value("数值", visible ? point.y : baseline))
                                .foregroundStyle(baselineGradient).alignsMarkStylesWithPlotArea().opacity(0.15)
                        } else {
                            AreaMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : 0), series: .value("系列", point.series), stacking: stacked ? .standard : .unstacked)
                                .foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count])).opacity(0.25)
                        }
                    }
                    if !(kind == "area" && stacked) {
                    if divergesAroundBaseline {
                        LineMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : baseline), series: .value("系列", point.series))
                            .foregroundStyle(baselineGradient).alignsMarkStylesWithPlotArea()
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    } else {
                        LineMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : 0), series: .value("系列", point.series))
                            .foregroundStyle(by: .value("系列", point.series))
                            .foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count]))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    if divergesAroundBaseline {
                        PointMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : baseline))
                            .foregroundStyle(RenderChartPalette.gradient(point.y >= baseline ? RenderChartPalette.positive : RenderChartPalette.negative)).symbolSize(20)
                    } else {
                        PointMark(x: .value("类别", point.x), y: .value("数值", visible ? point.y : 0))
                            .foregroundStyle(by: .value("系列", point.series)).foregroundStyle(RenderChartPalette.gradient(palette[(series.firstIndex(of: point.series) ?? 0) % palette.count])).symbolSize(24)
                    }
                    }
                }
            }
            if !horizontal, let selectedX {
                RuleMark(x: .value("选中", selectedX)).foregroundStyle(.secondary.opacity(0.35))
            }
        }
        .chartForegroundStyleScale(domain: series, range: paletteForCount(series.count))
        .chartLegend(.hidden)

    }

    private var sectorChart: some View {
        let palette = palette
        return Chart(Array(points.enumerated()), id: \.element.id) { index, point in
            let visible = index < revealed
            SectorMark(angle: .value("数值", point.y),
                       innerRadius: .ratio(kind == "donut" ? 0.62 : 0),
                       outerRadius: .ratio(visible ? (selected.isEmpty || selected.first?.id == point.id ? 1 : 0.92) : 0.01),
                       angularInset: 2)
                .cornerRadius(4).shadow(color: accent.opacity(0.16), radius: 2, x: 0, y: 2)
                .foregroundStyle(RenderChartPalette.gradient(palette[(categories.firstIndex(of: point.x) ?? 0) % palette.count]))
                .opacity(visible ? (selected.isEmpty || selected.first?.id == point.id ? 1 : 0.5) : 0)
        }
        .chartForegroundStyleScale(domain: categories, range: paletteForCount(categories.count))
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedAngle)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { proxy.selectAngleValue(at: .radians(atan2($0.location.x - proxy.plotSize.width / 2, proxy.plotSize.height / 2 - $0.location.y))) }
                .exclusively(before: DragGesture(minimumDistance: 8).onChanged { proxy.selectAngleValue(at: .radians(atan2($0.location.x - proxy.plotSize.width / 2, proxy.plotSize.height / 2 - $0.location.y))) }.onEnded { _ in clearSelection() })
        }
    }

    private func tooltipAnchor(_ point: ChartDatum, proxy: ChartProxy, frame: CGRect) -> CGPoint {
        if circular {
            let total = points.reduce(0) { $0 + max(0, $1.y) }
            let before = points.prefix { $0.id != point.id }.reduce(0) { $0 + max(0, $1.y) }
            let angle = (before + max(0, point.y) / 2) / max(total, 0.0001) * 2 * .pi - .pi / 2
            let radius = min(frame.width, frame.height) * 0.36
            return CGPoint(x: frame.midX + cos(angle) * radius, y: frame.midY + sin(angle) * radius)
        }
        let value = stacked ? selected.filter { point.y >= 0 ? $0.y >= 0 : $0.y < 0 }.reduce(0) { $0 + $1.y } : point.y
        if horizontal {
            return CGPoint(x: frame.minX + (proxy.position(forX: value) ?? 0), y: frame.minY + (proxy.position(forY: point.x) ?? 0))
        }
        return CGPoint(x: frame.minX + (proxy.position(forX: point.x) ?? 0), y: frame.minY + (proxy.position(forY: value) ?? 0))
    }

    private func chartSelectionGesture(_ proxy: ChartProxy, horizontal: Bool) -> some Gesture {
        SpatialTapGesture().onEnded { event in
            if horizontal { proxy.selectYValue(at: event.location.y) } else { proxy.selectXValue(at: event.location.x) }
        }.exclusively(before: DragGesture(minimumDistance: 8).onChanged { event in
            if horizontal { proxy.selectYValue(at: event.location.y) } else { proxy.selectXValue(at: event.location.x) }
        }.onEnded { _ in clearSelection() })
    }

    private func clearSelection() {
        selectedX = nil
        selectedAngle = nil
    }

    private func paletteForCount(_ count: Int) -> [Color] {
        (0..<count).map { palette[$0 % palette.count] }
    }
}
