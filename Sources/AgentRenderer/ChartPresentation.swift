import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import AgentRendererCore

/// Native equivalents of the reference chart view/export controls.
struct ChartPresentationHeader: View {
    let title: String
    var description: String? = nil
    let rows: [[String: JSONValue]]
    @Binding var showsTable: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Menu {
                    Button(showsTable ? "显示图表" : "显示数据表") {
                        withAnimation(reduceMotion ? nil : RenderMotion.feedback) { showsTable.toggle() }
                    }
                    ShareLink(item: ChartCSV.encode(rows), preview: SharePreview(title + ".csv")) {
                        Text("导出 CSV")
                    }.disabled(rows.isEmpty)
                } label: {
                    Image("lucide-ellipsis", bundle: .module).resizable().scaledToFit()
                        .frame(width: 16, height: 16).foregroundStyle(RenderTheme.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).buttonStyle(RenderPlainButtonStyle())
                    .accessibilityLabel(title + "视图与导出")
            }
            if let description {
                Text(description).font(.caption).foregroundStyle(RenderTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ChartDataTable: View {
    let rows: [[String: JSONValue]]
    private var columns: [String] { Set(rows.flatMap(\.keys)).sorted() }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(columns, id: \.self) { Text($0).fontWeight(.medium).frame(width: 112, alignment: .leading).padding(10) }
                }.background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 12))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.self) { Text(row[$0]?.text ?? "—").frame(width: 112, alignment: .leading).padding(10).textSelection(.enabled) }
                    }
                    Divider().overlay(RenderTheme.border)
                }
                if rows.isEmpty { Text("暂无数据").foregroundStyle(RenderTheme.muted).padding(16) }
            }.font(.system(size: 12)).foregroundStyle(RenderTheme.foreground)
        }.frame(height: 220).accessibilityIdentifier("render-chart-data-table")
    }
}

struct ChartSeriesControls: View {
    let series: [String]
    let colors: [Color]
    @Binding var hidden: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(series.enumerated()), id: \.element) { index, name in
                    Button {
                        withAnimation(reduceMotion ? nil : RenderMotion.chart) {
                            if hidden.contains(name) { hidden.remove(name) } else { hidden.insert(name) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(colors[index % colors.count]).frame(width: 7, height: 7)
                        Text(name).font(.caption2).strikethrough(hidden.contains(name))
                        }.foregroundStyle(RenderTheme.muted).opacity(hidden.contains(name) ? 0.45 : 1).padding(.vertical, 8)
                    }.buttonStyle(RenderPlainButtonStyle()).accessibilityLabel(name).accessibilityValue(hidden.contains(name) ? "已隐藏" : "已显示").accessibilityHint("切换图表系列")
                }
            }
        }.scrollIndicators(.hidden)
    }
}

/// Fixed chart palette; gradients and swatches share the same series colors.
enum RenderChartPalette {
    static let primary = rgb(RenderTokens.chartPrimary)
    static let positive = rgb(RenderTokens.chartPositive)
    static let warning = rgb(RenderTokens.chartWarning)
    static let negative = rgb(RenderTokens.chartNegative)
    static let deep = rgb(RenderTokens.chartDeep)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255.0, green: Double((hex >> 8) & 255) / 255.0, blue: Double(hex & 255) / 255.0)
    }

    static func colors(_ accent: Color) -> [Color] {
        [primary, positive, warning, negative, deep]
    }
    static func color(_ index: Int, _ accent: Color) -> Color { colors(accent)[index % colors(accent).count] }
    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(stops: [.init(color: color.opacity(0.55), location: 0), .init(color: color, location: 0.42), .init(color: color.opacity(0.72), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct ChartEntrancePending: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        let next = nextValue()
        value = value || next
    }
}

/// Bounded stagger; cancelled automatically when the chart leaves the view tree.
struct ChartEntrance: ViewModifier {
    let count: Int
    var identity: String = ""
    @Binding var revealed: Int
    let session: RendererSession
    let instanceId: String
    @State private var started = false
    @State private var settled = false
    @State private var plotVisible = false
    @Environment(\.renderEntranceDelay) private var entranceDelay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Restore data animation inside hosts that suppress structural animation.
        content.animation(reduceMotion ? nil : RenderMotion.chart, value: revealed)
            .preference(key: ChartEntrancePending.self, value: count > 0 && plotVisible && !settled && !reduceMotion)
            .onGeometryChange(for: Bool.self) { geometry in
                guard let viewport = geometry.bounds(of: .scrollView(axis: .vertical)) else { return true }
                let plot = CGRect(origin: .zero, size: geometry.size)
                let overlap = plot.intersection(viewport)
                return !overlap.isNull && overlap.height >= min(65, plot.height * 0.25) && overlap.width > 0
            } action: { visible in
                plotVisible = visible
            }
            .task(id: "\(count)-\(reduceMotion)-\(plotVisible)-\(identity)") {
                guard count > 0 else { return }
                if started || session.presentationValue(for: instanceId, key: "motion.chart") != nil || reduceMotion {
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { revealed = count }
                    settled = true
                    started = true
                    session.setPresentationValue(.bool(true), for: instanceId, key: "motion.chart")
                    return
                }
                guard plotVisible else { return }
                // Give the laid-out plot a visible frame before any marks are drawn.
                do { try await Task.sleep(for: .seconds(0.30 + entranceDelay)) } catch { return }
                guard !Task.isCancelled else { return }
                started = true
                session.setPresentationValue(.bool(true), for: instanceId, key: "motion.chart")
                let delay = min(0.085, 0.9 / Double(count))
                for index in 1...count {
                    if index > 1 {
                        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    }
                    if index == count {
                        withAnimation(RenderMotion.chart, completionCriteria: .removed) {
                            revealed = index
                        } completion: { settled = true }
                    } else {
                        withAnimation(RenderMotion.chart) { revealed = index }
                    }
                }
            }
    }
}

extension View {
    func chartPlotBackground() -> some View {
        background(RenderTheme.neutral.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ChartLegendItems: View {
    let names: [String]
    let colors: [Color]
    var body: some View {
        RenderWrapLayout(spacing: 12) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 6) {
                    Circle().fill(colors[index % colors.count]).frame(width: 8, height: 8)
                    Text(name).font(.caption).foregroundStyle(RenderTheme.muted)
                }
            }
        }.accessibilityIdentifier("render-chart-legend")
    }
}

struct ChartTooltip: View {
    let title: String
    let entries: [(String, String, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 6) {
                    Circle().fill(entry.2).frame(width: 7, height: 7)
                    Text(entry.0)
                    Text(entry.1).monospacedDigit().fontWeight(.medium)
                }.font(.caption)
            }
        }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(RenderTheme.border, lineWidth: 0.5))
            .allowsHitTesting(false).accessibilityElement(children: .combine).accessibilityIdentifier("render-chart-tooltip")
    }
}

/// Positions the tooltip beside its datum and flips/clamps it at chart boundaries.
struct ChartFloatingTooltip<Content: View>: View {
    let anchor: CGPoint
    @ViewBuilder let content: Content
    @State private var tooltipSize: CGSize = .zero
    var body: some View {
        GeometryReader { geometry in
            content.frame(maxWidth: min(240, max(1, geometry.size.width - 12)))
                .fixedSize(horizontal: true, vertical: true)
                .background { GeometryReader { measured in
                    Color.clear.onAppear { tooltipSize = measured.size }
                        .onChange(of: measured.size) { _, size in tooltipSize = size }
                } }
                .position(ChartTooltipLayout.position(anchor: anchor, tooltip: tooltipSize, container: geometry.size))
        }.allowsHitTesting(false)
    }
}

struct ChartSelectedAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

extension View {
    func chartTooltipAnchor(selected: Bool) -> some View {
        anchorPreference(key: ChartSelectedAnchorKey.self, value: .bounds) { selected ? $0 : nil }
    }
}

enum ChartTooltipLayout {
    static func position(anchor: CGPoint, tooltip: CGSize, container: CGSize) -> CGPoint {
        let halfWidth = tooltip.width / 2, halfHeight = tooltip.height / 2
        let x = min(max(anchor.x, halfWidth + 6), max(halfWidth + 6, container.width - halfWidth - 6))
        let proposedY = anchor.y - tooltip.height - 12 > 0 ? anchor.y - halfHeight - 12 : anchor.y + halfHeight + 12
        let y = min(max(halfHeight + 4, proposedY), max(halfHeight + 4, container.height - halfHeight - 4))
        return CGPoint(x: x, y: y)
    }
}
