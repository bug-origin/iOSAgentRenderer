import SwiftUI
import AgentRendererCore

public struct RenderInputAppearance: Sendable {
    public let minHeight: CGFloat
    public let cornerRadius: CGFloat
    public init(minHeight: CGFloat = 48, cornerRadius: CGFloat = 12) {
        self.minHeight = minHeight; self.cornerRadius = cornerRadius
    }
}
private struct RenderInputAppearanceKey: EnvironmentKey {
    static let defaultValue = RenderInputAppearance()
}
extension EnvironmentValues {
    var renderInputAppearance: RenderInputAppearance {
        get { self[RenderInputAppearanceKey.self] }
        set { self[RenderInputAppearanceKey.self] = newValue }
    }
}

struct InputSurface: ViewModifier {
    let focused: Bool
    let invalid: Bool
    @Environment(\.renderInputAppearance) private var appearance
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: appearance.cornerRadius)
        content.background(RenderTheme.secondary, in: shape)
        .overlay(shape.strokeBorder(invalid ? RenderTheme.danger : accent,
                                    lineWidth: focused || invalid ? 1.5 : 0).allowsHitTesting(false))
        .opacity(enabled ? 1 : RenderTheme.disabledOpacity)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: focused)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: invalid)
    }
}

@MainActor
struct InputComponent: View {
    let context: ComponentRenderContext
    var multiline = false
    @Environment(\.renderInputAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    private var error: String? { context.node.bindings["value"].flatMap { context.session.validationErrors[$0] } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(context: context)
            Group {
                if multiline {
                    ZStack(alignment: .topLeading) {
                        if binding.wrappedValue.isEmpty {
                            Text(context.node.props["placeholder"]?.text ?? "")
                                .foregroundStyle(RenderTheme.muted).padding(.horizontal, 5).padding(.vertical, 8)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        TextEditor(text: binding).scrollContentBackground(.hidden)
                            .focused($focused)
                            .frame(height: CGFloat(context.node.props["rows"]?.number ?? 4) * 24 + 32)
                            .accessibilityLabel(context.node.props["label"]?.text ?? "")
                    }.padding(.horizontal, 7)
                } else {
                    TextField("", text: binding, prompt: Text(context.node.props["placeholder"]?.text ?? "").foregroundStyle(RenderTheme.muted))
                        .textFieldStyle(.plain).focused($focused).submitLabel(.done)
                        .onSubmit { context.session.setFocus(nil) }
                        .accessibilityLabel(context.node.props["label"]?.text ?? "")
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .frame(minHeight: appearance.minHeight)
                }
            }
            .font(.system(size: 14)).foregroundStyle(RenderTheme.foreground)
            .modifier(InputSurface(focused: focused, invalid: error != nil))
            .disabled(context.node.props["disabled"] == .bool(true))
            .onChange(of: focused) { _, value in
                if value { context.session.setFocus(context.node.id) }
                else if context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) }
            }
            .onChange(of: context.session.focusedInstanceId) { _, value in focused = value == context.node.id }
            .onChange(of: context.node.props["disabled"]) { _, value in
                if value == .bool(true), context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) }
            }
            .onDisappear { if context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) } }
            if let error { FieldError(message: error) }
        }.animation(reduceMotion ? nil : error == nil ? RenderMotion.errorOut : RenderMotion.errorIn, value: error)
    }
    private var binding: Binding<String> {
        Binding(get: {
            guard let pointer = context.node.bindings["value"] else { return "" }
            return (try? context.session.state.value(at: pointer).text) ?? ""
        }, set: { value in
            guard let pointer = context.node.bindings["value"] else { return }
            context.session.setInput(.string(value), at: pointer)
        })
    }
}

@MainActor
struct SelectComponent: View {
    let context: ComponentRenderContext
    @State private var choosing = false
    @Environment(\.renderInputAppearance) private var appearance
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var options: [JSONValue] { context.node.props["options"]?.array ?? [] }
    private var value: String {
        guard let path = context.node.bindings["value"] else { return "" }
        return (try? context.session.state.value(at: path).text) ?? ""
    }
    private var error: String? { context.node.bindings["value"].flatMap { context.session.validationErrors[$0] } }
    private var label: String { context.node.props["label"]?.text ?? "" }
    private var selectedLabel: String { options.first { $0.object?["value"]?.text == value }?.object?["label"]?.text ?? "请选择" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(context: context)
            Button {
                context.session.setFocus(context.node.id)
                choosing = true
            } label: {
                HStack {
                    Text(selectedLabel).foregroundStyle(value.isEmpty ? RenderTheme.muted : RenderTheme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Path { path in
                        path.move(to: CGPoint(x: 3, y: 6)); path.addLine(to: CGPoint(x: 8, y: 11))
                        path.addLine(to: CGPoint(x: 13, y: 6))
                    }.stroke(RenderTheme.muted, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 16).rotationEffect(.degrees(choosing ? -180 : 0)).animation(reduceMotion ? nil : RenderMotion.indicator, value: choosing)
                        .accessibilityHidden(true)
                }.font(.system(size: 14)).padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: appearance.minHeight)
                    .contentShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
            }.buttonStyle(RenderPlainButtonStyle())
                .modifier(InputSurface(focused: choosing, invalid: error != nil))
                .accessibilityLabel(label).accessibilityValue(selectedLabel)
                .renderSheet(isPresented: $choosing, height: min(CGFloat(options.count) * 58 + 96, 560)) {
                    VStack(spacing: 0) {
                        RenderSheetTitle(title: label)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(options, id: \.self.textIdentity) { option in
                                    let optionValue = option.object?["value"]?.text ?? ""
                                    RenderSheetOption(
                                        title: option.object?["label"]?.text ?? "", selected: value == optionValue
                                    ) {
                                        if let path = context.node.bindings["value"] {
                                            context.session.setInput(.string(optionValue), at: path)
                                        }
                                        choosing = false
                                    }
                                }
                            }.padding(.horizontal, 16).padding(.bottom, 16)
                        }
                    }.tint(accent)
                }
                .onChange(of: choosing) { _, presented in
                    if !presented, context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) }
                }
                .onChange(of: context.session.focusedInstanceId) { _, id in
                    if id != context.node.id { choosing = false }
                }
                .onChange(of: context.node.props["disabled"]) { _, disabled in
                    if disabled == .bool(true) {
                        choosing = false
                        if context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) }
                    }
                }
                .disabled(context.node.props["disabled"] == .bool(true))
                .onDisappear { if context.session.focusedInstanceId == context.node.id { context.session.setFocus(nil) } }
            if let error { FieldError(message: error) }
        }
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: choosing)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: value)
        .sensoryFeedback(.selection, trigger: value)
        .animation(reduceMotion ? nil : error == nil ? RenderMotion.errorOut : RenderMotion.errorIn, value: error)
    }
}

struct FieldError: View {
    let message: String
    var body: some View {
        Text(message).font(.system(size: 14)).foregroundStyle(RenderTheme.danger)
            .padding(.horizontal, 6).transition(.opacity)
    }
}
private extension JSONValue {
    var textIdentity: String { object?["value"]?.text ?? text }
}
