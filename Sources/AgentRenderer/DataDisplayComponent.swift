import Charts
import SwiftUI
import AgentRendererCore

@MainActor
struct DataDisplayComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var imageIndex: Int?
    private var p: [String: JSONValue] { context.node.props }
    private var kind: String { context.node.type }
    private var rows: [[String: JSONValue]] {
        let key = kind == "Image" ? "images" : kind == "RecordCard" ? "fields" : ["MetricGrid", "KPIGrid"].contains(kind) ? "metrics" : "items"
        return (p[key]?.array ?? []).compactMap(\.object)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if kind == "RecordCard", let image = p["image"]?.object { RenderMediaPreview(image: image) }
            if kind == "RecordCard", let status = p["status"]?.object {
                Text(status["label"]?.text ?? "").font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundStyle(statusColor(status)).background(statusColor(status).opacity(0.12), in: Capsule())
            }
            if let eyebrow = p["eyebrow"]?.string { Text(eyebrow).font(.caption.weight(.medium)).foregroundStyle(RenderTheme.muted) }
            if let title = p["title"]?.string { Text(title).font(.system(size: 14, weight: .medium)) }
            if let description = p["description"]?.string { Text(description).font(.subheadline).foregroundStyle(RenderTheme.muted) }
            if rows.isEmpty && kind != "RecordCard" { Text("暂无数据").font(.subheadline).foregroundStyle(RenderTheme.muted) }
            else if kind == "Image" { images }
            else if ["MetricGrid", "KPIGrid", "RecordCard"].contains(kind) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: kind == "RecordCard" ? 120 : 140), alignment: .leading)], alignment: .leading, spacing: 16) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in metric(row, index: index) }
                }
            } else {
                VStack(spacing: 20) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if kind == "MeterList" { meter(row) }
                        else { comparison(row, index: index) }
                    }
                }
            }
            context.children
        }.padding(kind == "RecordCard" ? 16 : 0)
            .background(kind == "RecordCard" && p["variant"] != .string("clear") ? RenderTheme.surface : .clear, in: RoundedRectangle(cornerRadius: RenderTheme.surfaceRadius))
            .overlay { if kind == "RecordCard" && p["variant"] == .string("outline") { RoundedRectangle(cornerRadius: RenderTheme.surfaceRadius).strokeBorder(RenderTheme.border, lineWidth: 1) } }
            .foregroundStyle(RenderTheme.foreground)
            .onAppear { withAnimation(reduceMotion ? nil : RenderMotion.chart) { appeared = true } }
            .animation(reduceMotion ? nil : RenderMotion.chart, value: p)

    }
    private func statusColor(_ status: [String: JSONValue]) -> Color {
        switch status["tone"]?.text { case "success": RenderTheme.success; case "warning": RenderTheme.warning; case "danger": RenderTheme.danger; case "neutral": RenderTheme.muted; default: accent }
    }
    private func metric(_ row: [String: JSONValue], index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row["label"]!.text).font(.system(size: 13)).foregroundStyle(RenderTheme.muted)
            Text(ValueFormat.text(row["value"]!, format: row["format"])).font(.system(size: kind == "RecordCard" ? 16 : 24, weight: .semibold)).contentTransition(.numericText())
            if let change = row["change"]?.number { changeLabel(change) }
            if kind == "KPIGrid", let trend = row["trend"]?.array {
                if trend.count >= 2 {
                    KPITrendChart(trend: trend, domain: trendDomain(trend), session: context.session,
                                  instanceId: context.node.id + ".trend.\(index)")
                } else { Text("历史数据不足").font(.caption2).foregroundStyle(RenderTheme.muted).frame(height: 42) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func trendDomain(_ trend: [JSONValue]) -> ClosedRange<Double> {
        let values = trend.compactMap(\.number), lower = values.min() ?? 0, upper = values.max() ?? 1
        let padding = max(abs(upper - lower) * 0.1, max(abs(upper), 1) * 0.02)
        return (lower - padding)...(upper + padding)
    }
    private func changeLabel(_ value: Double) -> some View {
        Text((value > 0 ? "+" : "") + value.formatted() + "%")
            .font(.system(size: 12, weight: .medium)).monospacedDigit()
            .foregroundStyle(value > 0 ? RenderTheme.success : value < 0 ? RenderTheme.danger : RenderTheme.muted)
    }
    private func meter(_ row: [String: JSONValue]) -> some View {
        let min = row["min"]?.number ?? 0, max = row["max"]?.number ?? 100, value = row["value"]!.number!
        let color = row["tone"] == .string("warning") ? RenderTheme.warning : row["tone"] == .string("success") ? RenderTheme.success : row["tone"] == .string("danger") ? RenderTheme.danger : accent
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text(row["label"]!.text).font(.subheadline.weight(.medium)); Spacer(); Text(ValueFormat.text(.number(value), format: row["format"]) + " / " + ValueFormat.text(.number(max), format: row["format"])).font(.caption).monospacedDigit().foregroundStyle(RenderTheme.muted) }
            GeometryReader { geometry in
                Capsule().fill(RenderTheme.neutral)
                Capsule().fill(color).frame(width: geometry.size.width * (appeared ? (value - min) / (max - min) : 0))
            }.frame(height: 8)
            if let description = row["description"]?.string { Text(description).font(.caption).foregroundStyle(RenderTheme.muted) }
        }.accessibilityElement(children: .combine)
    }
    private func comparison(_ row: [String: JSONValue], index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(RenderTheme.muted).frame(width: 20, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(row["label"]!.text).font(.subheadline.weight(.medium))
                if let note = row["note"]?.string { Text(note).font(.caption).foregroundStyle(RenderTheme.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(ValueFormat.text(row["value"]!, format: row["format"])).font(.subheadline.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
                if let change = row["change"]?.number { changeLabel(change) }
            }
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var images: some View {
        if p["variant"] == .string("horizontal") {
            ScrollView(.horizontal) { HStack(alignment: .top, spacing: 12) { imageButtons(width: 220) } }.scrollIndicators(.hidden)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], spacing: 12) { imageButtons(width: nil) }
        }
    }
    private func imageButtons(width: CGFloat?) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            Button { context.session.setFocus(nil); imageIndex = index } label: {
                VStack(alignment: .leading, spacing: 8) {
                    thumbnail(row)
                    if let caption = row["caption"]?.string { Text(caption).font(.caption).foregroundStyle(RenderTheme.muted).lineLimit(2) }
                }.frame(width: width).contentShape(Rectangle())
            }.buttonStyle(RenderPlainButtonStyle()).accessibilityLabel(row["alt"]!.text).accessibilityHint("打开图片预览")
                .renderFullScreen(isPresented: Binding(get: { imageIndex == index }, set: { if !$0 { imageIndex = nil } })) {
                    RenderImageViewer(url: row["src"]?.string.flatMap(URL.init(string:)), title: row["alt"]?.text ?? "图片")
                }
        }
    }
    private func thumbnail(_ row: [String: JSONValue]) -> some View {
        let ratio: CGFloat = switch row["aspectRatio"]?.text { case "portrait": 0.75; case "square": 1; case "wide": 16.0 / 9; case "landscape": 4.0 / 3; default: 1.5 }
        return GeometryReader { geometry in remoteImage(row, height: geometry.size.height) }.aspectRatio(ratio, contentMode: .fit)
    }
    private func remoteImage(_ row: [String: JSONValue], height: CGFloat) -> some View {
        AsyncImage(url: URL(string: row["src"]!.text), transaction: RenderMotion.imageLoad(reduceMotion)) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit().frame(maxWidth: .infinity, minHeight: height, maxHeight: height).background(RenderTheme.neutral)
            case .failure: VStack(spacing: 8) { Text("图片加载失败").font(.caption); Text(row["alt"]!.text).font(.caption2).foregroundStyle(RenderTheme.muted) }.frame(maxWidth: .infinity).frame(height: height).background(RenderTheme.neutral)
            default: ProgressView().frame(maxWidth: .infinity).frame(height: height).background(RenderTheme.neutral)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel(row["alt"]!.text)
    }
}

private struct KPITrendChart: View {
    let trend: [JSONValue]
    let domain: ClosedRange<Double>
    let session: RendererSession
    let instanceId: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entranceRevealed: Int
    private var revealed: Int { reduceMotion ? Int.max : entranceRevealed }

    init(trend: [JSONValue], domain: ClosedRange<Double>, session: RendererSession, instanceId: String) {
        self.trend = trend
        self.domain = domain
        self.session = session
        self.instanceId = instanceId
        let entered = session.presentationValue(for: instanceId, key: "motion.chart") != nil
        _entranceRevealed = State(initialValue: entered ? Int.max : 0)
    }

    var body: some View {
        Chart(Array(trend.prefix(revealed).enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("时间", index), y: .value("数值", value.number ?? 0))
                .foregroundStyle(RenderChartPalette.gradient(RenderChartPalette.primary)).opacity(0.12)
            LineMark(x: .value("时间", index), y: .value("数值", value.number ?? 0))
                .foregroundStyle(RenderChartPalette.gradient(RenderChartPalette.primary))
                .lineStyle(.init(lineWidth: 1.5))
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartXScale(domain: 0...(trend.count - 1)).chartYScale(domain: domain)
        .chartPlotStyle { $0.chartPlotBackground() }
        .frame(height: 42)
        .modifier(ChartEntrance(count: trend.count, revealed: $entranceRevealed, session: session, instanceId: instanceId))
        .accessibilityLabel("历史趋势：" + trend.map(\.text).joined(separator: "，"))
    }
}
