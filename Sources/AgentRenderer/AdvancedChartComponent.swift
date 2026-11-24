import Charts
import SwiftUI
import AgentRendererCore

@MainActor
struct AdvancedChartComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entranceRevealed: Int
    private var revealed: Int { reduceMotion ? Int.max : entranceRevealed }
    @State private var showsTable = false
    @State private var selected: Int?
    @State private var selectedX: String?
    @State private var scatterX: Double?
    init(context: ComponentRenderContext) {
        self.context = context
        let entered = context.session.presentationValue(for: context.node.id, key: "motion.chart") != nil
        _entranceRevealed = State(initialValue: entered ? Int.max : 0)
    }
    private var p: [String: JSONValue] { context.node.props }
    private var data: [[String: JSONValue]] { (p["data"]?.array ?? []).compactMap(\.object) }
    private var kind: String { context.node.type }
    private var maximum: Double { max(p["max"]?.number ?? data.compactMap { $0["value"]?.number }.max() ?? 1, 1) }
    private var indexed: [Int] { Array(data.indices) }
    private var active: Int? {
        if let selectedX { return data.firstIndex { $0["x"]?.string == selectedX } }
        if let scatterX { return indexed.min(by: { abs((data[$0]["x"]?.number ?? 0) - scatterX) < abs((data[$1]["x"]?.number ?? 0) - scatterX) }) }
        return selected
    }
    private var entranceCount: Int {
        guard !showsTable else { return 0 }
        if kind == "RadarChart" { return Set(data.map { $0["series"]?.text ?? "数值" }).count }
        guard kind == "GaugeChart" else { return data.count }
        return p["orientation"] == .string("linear") ? Int(p["notches"]?.number ?? 30) : 1
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ChartPresentationHeader(title: p["title"]?.text ?? kind, description: p["description"]?.string, rows: kind == "GaugeChart" ? [["value": p["value"] ?? .null]] : data, showsTable: $showsTable)
            if showsTable { ChartDataTable(rows: kind == "GaugeChart" ? [["value": p["value"] ?? .null]] : data) }
            else if data.isEmpty && kind != "GaugeChart" {
                Text("暂无图表数据").foregroundStyle(RenderTheme.muted).frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Group {
                    switch kind {
                    case "GaugeChart": gauge
                    case "CandlestickChart": candles
                    case "NumericScatterChart": scatter
                    case "Heatmap": heatmap
                    case "RadarChart": radar
                    case "RadialChart": radial
                    default: funnel
                    }
                }.overlayPreferenceValue(ChartSelectedAnchorKey.self) { anchor in
                    GeometryReader { geometry in
                        if let anchor, let active {
                            let rect = geometry[anchor]
                            ChartFloatingTooltip(anchor: CGPoint(x: rect.midX, y: rect.midY)) { tooltip(active) }
                        }
                    }.allowsHitTesting(false)
                }
                .chartSelectionFocus(active != nil) { selected = nil; selectedX = nil; scatterX = nil }
                .chartPlotBackground()
                .accessibilityIdentifier("render-chart-" + kind)
            }
            if let active, data.indices.contains(active) {
                Text(summary(data[active])).font(.caption.monospacedDigit()).foregroundStyle(RenderTheme.muted)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 14)).transition(.opacity)
            }
        }.modifier(ChartEntrance(count: entranceCount, revealed: $entranceRevealed, session: context.session, instanceId: context.node.id))
            .onChange(of: p) { _, _ in selected = nil; selectedX = nil; scatterX = nil }
            .animation(reduceMotion ? nil : RenderMotion.feedback, value: active)
            .animation(reduceMotion ? nil : RenderMotion.chart, value: p)
    }
    private func tooltip(_ index: Int) -> some View {
        let row = data[index]
        return ChartTooltip(title: row["label"]?.text ?? row["x"]?.text ?? "详情", entries: row.keys.sorted().filter { row[$0]?.number != nil }.enumerated().map { offset, key in
            (key, ValueFormat.text(row[key]!, format: p["format"]), RenderChartPalette.color(offset, accent))
        })
    }

    private func tooltipOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let active, let plot = proxy.plotFrame {
                let row = data[active]
                let frame = geometry[plot]
                let x = kind == "NumericScatterChart" ? proxy.position(forX: row["x"]?.number ?? 0) : proxy.position(forX: row["x"]?.text ?? "")
                let y = kind == "Heatmap" ? proxy.position(forY: row["y"]?.text ?? "") : proxy.position(forY: row[kind == "CandlestickChart" ? "high" : "y"]?.number ?? 0)
                ChartFloatingTooltip(anchor: CGPoint(x: frame.minX + (x ?? 0), y: frame.minY + (y ?? 0))) { tooltip(active) }
            }
        }.allowsHitTesting(false)
    }

    private func formatted(_ value: Double) -> String { ValueFormat.text(.number(value), format: p["format"]) }
    private func summary(_ row: [String: JSONValue]) -> String {
        row.keys.sorted().map { "\($0)：\(ValueFormat.text(row[$0]!, format: row[$0]?.number == nil ? nil : p["format"]))" }.joined(separator: " · ")
    }
    private var gaugeColor: Color {
        switch p["tone"]?.text { case "success": RenderChartPalette.positive; case "warning": RenderChartPalette.warning; case "danger": RenderChartPalette.negative; default: RenderChartPalette.primary }
    }
    @ViewBuilder private var gauge: some View {
        if p["orientation"] == .string("linear") { linearGauge }
        else { arcGauge }
    }
    private var linearGauge: some View {
        let lower = p["min"]?.number ?? 0, upper = p["max"]?.number ?? 100, value = p["value"]?.number ?? 0
        let fraction = (value - lower) / (upper - lower)
        let count = Int(p["notches"]?.number ?? 30)
        return VStack(alignment: .leading, spacing: 16) {
            Text(revealed > 0 ? formatted(value) : "—").font(.system(size: 32, weight: .semibold)).contentTransition(.numericText())
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2).fill(RenderChartPalette.gradient(index < revealed && Double(index) / Double(count) < fraction ? gaugeColor : RenderTheme.neutral)).frame(height: 28)
                }
            }
            HStack { Text(p["label"]?.text ?? ""); Spacer(); Text(formatted(lower) + " – " + formatted(upper)) }.font(.caption).foregroundStyle(RenderTheme.muted)
        }.accessibilityElement(children: .combine)
    }
    private var arcGauge: some View {
        let lower = p["min"]?.number ?? 0, upper = p["max"]?.number ?? 100
        let value = p["value"]?.number ?? 0
        let fraction = (value - lower) / (upper - lower)
        return VStack(spacing: 8) {
            ZStack {
                Circle().trim(from: 0, to: 0.75).stroke(RenderTheme.neutral, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                Circle().trim(from: 0, to: revealed > 0 ? fraction * 0.75 : 0).stroke(RenderChartPalette.gradient(gaugeColor), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                if let count = p["notches"]?.number {
                    Circle().trim(from: 0, to: 0.75).stroke(RenderTheme.surface, style: StrokeStyle(lineWidth: 20, dash: [2, max(1, 424 / count - 2)]))
                }
                VStack(spacing: 4) {
                    Text(revealed > 0 ? formatted(value) : "—").font(.system(size: 32, weight: .semibold)).contentTransition(.numericText())
                    if let label = p["label"]?.string { Text(label).font(.caption).foregroundStyle(RenderTheme.muted) }
                }.rotationEffect(.degrees(-135))
            }.rotationEffect(.degrees(135)).frame(width: 180, height: 180).padding(12)
            HStack { Text(formatted(lower)); Spacer(); Text(formatted(upper)) }.font(.caption).foregroundStyle(RenderTheme.muted).frame(width: 190)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
    private var formattedAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine(); AxisTick()
            AxisValueLabel { if let number = value.as(Double.self) { Text(formatted(number)) } }
        }
    }
    private var candles: some View {
        Chart(indexed, id: \.self) { i in
            let row = data[i]
            let x = row["x"]!.text
            let rising = row["close"]!.number! >= row["open"]!.number!
            RuleMark(x: .value("日期", x), yStart: .value("低", row["low"]!.number!), yEnd: .value("高", row["high"]!.number!))
                .foregroundStyle(RenderChartPalette.gradient(rising ? RenderChartPalette.positive : RenderChartPalette.negative)).opacity(i < revealed ? 1 : 0)
            BarMark(x: .value("日期", x), yStart: .value("开盘", row["open"]!.number!), yEnd: .value("收盘", row["close"]!.number!), width: .ratio(0.55))
                .foregroundStyle(RenderChartPalette.gradient(rising ? RenderChartPalette.positive : RenderChartPalette.negative)).opacity(i < revealed ? 1 : 0).cornerRadius(2)
            if selectedX == x { RuleMark(x: .value("选中", x)).foregroundStyle(RenderTheme.muted.opacity(0.3)) }
        }.chartOverlay { tooltipOverlay($0) }.chartXSelection(value: $selectedX).chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }.exclusively(before: DragGesture(minimumDistance: 8).onChanged { proxy.selectXValue(at: $0.location.x) }.onEnded { _ in selectedX = nil; scatterX = nil }) }.chartYAxis { formattedAxis }.frame(height: 220)
    }
    private func bubbleSize(_ index: Int) -> CGFloat {
        let maximum = max(data.compactMap { $0["size"]?.number }.max() ?? 1, 1)
        let area = data[index]["size"]?.number.map { 30 + 240 * $0 / maximum } ?? 45
        return CGFloat(area * (active == index ? 1.5 : 1))
    }
    private func seriesIndex(_ index: Int) -> Int {
        let names = data.reduce(into: [String]()) { result, row in
            let name = row["series"]?.text ?? "数值"
            if !result.contains(name) { result.append(name) }
        }
        return names.firstIndex(of: data[index]["series"]?.text ?? "数值") ?? 0
    }
    private var scatter: some View {
        Chart(indexed, id: \.self) { i in
            PointMark(x: .value("X", data[i]["x"]!.number!), y: .value("Y", data[i]["y"]!.number!))
                .foregroundStyle(RenderChartPalette.gradient(RenderChartPalette.color(seriesIndex(i), accent))).shadow(color: accent.opacity(0.18), radius: 2, x: 0, y: 2).symbolSize(i < revealed ? bubbleSize(i) : 0)
                .annotation(position: .top) { if i < revealed, let label = data[i]["label"]?.string { Text(label).font(.caption2).foregroundStyle(RenderTheme.muted) } }
        }.chartOverlay { tooltipOverlay($0) }.chartForegroundStyleScale(range: RenderChartPalette.colors(accent))
            .chartXSelection(value: $scatterX).chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }.exclusively(before: DragGesture(minimumDistance: 8).onChanged { proxy.selectXValue(at: $0.location.x) }.onEnded { _ in selectedX = nil; scatterX = nil }) }.chartYAxis { formattedAxis }.frame(height: 220)
    }
    private var heatRange: ClosedRange<Double> {
        let values = data.compactMap { $0["value"]?.number }
        let low = values.min() ?? 0, high = values.max() ?? 1
        return low...max(low + 0.0001, high)
    }
    private func selectHeatmap(at point: CGPoint, proxy: ChartProxy) {
        guard let x: String = proxy.value(atX: point.x), let y: String = proxy.value(atY: point.y) else { return }
        selectedX = nil
        selected = data.firstIndex { $0["x"]?.text == x && $0["y"]?.text == y }
    }
    private var heatmap: some View {
        Chart(indexed, id: \.self) { i in
            RectangleMark(x: .value("X", data[i]["x"]!.text), y: .value("Y", data[i]["y"]!.text))
                .foregroundStyle(RenderChartPalette.gradient(RenderChartPalette.primary.opacity(0.15 + 0.85 * (data[i]["value"]!.number! - heatRange.lowerBound) / (heatRange.upperBound - heatRange.lowerBound))))
                .cornerRadius(3).shadow(color: accent.opacity(0.1), radius: 1, x: 0, y: 1)
                .opacity(i < revealed ? (active == nil || active == i ? 1 : 0.55) : 0)
        }.chartOverlay { tooltipOverlay($0) }.chartForegroundStyleScale(range: Gradient(colors: [RenderChartPalette.primary.opacity(0.08), RenderChartPalette.primary]))
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { selectHeatmap(at: $0.location, proxy: proxy) }
                    .exclusively(before: DragGesture(minimumDistance: 8).onChanged { selectHeatmap(at: $0.location, proxy: proxy) }.onEnded { _ in selected = nil })
            }.frame(height: 220)
    }
    private var funnel: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let horizontal = p["orientation"] == .string("horizontal")
                let layout = horizontal ? AnyLayout(HStackLayout(spacing: 2)) : AnyLayout(VStackLayout(spacing: 2))
                layout {
                    ForEach(indexed, id: \.self) { i in
                        let current = data[i]["value"]!.number! / maximum
                        let next = data.indices.contains(i + 1) ? data[i + 1]["value"]!.number! / maximum : current
                        FunnelStage(top: i < revealed ? current : 0, bottom: i < revealed ? next : 0, horizontal: horizontal)
                            .fill(RenderChartPalette.gradient(RenderChartPalette.color(i, accent)))
                            .opacity(active == nil || active == i ? 1 : 0.45)
                            .shadow(color: accent.opacity(0.15), radius: 2, x: 0, y: 2)
                            .chartTooltipAnchor(selected: active == i)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = selected == i ? nil : i }
                            .accessibilityLabel(summary(data[i])).accessibilityAddTraits(.isButton)
                    }
                }.frame(width: geometry.size.width)
            }.frame(height: 180)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 14) {
                ForEach(indexed, id: \.self) { i in
                    Button { selected = selected == i ? nil : i } label: {
                        HStack(spacing: 6) {
                            Circle().fill(RenderChartPalette.gradient(RenderChartPalette.color(i, accent))).frame(width: 6, height: 6)
                            Text(data[i]["label"]!.text).foregroundStyle(RenderTheme.muted)
                            Spacer(minLength: 4)
                            Text(formatted(data[i]["value"]!.number!))
                            if p["showPercentages"] != .bool(false) { Text((data[i]["value"]!.number! / max(data.first?["value"]?.number ?? 1, 1)).formatted(.percent.precision(.fractionLength(0...1)))) }
                        }.font(.system(size: 11)).monospacedDigit().padding(.vertical, 4)
                    }.buttonStyle(RenderPlainButtonStyle()).accessibilityAddTraits(active == i ? .isSelected : [])
                }
            }
        }
    }
    private var radial: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(indexed, id: \.self) { i in
                    let inset = CGFloat(i) * 15
                    Circle().stroke(RenderTheme.neutral, lineWidth: 10).padding(inset)
                    Circle().trim(from: 0, to: i < revealed ? data[i]["value"]!.number! / maximum : 0)
                        .stroke(RenderChartPalette.gradient(RenderChartPalette.color(i, accent)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(inset)
                        .shadow(color: accent.opacity(0.18), radius: 2, x: 0, y: 2)
                        .onTapGesture { selected = selected == i ? nil : i }
                    let angle = data[i]["value"]!.number! / maximum * 2 * .pi - .pi / 2
                    Color.clear.frame(width: 1, height: 1)
                        .chartTooltipAnchor(selected: active == i)
                        .offset(x: cos(angle) * (100 - inset), y: sin(angle) * (100 - inset))
                }
            }.frame(width: 200, height: 200).padding(6)
            ForEach(indexed, id: \.self) { i in
                Button { selected = selected == i ? nil : i } label: {
                    HStack { Text(data[i]["label"]!.text); Spacer(); Text(formatted(data[i]["value"]!.number!)).monospacedDigit() }.font(.caption)
                }.buttonStyle(RenderPlainButtonStyle()).foregroundStyle(active == i ? accent : RenderTheme.muted)
            }
        }.frame(maxWidth: .infinity)
    }
    private var radar: some View {
        let labels = data.reduce(into: [String]()) { if let label = $1["label"]?.string, !$0.contains(label) { $0.append(label) } }
        let series = data.reduce(into: [String]()) { let s = $1["series"]?.text ?? "数值"; if !$0.contains(s) { $0.append(s) } }
        return VStack(spacing: 12) {
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let radius = min(geometry.size.width, geometry.size.height) * 0.34
                ZStack {
                    ForEach(1...4, id: \.self) { ring in
                        RadarPolygon(values: Array(repeating: Double(ring) / 4, count: labels.count)).stroke(RenderTheme.border, lineWidth: 1).frame(width: radius * 2, height: radius * 2).position(center)
                    }
                    ForEach(Array(series.enumerated()), id: \.offset) { seriesIndex, s in
                        let values = labels.map { label in data.first { $0["label"]?.string == label && ($0["series"]?.text ?? "数值") == s }?["value"]?.number ?? 0 }
                        RadarPolygon(values: values.map { $0 / maximum }, progress: seriesIndex < revealed ? 1 : 0)
                            .fill(RenderChartPalette.gradient(RenderChartPalette.color(seriesIndex, accent))).opacity(0.16)
                            .overlay { RadarPolygon(values: values.map { $0 / maximum }, progress: seriesIndex < revealed ? 1 : 0).stroke(RenderChartPalette.gradient(RenderChartPalette.color(seriesIndex, accent)), lineWidth: 2) }
                            .frame(width: radius * 2, height: radius * 2).position(center)
                    }
                    ForEach(indexed, id: \.self) { i in
                        let labelIndex = labels.firstIndex(of: data[i]["label"]?.text ?? "") ?? 0
                        let angle = Double(labelIndex) / Double(max(1, labels.count)) * 2 * .pi - .pi / 2
                        let distance = radius * (data[i]["value"]?.number ?? 0) / maximum
                        let visible = seriesIndex(i) < revealed
                        Button { selected = selected == i ? nil : i } label: {
                            Circle().fill(RenderChartPalette.gradient(RenderChartPalette.color(seriesIndex(i), accent)))
                                .frame(width: active == i ? 10 : 7, height: active == i ? 10 : 7)
                                .padding(10).contentShape(Circle())
                        }.buttonStyle(RenderPlainButtonStyle())
                            .opacity(visible ? 1 : 0)
                            .allowsHitTesting(visible)
                            .chartTooltipAnchor(selected: active == i)
                            .position(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                            .accessibilityLabel(summary(data[i]))
                    }
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        let angle = Double(index) / Double(labels.count) * 2 * .pi - .pi / 2
                        Text(label).font(.system(size: 11)).foregroundStyle(RenderTheme.muted)
                            .position(x: center.x + cos(angle) * (radius + 24), y: center.y + sin(angle) * (radius + 20))
                    }
                }
            }.frame(height: 250)
            ChartLegendItems(names: series, colors: RenderChartPalette.colors(accent))
        }
    }
}

private struct RadarPolygon: Shape {
    var values: [Double]
    var progress: Double = 1
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        Path { path in
            for (index, value) in values.enumerated() {
                let angle = Double(index) / Double(values.count) * 2 * .pi - .pi / 2
                let point = CGPoint(x: rect.midX + cos(angle) * rect.width / 2 * value * progress, y: rect.midY + sin(angle) * rect.height / 2 * value * progress)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}

private struct FunnelStage: Shape {
    var top: Double
    var bottom: Double
    var horizontal = false
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let bounds = horizontal ? CGRect(x: 0, y: 0, width: rect.height, height: rect.width) : rect
        let path = Path { path in
            let rect = bounds
            path.move(to: .init(x: rect.midX - rect.width * top / 2, y: rect.minY))
            path.addLine(to: .init(x: rect.midX + rect.width * top / 2, y: rect.minY))
            path.addLine(to: .init(x: rect.midX + rect.width * bottom / 2, y: rect.maxY))
            path.addLine(to: .init(x: rect.midX - rect.width * bottom / 2, y: rect.maxY))
            path.closeSubpath()
        }
        return horizontal ? path.applying(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)) : path
    }
}
