import SwiftUI
import AgentRendererCore

@MainActor
struct CompositionComponent: View {
    static let types = ["ItemCard", "ItemCardGroup", "Dashboard", "SwitchGroup", "Followup", "ListBlock", "Diagram"]
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var p: [String: JSONValue] { context.node.props }
    var body: some View {
        Group {
            switch context.node.type {
            case "Diagram": diagram
            case "ListBlock": listBlock
            case "ItemCard": item
            case "Followup": followup
            default: container
            }
        }
    }
    @ViewBuilder private var diagram: some View {
        if let props = try? DiagramData.parse(p["chart"]?.text ?? "") {
            FlowchartComponent(context: context, overrideProps: props)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("暂时无法绘制此图示").font(.subheadline.weight(.medium))
                Text("支持 flowchart TD／LR、方框、圆角节点、判断节点和箭头连线。").font(.caption).foregroundStyle(RenderTheme.muted)
                Text(p["chart"]?.text ?? "").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            }.padding(16).background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private var listBlock: some View {
        VStack(spacing: 0) {
            ForEach(Array((p["items"]?.array ?? []).enumerated()), id: \.offset) { index, item in
                if index > 0 { Rectangle().fill(RenderTheme.border).frame(height: 1) }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.object?["label"]?.text ?? "").font(.subheadline.weight(.medium))
                        if let description = item.object?["description"]?.string { Text(description).font(.caption).foregroundStyle(RenderTheme.muted) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let value = item.object?["value"] { Text(value.text).font(.subheadline).foregroundStyle(RenderTheme.muted) }
                }.padding(14).accessibilityElement(children: .combine)
            }
        }.background(RenderTheme.surface, in: RoundedRectangle(cornerRadius: 20)).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private var container: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title = p["title"]?.string { Text(title).font(.system(size: 14, weight: .medium)) }
            if let description = p["description"]?.string { Text(description).font(.subheadline).foregroundStyle(RenderTheme.muted) }
            switch p["layout"]?.string {
            case "grid": LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], alignment: .leading, spacing: 12) { context.children }
            case "horizontal": ScrollView(.horizontal) { HStack(alignment: .top, spacing: 12) { ForEach(context.node.children) { context.renderChild($0).frame(width: 260) } } }.scrollIndicators(.hidden)
            default: VStack(alignment: .leading, spacing: 12) { context.children }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var itemContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if let leading = context.slots["leading"] { leading }
            context.children.frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = context.slots["trailing"] { trailing }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(p["selected"] == .bool(true) ? accent.opacity(0.08) : RenderTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(p["selected"] == .bool(true) ? accent.opacity(0.4) : RenderTheme.border.opacity(0.5), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 20))
    }
    private var itemContainsControls: Bool {
        func interactive(_ node: ResolvedNode) -> Bool {
            if !node.bindings.isEmpty || ["Button", "Followup", "Tabs", "Accordion", "Image", "Map", "ItemCard"].contains(node.type) { return true }
            return node.children.contains(where: interactive) || node.slots.values.joined().contains(where: interactive)
        }
        return context.node.children.contains(where: interactive) || context.node.slots.values.joined().contains(where: interactive)
    }
    private var itemDisabled: Bool { p["disabled"] == .bool(true) || context.session.pendingInstances.contains(context.node.id) }
    private func activateItem() { guard !itemDisabled else { return }; context.session.setFocus(nil); context.emit("press") }
    @ViewBuilder private var item: some View {
        if context.session.canEmit(node: context.node, event: "press") {
            if itemContainsControls {
                HStack(spacing: 8) {
                    itemContent
                    Button(action: activateItem) {
                        Image("lucide-chevron-right", bundle: .module).resizable().scaledToFit().frame(width: 16, height: 16).frame(width: 36, height: 44)
                    }.buttonStyle(RenderPlainButtonStyle()).accessibilityLabel("打开项目").disabled(itemDisabled)
                }.opacity(itemDisabled ? RenderTheme.disabledOpacity : 1)
            } else {
                Button(action: activateItem) { itemContent }
                    .buttonStyle(RenderPlainButtonStyle()).disabled(itemDisabled)
                    .accessibilityAddTraits(p["selected"] == .bool(true) ? .isSelected : [])
            }
        } else { itemContent.opacity(itemDisabled ? RenderTheme.disabledOpacity : 1) }
    }
    private var followup: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((p["prompts"]?.array ?? []).enumerated()), id: \.offset) { index, prompt in
                Button { Task { await context.session.chooseFollowup(instanceId: context.node.id, index: index) } } label: {
                    HStack(spacing: 10) {
                        Text(prompt.text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        Image("lucide-arrow-up", bundle: .module).resizable().scaledToFit().frame(width: 14, height: 14).rotationEffect(.degrees(45))
                    }.padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(accent)
                        .background(RenderTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(RenderTheme.border, lineWidth: 1) }
                }.buttonStyle(RenderPlainButtonStyle())
                    .disabled(!context.session.pendingInstances.isEmpty || !context.session.canEmit(node: context.node, event: "press"))
                    .animation(reduceMotion ? nil : RenderMotion.feedback, value: context.session.pendingInstances)
            }
        }
    }
}
