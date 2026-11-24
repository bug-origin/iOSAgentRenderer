import Charts
import SwiftUI
import AgentRendererCore

@MainActor
struct ComposedChartComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedX: String?
    @State private var entranceRevealed: Int
    private var revealed: Int { reduceMotion ? Int.max : entranceRevealed }
    @State private var showsTable = false
    @State private var hiddenSeries = Set<String>()
    init(context: ComponentRenderContext) {
        self.context = context
        let entered = context.session.presentationValue(for: context.node.id, key: "motion.chart") != nil
        _entranceRevealed = State(initialValue: entered ? Int.max : 0)
    }
    private var allRows: [[String: JSONValue]] { (context.node.props["data"]?.array ?? []).compactMap(\.object) }
    private var rows: [[String: JSONValue]] { allRows.filter { !hiddenSeries.contains($0["series"]?.text ?? "") } }
    private var series: [String] { allRows.reduce(into: []) { if let series = $1["series"]?.string, !$0.contains(series) { $0.append(series) } } }
    private func domain(_ axis: String) -> ClosedRange<Double> {
        let values = rows.filter { ($0["axis"]?.text ?? "left") == axis }.compactMap { $0["y"]?.number }
        let lower = min(0, values.min() ?? 0), upper = max(0, values.max() ?? 1)
        return lower...(upper > lower ? upper : lower + 1)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartPresentationHeader(title: context.node.props["title"]?.text ?? "组合图表", description: context.node.props["description"]?.string, rows: rows, showsTable: $showsTable)
            if showsTable { ChartDataTable(rows: rows) }
            else if rows.isEmpty { Text("暂无图表数据").font(.subheadline).foregroundStyle(RenderTheme.muted).frame(maxWidth: .infinity, minHeight: 220) }
            else {
                chart.chartLegend(.hidden).chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let selectedX, let plot = proxy.plotFrame,
                           let row = rows.first(where: { $0["x"]?.text == selectedX }) {
                            let frame = geometry[plot]
                            let left = domain("left"), right = domain("right")
                            let value = row["y"]?.number ?? 0
                            let y = row["axis"] == .string("right") ? (value - right.lowerBound) * (left.upperBound - left.lowerBound) / (right.upperBound - right.lowerBound) + left.lowerBound : value
                            ChartFloatingTooltip(anchor: CGPoint(x: frame.minX + (proxy.position(forX: selectedX) ?? 0), y: frame.minY + (proxy.position(forY: y) ?? 0))) {
                                ChartTooltip(title: selectedX, entries: rows.filter { $0["x"]?.text == selectedX }.map { item in
                                    let name = item["series"]?.text ?? ""
                                    return (name, item["y"]?.text ?? "", RenderChartPalette.color(series.firstIndex(of: name) ?? 0, accent))
                                })
                            }
                        }
                    }.allowsHitTesting(false)
                }.chartSelectionFocus(selectedX != nil) { selectedX = nil }.chartPlotStyle { $0.chartPlotBackground() }.frame(height: 240)
                if let selectedX {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rows.filter { $0["x"]?.text == selectedX }.enumerated()), id: \.offset) { _, row in
                            Text("\(selectedX) · \(row["series"]!.text)：\(row["y"]!.number!.formatted())").font(.caption.monospacedDigit())
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 14)).transition(.opacity)
                }
            }
            ChartSeriesControls(series: series, colors: RenderChartPalette.colors(accent), hidden: $hiddenSeries)
        }.modifier(ChartEntrance(count: showsTable ? 0 : rows.count, revealed: $entranceRevealed, session: context.session, instanceId: context.node.id))
            .onChange(of: context.node.props["data"]) { _, _ in selectedX = nil }
            .animation(reduceMotion ? nil : RenderMotion.chart, value: context.node.props["data"])
            .animation(reduceMotion ? nil : RenderMotion.feedback, value: selectedX)
            .sensoryFeedback(.selection, trigger: selectedX) { _, new in new != nil }
    }
    private var chart: some View {
        let palette = RenderChartPalette.colors(accent)
        let leftDomain = domain("left"), rightDomain = domain("right")
        let colors = Dictionary(uniqueKeysWithValues: series.enumerated().map { ($0.element, palette[$0.offset % palette.count]) })
        return Chart {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                let x = row["x"]!.text, name = row["series"]!.text
                let value = index < revealed ? row["y"]?.number ?? 0 : 0
                let rightAxis = row["axis"] == .string("right")
                let scale = (leftDomain.upperBound - leftDomain.lowerBound) / (rightDomain.upperBound - rightDomain.lowerBound)
                let zero = rightAxis ? -rightDomain.lowerBound * scale + leftDomain.lowerBound : 0
                let displayed = rightAxis ? (value - rightDomain.lowerBound) * scale + leftDomain.lowerBound : value
                if row["mark"] == .string("bar") || index < revealed {
                switch row["mark"]?.text {
                case "bar": BarMark(x: .value("类别", x), yStart: .value("基线", zero), yEnd: .value("数值", displayed)).foregroundStyle(by: .value("系列", name)).position(by: .value("系列", name)).foregroundStyle(RenderChartPalette.gradient(colors[name] ?? accent)).cornerRadius(3).shadow(color: accent.opacity(0.16), radius: 2, x: 0, y: 2).opacity(index < revealed ? 1 : 0)
                case "area":
                    AreaMark(x: .value("类别", x), yStart: .value("基线", zero), yEnd: .value("数值", displayed), series: .value("系列", name)).foregroundStyle(RenderChartPalette.gradient(colors[name] ?? accent)).opacity(0.25)
                    LineMark(x: .value("类别", x), y: .value("数值", displayed), series: .value("系列", name)).foregroundStyle(by: .value("系列", name)).foregroundStyle(RenderChartPalette.gradient(colors[name] ?? accent)).lineStyle(.init(lineWidth: 2))
                default: LineMark(x: .value("类别", x), y: .value("数值", displayed), series: .value("系列", name)).foregroundStyle(by: .value("系列", name)).foregroundStyle(RenderChartPalette.gradient(colors[name] ?? accent)).lineStyle(.init(lineWidth: 2.5))
                }
            }
            }
            if let selectedX { RuleMark(x: .value("选中", selectedX)).foregroundStyle(RenderTheme.muted.opacity(0.3)) }
        }.chartXScale(domain: rows.reduce(into: [String]()) { if let x = $1["x"]?.string, !$0.contains(x) { $0.append(x) } }).chartYScale(domain: leftDomain)
            .chartForegroundStyleScale(domain: series, range: series.indices.map { palette[$0 % palette.count] })
            .chartYAxis {
                AxisMarks(position: .leading)
                if rows.contains(where: { $0["axis"] == .string("right") }) {
                    AxisMarks(position: .trailing) { value in
                        AxisTick()
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                let left = leftDomain, right = rightDomain
                                let mapped = (number - left.lowerBound) / (left.upperBound - left.lowerBound) * (right.upperBound - right.lowerBound) + right.lowerBound
                                Text(mapped.formatted(.number.precision(.significantDigits(1...3))))
                            }
                        }
                    }
                }
            }.chartXSelection(value: $selectedX).chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }.exclusively(before: DragGesture(minimumDistance: 8).onChanged { proxy.selectXValue(at: $0.location.x) }.onEnded { _ in selectedX = nil }) }
            .accessibilityLabel(context.node.props["title"]?.text ?? "组合图表")
    }
}
