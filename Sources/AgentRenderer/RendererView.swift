import Charts
import SwiftUI
import AgentRendererCore

@MainActor
public struct ComponentRenderContext {
    public let node: ResolvedNode
    public let children: AnyView
    public let slots: [String: AnyView]
    public let session: RendererSession
    public let renderChild: @MainActor (ResolvedNode) -> AnyView
    public func emit(_ event: String) { Task { await session.emit(instanceId: node.id, event: event) } }
}

@MainActor
public struct ComponentRegistry {
    public typealias Builder = @MainActor (ComponentRenderContext) -> AnyView
    private var builders: [String: Builder] = [:]
    public init() {}
    public mutating func register(_ type: String, builder: @escaping Builder) throws {
        guard builders[type] == nil else { throw RendererError("Duplicate SwiftUI registration: \(type)") }
        builders[type] = builder
    }
    public func render(_ context: ComponentRenderContext) -> AnyView? { builders[context.node.type]?(context) }
    public var types: Set<String> { Set(builders.keys) }

    /// Customize a registered component's appearance without changing its protocol definition.
    public func overriding(_ type: String, builder: @escaping Builder) throws -> ComponentRegistry {
        guard builders[type] != nil else { throw RendererError("Unknown SwiftUI registration: \(type)") }
        var registry = self
        registry.builders[type] = builder
        return registry
    }

    public static func standard() -> ComponentRegistry {
        var registry = ComponentRegistry()
        registry.builders = [
            "ComposedChart": { AnyView(ComposedChartComponent(context: $0)) },
            "SunburstChart": { AnyView(HierarchyChartComponent(context: $0)) },
            "SankeyChart": { AnyView(HierarchyChartComponent(context: $0)) },
            "MusicPlayer": { AnyView(MusicPlayerComponent(context: $0)) },
            "Weather": { AnyView(WeatherComponent(context: $0)) },
            "Map": { AnyView(MapComponent(context: $0)) },
            "Card": { AnyView(CardComponent(context: $0)) },
            "Stack": { context in
                AnyView(VStack(alignment: .leading, spacing: spacing(context.node)) { context.children }.frame(maxWidth: .infinity, alignment: .leading))
            },
            "Grid": { AnyView(RendererGrid(context: $0)) },
            "ActionGroup": { context in
                AnyView(ViewThatFits(in: .horizontal) {
                    HStack(spacing: spacing(context.node)) { context.children }
                    VStack(alignment: .leading, spacing: spacing(context.node)) { context.children }
                })
            },
            "Text": { context in
                AnyView(Text(context.node.props["text"]?.text ?? "")
                    .font(context.node.props["variant"] == .string("heading") ? .headline : context.node.props["variant"] == .string("caption") ? .caption : .subheadline)
                    .foregroundStyle(context.node.props["variant"] == .string("caption") ? RenderTheme.muted : RenderTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true))
            },
            "Metric": { context in
                AnyView(VStack(alignment: .leading, spacing: 4) {
                    Text(context.node.props["label"]?.text ?? "")
                        .font(.caption.weight(.medium)).foregroundStyle(RenderTheme.muted)
                    Text(context.node.props["value"]?.text ?? "")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(RenderTheme.foreground).contentTransition(.numericText())
                }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine))
            },
            "Badge": { AnyView(BadgeComponent(context: $0)) },
            "Button": { AnyView(ActionButton(context: $0)) },
            "TextField": { AnyView(InputComponent(context: $0)) },
            "TextArea": { AnyView(InputComponent(context: $0, multiline: true)) },
            "Steps": { AnyView(StepsComponent(context: $0)) },
            "Select": { AnyView(SelectComponent(context: $0)) },
            "Slider": { AnyView(SliderComponent(context: $0)) },
            "Switch": { AnyView(BooleanControlComponent(context: $0)) },
            "Checkbox": { AnyView(BooleanControlComponent(context: $0, checkbox: true)) },
            "Radio": { AnyView(RadioComponent(context: $0)) },
            "Form": { context in AnyView(VStack(alignment: .leading, spacing: spacing(context.node)) { context.children }) },
            "Chart": { AnyView(ChartComponent(context: $0)) },
            "Flowchart": { AnyView(FlowchartComponent(context: $0)) },
            "Table": { AnyView(TableComponent(context: $0)) },
        ]
        for type in CompositionComponent.types {
            registry.builders[type] = { AnyView(CompositionComponent(context: $0)) }
        }
        for type in ExtendedInput.types {
            registry.builders[type] = { AnyView(ExtendedInputComponent(context: $0)) }
        }
        for type in InformationData.types {
            registry.builders[type] = { AnyView(DataDisplayComponent(context: $0)) }
        }
        for type in AdvancedChartData.types {
            registry.builders[type] = { AnyView(AdvancedChartComponent(context: $0)) }
        }
        for type in InformationComponent.types {
            registry.builders[type] = { AnyView(InformationComponent(context: $0)) }
        }
        return registry
    }
}

private struct RenderAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}
extension EnvironmentValues {
    var renderAccent: Color {
        get { self[RenderAccentKey.self] }
        set { self[RenderAccentKey.self] = newValue }
    }
}

extension EnvironmentValues {
    @Entry var renderEntranceDelay: Double = 0
}

@MainActor
public struct RendererView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let session: RendererSession
    private let registry: ComponentRegistry
    private let accent: Color
    private let onEntranceComplete: (() -> Void)?
    private let entranceDelay: Double
    private let inputAppearance: RenderInputAppearance
    public init(session: RendererSession, registry: ComponentRegistry = .standard(), accent: Color = .accentColor, inputAppearance: RenderInputAppearance = .init(), entranceDelay: Double = 0, onEntranceComplete: (() -> Void)? = nil) {
        self.onEntranceComplete = onEntranceComplete
        self.entranceDelay = min(2.5, max(0, entranceDelay))
        self.session = session; self.registry = registry; self.accent = accent; self.inputAppearance = inputAppearance
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = session.errorMessage { Text(error).foregroundStyle(RenderTheme.danger).accessibilityLabel("界面错误：" + error) }
            if let root = session.root { render(root) }
            if let result = session.outcome {
                HStack(spacing: 8) {
                    Image("lucide-" + (result.status == .completed ? "circle-check" : "circle-help"), bundle: .module)
                        .resizable().scaledToFit().frame(width: 17, height: 17).accessibilityHidden(true)
                    Text(result.message).font(.callout)
                }.foregroundStyle(RenderTheme.muted)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }
        }
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { session.setFocus(nil) }
        }
        .overlayPreferenceValue(ChartEntrancePending.self) { pending in
            if let onEntranceComplete {
                Color.clear.allowsHitTesting(false).task(id: pending) {
                    guard !pending else { return }
                    // Allow the card to settle and descendants to register their plot entrances.
                    if !reduceMotion {
                        do { try await Task.sleep(for: .milliseconds(260)) } catch { return }
                    }
                    onEntranceComplete()
                }
            }
        }
        .font(.system(size: 14)).foregroundStyle(RenderTheme.foreground)
        .tint(accent)
        .environment(\.renderEntranceDelay, entranceDelay)
        .environment(\.renderAccent, accent)
        .environment(\.renderInputAppearance, inputAppearance)
        #if os(iOS)
        .toolbar {
            if session.focusedInstanceId != nil {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { session.setFocus(nil) }
                }
            }
        }
        #endif
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: session.validationErrors)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: session.errorMessage)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: session.outcome)
        // Results are felt as well as seen; a failed submit buzzes once rather than per field.
        .sensoryFeedback(trigger: session.outcome) { _, outcome in
            switch outcome?.status {
            case .completed: .success
            case .rejected: .error
            default: nil
            }
        }
        .sensoryFeedback(.error, trigger: session.validationErrors.count) { old, new in new > old }
    }

    private func render(_ node: ResolvedNode) -> AnyView {
        let children = renderChildren(node.children)
        let slots = node.slots.mapValues(renderChildren)
        let context = ComponentRenderContext(node: node, children: children, slots: slots, session: session, renderChild: render)
        return registry.render(context) ?? AnyView(Text("当前客户端暂不支持此组件：" + node.type).foregroundStyle(.secondary))
    }

    private func renderChildren(_ nodes: [ResolvedNode]) -> AnyView {
        AnyView(ForEach(nodes) { node in
            render(node).accessibilityIdentifier(node.id)
        })
    }
}

private func spacing(_ node: ResolvedNode) -> CGFloat {
    switch node.props["spacing"]?.string { case "compact": 8; case "relaxed": 24; default: 16 }
}

private struct RendererGrid: View {
    let context: ComponentRenderContext
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var metricWidth: CGFloat = 136

    var body: some View {
        let metricsOnly = !context.node.children.isEmpty && context.node.children.allSatisfy { $0.type == "Metric" }
        let size: GridItem.Size = metricsOnly && typeSize.isAccessibilitySize
            ? .flexible(minimum: 0) : .adaptive(minimum: metricsOnly ? metricWidth : 180)
        let column = GridItem(size, spacing: metricsOnly ? spacing(context.node) : nil,
                              alignment: metricsOnly ? .topLeading : .leading)
        LazyVGrid(columns: [column], alignment: .leading, spacing: spacing(context.node)) { context.children }
    }
}

private struct BadgeComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    private var color: Color {
        switch context.node.props["tone"]?.string {
        case "success": RenderTheme.success
        case "warning": RenderTheme.warning
        case "danger": RenderTheme.danger
        case "accent": accent
        default: RenderTheme.muted
        }
    }
    var body: some View {
        Text(context.node.props["label"]?.text ?? "")
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .foregroundStyle(context.node.props["variant"] == .string("solid") ? Color.white : color)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(RenderTheme.surface)
                RoundedRectangle(cornerRadius: 16).fill(context.node.props["variant"] == .string("solid") ? color : context.node.props["variant"] == .string("outline") ? Color.clear : color.opacity(0.15))
                RoundedRectangle(cornerRadius: 16).strokeBorder(context.node.props["variant"] == .string("outline") ? color.opacity(0.35) : .clear, lineWidth: 1)
            }
    }
}

@MainActor
private struct CardComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderSurfaceDepth) private var depth
    var body: some View {
        let surface = RoundedRectangle(cornerRadius: RenderTheme.surfaceRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 16) {
            if let header = context.slots["header"] { header }
            else if let title = context.node.props["title"]?.string {
                Text(title)
                    .font(depth == 0 ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(RenderTheme.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            context.children.environment(\.renderSurfaceDepth, depth + 1)
            if let footer = context.slots["footer"] { footer }
        }
        .padding(depth == 0 ? 16 : 0).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if depth == 0 && context.node.props["variant"] != .string("clear") {
                surface.fill(RenderTheme.surface).modifier(RenderShadow())
            }
        }
        .overlay {
            if context.node.props["variant"] == .string("outline") {
                surface.strokeBorder(RenderTheme.border, lineWidth: 1).allowsHitTesting(false)
            }
        }
    }
}

/// One motion vocabulary for native controls, validation and rendered data.
// RenderMotion supplies the shared animation curves.
extension RenderMotion {
    /// Loaded remote images fade in rather than popping over their placeholder.
    static func imageLoad(_ reduceMotion: Bool) -> Transaction { Transaction(animation: reduceMotion ? nil : feedback) }
}

struct FieldLabel: View {
    let context: ComponentRenderContext
    @Environment(\.isEnabled) private var enabled
    private var invalid: Bool {
        context.node.bindings["value"].flatMap { context.session.validationErrors[$0] } != nil
    }
    var body: some View {
        HStack(spacing: 4) {
            Text(context.node.props["label"]?.text ?? "")
            if context.node.props["required"] == .bool(true) { Text("*").foregroundStyle(RenderTheme.danger) }
        }.font(.system(size: 14, weight: .medium))
            .foregroundStyle(invalid ? RenderTheme.danger : RenderTheme.foreground)
            .opacity(enabled && context.node.props["disabled"] != .bool(true) ? 1 : RenderTheme.disabledOpacity)
    }
}

@MainActor
private struct ActionButton: View {
    let context: ComponentRenderContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var pending: Bool { context.session.pendingInstances.contains(context.node.id) }
    private var primary: Bool { context.node.props["variant"] != .string("secondary") }
    var body: some View {
        button.buttonStyle(RenderButtonStyle(primary: primary, variant: context.node.props["variant"]?.string))
        .disabled(context.node.props["disabled"] == .bool(true) || pending
                  || !context.session.canEmit(node: context.node, event: "press"))
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: pending)
    }
    private var button: some View {
        Button { context.session.setFocus(nil); context.emit("press") } label: {
            HStack(spacing: 8) {
                if pending { ProgressView().controlSize(.small).transition(.opacity) }
                else if let icon = context.node.props["icon"]?.string {
                    Image("lucide-" + icon, bundle: .module).resizable().scaledToFit().frame(width: 17, height: 17).accessibilityHidden(true)
                }
                Text(pending ? "提交中…" : (context.node.props["label"]?.text ?? ""))
                    .contentTransition(.opacity)
            }.frame(maxWidth: .infinity)
        }
    }
}
