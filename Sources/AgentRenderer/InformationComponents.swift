import SwiftUI
import AgentRendererCore

/// Information primitives share the same typography, spacing and motion as form controls.
@MainActor
struct InformationComponent: View {
    static let types = ["Heading", "Divider", "Spacer", "Progress", "Rating", "Callout", "TagList", "List", "CodeBlock", "Accordion", "Tabs", "Timeline", "Row", "Icon"]
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0
    @State private var expanded: Set<Int> = []
    @Namespace private var tabPill
    init(context: ComponentRenderContext) {
        self.context = context
        _selected = State(initialValue: Int(context.session.presentationValue(for: context.node.id, key: "selected")?.number
            ?? context.node.props["defaultValue"]?.number ?? 0))
        _expanded = State(initialValue: Set((context.session.presentationValue(for: context.node.id, key: "expanded")?.array ?? [])
            .compactMap { $0.number.map { Int($0) } }))
    }
    private var p: [String: JSONValue] { context.node.props }
    private var labels: [String] { (p["labels"]?.array ?? []).compactMap(\.string) }
    private var tone: Color {
        switch p["tone"]?.string {
        case "success": RenderTheme.success
        case "warning": RenderTheme.warning
        case "danger": RenderTheme.danger
        default: accent
        }
    }
    var body: some View {
        Group {
            switch context.node.type {
            case "Icon":
                Image("lucide-" + (p["name"]?.text ?? "circle-help"), bundle: .module).resizable().scaledToFit()
                    .frame(width: p["size"]?.number ?? 20, height: p["size"]?.number ?? 20).foregroundStyle(accent)
                    .accessibilityLabel(p["label"]?.text ?? "").accessibilityHidden(p["label"] == nil)
            case "Heading":
                Text(p["text"]?.text ?? "").font(.system(size: headingSize, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            case "Divider": Rectangle().fill(RenderTheme.border).frame(height: 1).accessibilityHidden(true)
            case "Spacer": Color.clear.frame(height: p["size"]?.number ?? 16).accessibilityHidden(true)
            case "Progress": progress
            case "Rating": rating
            case "Callout": callout
            case "TagList": tags
            case "List": list
            case "CodeBlock": code
            case "Accordion": accordion
            case "Tabs": tabs
            case "Timeline": timeline
            case "Row": ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { context.children }
                VStack(alignment: .leading, spacing: 12) { context.children }
            }
            default: EmptyView()
            }
        }.foregroundStyle(RenderTheme.foreground)
            .onChange(of: selected) { _, value in
                context.session.setPresentationValue(.number(Double(value)), for: context.node.id, key: "selected")
            }
            .onChange(of: expanded) { _, value in
                context.session.setPresentationValue(.array(value.sorted().map { .number(Double($0)) }), for: context.node.id, key: "expanded")
            }
    }
    private var headingSize: CGFloat {
        switch Int(p["level"]?.number ?? 2) { case 1: 28; case 2: 24; case 3: 20; default: 16 }
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = p["label"]?.string { Text(label).font(.subheadline.weight(.medium)) }
            ProgressView(value: p["value"]?.number ?? 0, total: 100).tint(accent)
                .animation(reduceMotion ? nil : RenderMotion.chart, value: p["value"])
            Text((p["value"]?.number ?? 0).formatted() + "%").font(.caption).foregroundStyle(RenderTheme.muted)
        }.accessibilityElement(children: .combine)
    }
    private var rating: some View {
        HStack(spacing: 6) {
            ForEach(0..<5) { index in
                StarShape().fill(RenderTheme.neutral).frame(width: 16, height: 16)
                    .overlay {
                        StarShape().fill(accent).mask(alignment: .leading) {
                            Rectangle().frame(width: 16 * min(1, max(0, (p["value"]?.number ?? 0) - Double(index))))
                        }
                    }
            }
            Text((p["value"]?.number ?? 0).formatted(.number.precision(.fractionLength(1)))).font(.subheadline.weight(.medium))
            if let count = p["count"]?.number { Text("(\(Int(count)))").font(.caption).foregroundStyle(RenderTheme.muted) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("评分 \((p["value"]?.number ?? 0).formatted())，满分 5")
    }
    private var callout: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon = p["icon"]?.string {
                Image("lucide-" + icon, bundle: .module).resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(tone).accessibilityHidden(true)
            } else { RoundedRectangle(cornerRadius: 2).fill(tone).frame(width: 3) }
            VStack(alignment: .leading, spacing: 4) {
                if let title = p["title"]?.string { Text(title).font(.subheadline.weight(.semibold)) }
                Text(p["content"]?.text ?? "").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(tone.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
    private var tags: some View {
        RenderWrapLayout(spacing: 8) {
            ForEach(Array((p["tags"]?.array ?? []).enumerated()), id: \.offset) { _, tag in
                Text(tag.text).font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RenderTheme.neutral, in: Capsule())
            }
        }
    }
    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array((p["items"]?.array ?? []).enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    if p["style"] == .string("numbered") { Text("\(index + 1).").foregroundStyle(RenderTheme.muted).monospacedDigit() }
                    else if p["style"] != .string("plain") { Circle().fill(accent).frame(width: 5, height: 5).padding(.top, 7) }
                    Text(item.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private var code: some View {
        RenderCodeBlock(language: p["language"]?.string, code: p["code"]?.string ?? "")
    }
    private var accordion: some View {
        VStack(spacing: 0) {
            ForEach(Array(context.node.children.enumerated()), id: \.element.id) { index, child in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        context.session.setFocus(nil)
                        withAnimation(reduceMotion ? nil : RenderMotion.indicator) {
                            if expanded.contains(index) { expanded.remove(index) }
                            else { if p["multiple"] != .bool(true) { expanded.removeAll() }; expanded.insert(index) }
                        }
                    } label: {
                        HStack {
                            Text(labels.indices.contains(index) ? labels[index] : "").frame(maxWidth: .infinity, alignment: .leading)
                            ChevronShape().stroke(RenderTheme.muted, style: StrokeStyle(lineWidth: 1.6, lineCap: .round)).frame(width: 10, height: 6)
                                .rotationEffect(.degrees(expanded.contains(index) ? 180 : 0))
                        }.padding(.vertical, 16).contentShape(Rectangle())
                    }.buttonStyle(RenderPlainButtonStyle()).accessibilityValue(expanded.contains(index) ? "已展开" : "已折叠")
                    if expanded.contains(index) { context.renderChild(child).padding(.bottom, 16).transition(.opacity.combined(with: .move(edge: .top))) }
                }
                if index < context.node.children.count - 1 { Rectangle().fill(RenderTheme.border).frame(height: 1) }
            }
        }.padding(.horizontal, 16).background(RenderTheme.surface, in: RoundedRectangle(cornerRadius: 20)).clipped()
            .sensoryFeedback(.selection, trigger: expanded)
    }
    private var tabs: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                        Button {
                            context.session.setFocus(nil)
                            withAnimation(reduceMotion ? nil : RenderMotion.indicator) { selected = index }
                        } label: {
                            Text(label).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
                                .foregroundStyle(selected == index ? accent : RenderTheme.muted)
                                .background {
                                    // One capsule slides to the chosen tab.
                                    if selected == index { Capsule().fill(RenderTheme.surface).matchedGeometryEffect(id: "tab-pill", in: tabPill) }
                                }
                        }.buttonStyle(RenderPlainButtonStyle()).accessibilityAddTraits(selected == index ? .isSelected : [])
                    }
                }.padding(4).background(RenderTheme.neutral, in: Capsule())
            }.scrollIndicators(.hidden)
                .sensoryFeedback(.selection, trigger: selected)
            ForEach(Array(context.node.children.enumerated()), id: \.element.id) { index, child in
                if index == selected { context.renderChild(child).transition(.opacity) }
            }
        }
    }
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((p["steps"]?.array ?? []).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Circle().fill(step.object?["status"] == .string("completed") ? accent : RenderTheme.neutral).frame(width: 12, height: 12)
                        if index < (p["steps"]?.array?.count ?? 0) - 1 { Rectangle().fill(RenderTheme.border).frame(width: 1).frame(minHeight: 32) }
                    }.padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.object?["title"]?.text ?? "").font(.subheadline.weight(.medium))
                        if let detail = step.object?["description"]?.string { Text(detail).font(.subheadline).foregroundStyle(RenderTheme.muted) }
                        if let image = step.object?["image"]?.object { RenderMediaPreview(image: image) }
                    }.padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: .init(x: rect.minX, y: rect.minY)); p.addLine(to: .init(x: rect.midX, y: rect.maxY)); p.addLine(to: .init(x: rect.maxX, y: rect.minY)) }
    }
}
private struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            for point in 0..<10 {
                let angle = Double(point) * .pi / 5 - .pi / 2
                let radius = Double(min(rect.width, rect.height)) * (point.isMultiple(of: 2) ? 0.5 : 0.22)
                let position = CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius)
                if point == 0 { p.move(to: position) } else { p.addLine(to: position) }
            }
            p.closeSubpath()
        }
    }
}
