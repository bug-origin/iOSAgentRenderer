import SwiftUI
import AgentRendererCore

private struct FlowDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY)); path.closeSubpath()
        }
    }
}

@MainActor
struct FlowchartComponent: View {
    let context: ComponentRenderContext
    var overrideProps: [String: JSONValue]? = nil
    private var props: [String: JSONValue] { overrideProps ?? context.node.props }
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var appeared = false
    @State private var fullscreen = false
    var isFullscreen = false
    private var horizontal: Bool { props["direction"] == .string("horizontal") }
    private var graph: FlowchartGraph? {
        try? FlowchartGraph(nodes: props["nodes"] ?? .null, edges: props["edges"] ?? .null)
    }
    var body: some View {
        if let graph {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(props["title"]?.string ?? "流程图").font(.subheadline.weight(.medium))
                    Spacer()
                    if !isFullscreen {
                        Button { fullscreen = true } label: {
                            HStack(spacing: 6) {
                                Image("lucide-arrow-up-right", bundle: .module).resizable().scaledToFit().frame(width: 16, height: 16)
                                Text("全屏").font(.caption.weight(.medium))
                            }.foregroundStyle(accent).padding(.horizontal, 12).frame(minHeight: 44)
                                .background(accent.opacity(0.1), in: Capsule())
                        }.buttonStyle(RenderPlainButtonStyle()).accessibilityLabel("全屏流程图")
                    }
                }.zIndex(1)
                let layout = FlowLayout(graph: graph, horizontal: horizontal)
                RenderZoomViewport(canvasSize: layout.size) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(graph.edges.enumerated()), id: \.element.id) { index, edge in
                            edgeView(edge, index: index, layout: layout)
                        }
                        ForEach(graph.nodes) { node in
                            Button {
                                context.session.setFocus(nil)
                                withAnimation(reduceMotion ? nil : RenderMotion.feedback) {
                                    selectedID = selectedID == node.id ? nil : node.id
                                }
                            } label: { nodeView(node) }
                                .buttonStyle(RenderPlainButtonStyle())
                                .frame(width: 180, height: 100)
                                .position(layout.position(node.id))
                                .accessibilityLabel(node.label + "，" + statusLabel(node.status))
                                .accessibilityHint(accessibilityHint(node, graph: graph))
                                .accessibilityAddTraits(selectedID == node.id ? .isSelected : [])
                        }
                    }
                    .frame(width: layout.size.width, height: layout.size.height)
                    .opacity(appeared ? 1 : 0)
                    .animation(reduceMotion ? nil : RenderMotion.chart, value: graph)
                }
                .frame(height: isFullscreen ? nil : 320)
                .frame(maxHeight: isFullscreen ? .infinity : nil)
                .background(RenderTheme.secondary, in: RoundedRectangle(cornerRadius: RenderTheme.surfaceRadius))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("flowchart-viewport")
                if let node = graph.nodes.first(where: { $0.id == selectedID }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(node.label).font(.subheadline.weight(.semibold))
                        Text(statusLabel(node.status)).font(.caption).foregroundStyle(statusColor(node.status))
                        if let detail = node.detail, !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(RenderTheme.muted) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 16))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .renderFullScreen(isPresented: $fullscreen) {
                ZStack {
                    FlowchartComponent(context: context, overrideProps: overrideProps, isFullscreen: true).padding()
                        .overlay(alignment: .topTrailing) { Button("完成") { fullscreen = false }.buttonStyle(.bordered).padding() }
                }.tint(accent)
            }
            .onAppear { withAnimation(reduceMotion ? nil : RenderMotion.chart) { appeared = true } }
            .onChange(of: graph.nodes.map(\.id)) {
                if !graph.nodes.contains(where: { $0.id == selectedID }) { selectedID = nil }
            }
        }
    }

    private func nodeView(_ node: FlowchartGraph.Node) -> some View {
        let selected = selectedID == node.id
        let color = statusColor(node.status)
        return ZStack {
            Group {
                switch node.kind {
                case "decision":
                    FlowDiamond().fill(RenderTheme.surface)
                    FlowDiamond().fill(selected ? accent.opacity(0.12) : color.opacity(0.06))
                    FlowDiamond().stroke(color.opacity(selected ? 1 : 0.45), lineWidth: selected ? 2 : 1)
                case "start", "end":
                    Capsule().fill(RenderTheme.surface)
                    Capsule().fill(selected ? accent.opacity(0.12) : color.opacity(0.06))
                    Capsule().strokeBorder(color.opacity(selected ? 1 : 0.45), lineWidth: selected ? 2 : 1)
                default:
                    RoundedRectangle(cornerRadius: 14).fill(RenderTheme.surface)
                    RoundedRectangle(cornerRadius: 14).fill(selected ? accent.opacity(0.12) : color.opacity(0.06))
                    RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(selected ? 1 : 0.45), lineWidth: selected ? 2 : 1)
                }
            }
            VStack(spacing: 5) {
                Text(node.label).font(.subheadline.weight(.medium)).foregroundStyle(RenderTheme.foreground).lineLimit(2)
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 5, height: 5)
                    Text(statusLabel(node.status)).font(.caption2).foregroundStyle(RenderTheme.muted)
                }
            }.frame(maxWidth: node.kind == "decision" ? 105 : 152)
        }
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: selected)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: node.status)
    }

    private func edgeView(_ edge: FlowchartGraph.Edge, index: Int, layout: FlowLayout) -> some View {
        let route = layout.route(edge, index: index)
        return ZStack(alignment: .topLeading) {
            route.path.trim(from: 0, to: appeared ? 1 : 0)
                .stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            Path { path in
                let angle = atan2(route.end.y - route.control.y, route.end.x - route.control.x)
                for delta in [-0.5, 0.5] {
                    path.move(to: route.end)
                    path.addLine(to: CGPoint(x: route.end.x - 8 * cos(angle + delta), y: route.end.y - 8 * sin(angle + delta)))
                }
            }.stroke(accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .opacity(appeared ? 1 : 0)
            if let label = edge.label, !label.isEmpty {
                Text(label).font(.caption2).foregroundStyle(RenderTheme.muted).lineLimit(2)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(RenderTheme.surface, in: RoundedRectangle(cornerRadius: 5))
                    .frame(maxWidth: 100).fixedSize(horizontal: false, vertical: true)
                    .position(route.label)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
    private func accessibilityHint(_ node: FlowchartGraph.Node, graph: FlowchartGraph) -> String {
        let targets = graph.edges.filter { $0.from == node.id }.compactMap { edge -> String? in
            guard let target = graph.nodes.first(where: { $0.id == edge.to }) else { return nil }
            return (edge.label.map { $0 + "：" } ?? "") + target.label
        }
        return "查看节点详情" + (targets.isEmpty ? "" : "。下一步：" + targets.joined(separator: "；"))
    }

    private func statusColor(_ status: String) -> Color {
        switch status { case "active", "completed": accent; case "failed": RenderTheme.danger; default: RenderTheme.muted }
    }
    private func statusLabel(_ status: String) -> String {
        switch status { case "active": "进行中"; case "completed": "已完成"; case "failed": "失败"; default: "待处理" }
    }
}

private struct FlowLayout {
    let graph: FlowchartGraph
    let horizontal: Bool
    private var breadth: Int { graph.layers.map(\.count).max() ?? 1 }
    var size: CGSize {
        horizontal ? CGSize(width: CGFloat(graph.layers.count) * 252 + 48, height: CGFloat(breadth) * 140 + 120)
            : CGSize(width: CGFloat(breadth) * 216 + 144, height: CGFloat(graph.layers.count) * 156 + 48)
    }
    func position(_ id: String) -> CGPoint {
        for (rank, layer) in graph.layers.enumerated() {
            if let index = layer.firstIndex(of: id) {
                let slot = CGFloat(index) + CGFloat(breadth - layer.count) / 2
                return horizontal ? CGPoint(x: CGFloat(rank) * 252 + 120, y: slot * 140 + 72)
                    : CGPoint(x: slot * 216 + 120, y: CGFloat(rank) * 156 + 72)
            }
        }
        return .zero
    }
    struct Route { let path: Path; let end: CGPoint; let control: CGPoint; let label: CGPoint }
    func route(_ edge: FlowchartGraph.Edge, index: Int) -> Route {
        let source = position(edge.from), target = position(edge.to)
        let distance = horizontal ? target.x - source.x : target.y - source.y
        let forward = distance > 0 && distance <= (horizontal ? 253 : 157)
        let start: CGPoint, end: CGPoint, first: CGPoint, second: CGPoint, label: CGPoint
        if forward {
            start = horizontal ? CGPoint(x: source.x + 90, y: source.y) : CGPoint(x: source.x, y: source.y + 50)
            end = horizontal ? CGPoint(x: target.x - 90, y: target.y) : CGPoint(x: target.x, y: target.y - 50)
            let middle = horizontal ? (start.x + end.x) / 2 : (start.y + end.y) / 2
            first = horizontal ? CGPoint(x: middle, y: start.y) : CGPoint(x: start.x, y: middle)
            second = horizontal ? CGPoint(x: middle, y: end.y) : CGPoint(x: end.x, y: middle)
            label = horizontal ? CGPoint(x: middle, y: (start.y + end.y) / 2) : CGPoint(x: (start.x + end.x) / 2, y: middle)
        } else {
            // Back edges and self-loops use an outside rail instead of crossing node contents.
            let rail = (horizontal ? size.height : size.width) - 24 - CGFloat(index % 4) * 16
            start = horizontal ? CGPoint(x: source.x + 15, y: source.y + 50) : CGPoint(x: source.x + 90, y: source.y - 15)
            end = horizontal ? CGPoint(x: target.x - 15, y: target.y + 50) : CGPoint(x: target.x + 90, y: target.y + 15)
            first = horizontal ? CGPoint(x: start.x, y: rail) : CGPoint(x: rail, y: start.y)
            second = horizontal ? CGPoint(x: end.x, y: rail) : CGPoint(x: rail, y: end.y)
            // Cubic midpoint for a label that remains attached to its edge.
            label = CGPoint(x: (start.x + 3 * first.x + 3 * second.x + end.x) / 8,
                            y: (start.y + 3 * first.y + 3 * second.y + end.y) / 8)
        }
        var path = Path(); path.move(to: start); path.addCurve(to: end, control1: first, control2: second)
        return Route(path: path, end: end, control: second, label: label)
    }
}
