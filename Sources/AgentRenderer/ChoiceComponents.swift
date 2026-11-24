import SwiftUI
import AgentRendererCore

private struct ControlLifecycle: ViewModifier {
    let context: ComponentRenderContext
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused)
            .onChange(of: focused) { _, value in
                if value { context.session.setFocus(context.node.id) }
                else if context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) }
            }
            .onChange(of: context.session.focusedInstanceId) { _, id in if id != context.node.id { focused = false } }
            .onDisappear { if context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) } }
    }
}

private struct ControlLabel: View {
    let context: ComponentRenderContext
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(context: context)
            if let description = context.node.props["description"]?.string {
                Text(description).font(.caption).foregroundStyle(RenderTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct BooleanControlComponent: View {
    let context: ComponentRenderContext
    var checkbox = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderAccent) private var accent
    @State private var feedback = 0
    private var value: Bool { context.node.props["value"]?.bool ?? false }
    private var binding: Binding<Bool> {
        Binding(get: { value }, set: { next in
            feedback += 1
            context.session.setFocus(context.node.id)
            context.session.setControlValue(.bool(next), instanceId: context.node.id)
            context.session.setFocus(nil)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if checkbox {
                Toggle(isOn: binding) {
                    HStack(spacing: 10) {
                        Image(value ? "lucide-check" : "lucide-plus", bundle: .module).resizable().scaledToFit().frame(width: 16, height: 16)
                        ControlLabel(context: context)
                    }.padding(.vertical, 6)
                }.toggleStyle(.button).buttonStyle(.bordered).tint(accent)
            } else {
                Toggle(isOn: binding) { ControlLabel(context: context) }.toggleStyle(.switch).tint(accent).frame(minHeight: 48)
            }
            if let path = context.node.bindings["value"], let error = context.session.validationErrors[path] { FieldError(message: error) }
        }.animation(reduceMotion ? nil : RenderMotion.feedback, value: value)
            .modifier(ControlLifecycle(context: context)).disabled(context.node.props["disabled"] == .bool(true))
            .sensoryFeedback(.selection, trigger: feedback)
    }
}

@MainActor
struct RadioComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedback = 0
    private var value: String { context.node.props["value"]?.string ?? "" }
    private var options: [[String: JSONValue]] { (context.node.props["options"]?.array ?? []).compactMap(\.object) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ControlLabel(context: context)
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let optionValue = option["value"]?.string ?? ""
                let checked = value == optionValue
                Button {
                    feedback += 1
                    context.session.setFocus(context.node.id)
                    withAnimation(reduceMotion ? nil : RenderMotion.feedback) {
                        context.session.setControlValue(.string(optionValue), instanceId: context.node.id)
                    }
                    context.session.setFocus(nil)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(checked ? accent.opacity(0.1) : RenderTheme.surface)
                            Circle().strokeBorder(checked ? accent : RenderTheme.border, lineWidth: checked ? 2 : 1.5)
                            Circle().fill(accent.gradient).padding(6).scaleEffect(checked ? 1 : 0.01).opacity(checked ? 1 : 0)
                        }.frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option["label"]?.text ?? "").font(.subheadline.weight(.medium)).foregroundStyle(RenderTheme.foreground)
                            if let detail = option["description"]?.string { Text(detail).font(.caption).foregroundStyle(RenderTheme.muted) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(14).frame(minHeight: 52)
                        .background(checked ? accent.opacity(0.07) : RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(checked ? accent.opacity(0.5) : RenderTheme.border, lineWidth: 1) }
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(RenderPlainButtonStyle())
                    .disabled(option["disabled"] == .bool(true))
                    .opacity(option["disabled"] == .bool(true) ? 0.45 : 1)
                    .accessibilityAddTraits(checked ? .isSelected : [])
                    .accessibilityLabel(option["label"]?.text ?? "")
                    .accessibilityHint(option["description"]?.text ?? "")
                    .accessibilityValue(checked ? "已选择" : "未选择")
            }
            if let path = context.node.bindings["value"], let error = context.session.validationErrors[path] { FieldError(message: error) }
        }.animation(reduceMotion ? nil : RenderMotion.feedback, value: value)
            .modifier(ControlLifecycle(context: context)).disabled(context.node.props["disabled"] == .bool(true))
            .sensoryFeedback(.selection, trigger: feedback)
    }
}

@MainActor
struct SliderComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    private var value: Double { context.node.props["value"]?.number ?? 0 }
    private var range: SliderRange? { try? SliderRange(props: context.node.props) }
    private func display(_ number: Double) -> String { number.formatted(.number.precision(.fractionLength(0...3))) + (context.node.props["unit"]?.string ?? "") }
    var body: some View {
        if let range {
            VStack(alignment: .leading, spacing: 8) {
                HStack { FieldLabel(context: context); Spacer(); Text(display(value)).font(.caption.monospacedDigit()).foregroundStyle(RenderTheme.muted).contentTransition(.numericText(value: value)) }
                Slider(value: Binding(get: { value }, set: {
                    context.session.setControlValue(.number(range.snapped($0)), instanceId: context.node.id, emitChange: false)
                }), in: range.min...range.max, step: range.step, onEditingChanged: { editing in
                    if editing { context.session.setFocus(context.node.id) }
                    else {
                        context.session.setControlValue(.number(range.snapped(value)), instanceId: context.node.id)
                        context.session.setFocus(nil)
                    }
                }).tint(accent).accessibilityLabel(context.node.props["label"]?.text ?? "滑块").accessibilityValue(display(value))
                HStack { Text(display(range.min)); Spacer(); Text(display(range.max)) }.font(.caption).foregroundStyle(RenderTheme.muted)
                if let description = context.node.props["description"]?.string { Text(description).font(.caption).foregroundStyle(RenderTheme.muted) }
                if let path = context.node.bindings["value"], let error = context.session.validationErrors[path] { FieldError(message: error) }
            }.modifier(ControlLifecycle(context: context)).disabled(context.node.props["disabled"] == .bool(true))
                .sensoryFeedback(.selection, trigger: value)
        }
    }
}
