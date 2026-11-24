import SwiftUI
import AgentRendererCore

@MainActor
struct ExtendedInputComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent
    @Environment(\.renderInputAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var keyboardFocus: Bool
    @State private var choosing = false
    @State private var search = ""
    @State private var draft = ""
    init(context: ComponentRenderContext) {
        self.context = context
        _draft = State(initialValue: context.node.props["value"]?.text ?? "")
    }
    private var p: [String: JSONValue] { context.node.props }
    private var kind: String { context.node.type }
    private var label: String { p["label"]?.text ?? "" }
    private var focused: Bool { context.session.focusedInstanceId == context.node.id }
    private var error: String? { context.node.bindings["value"].flatMap { context.session.validationErrors[$0] } }
    private var selected: [JSONValue] { p["value"]?.array ?? [] }
    private var options: [[String: JSONValue]] { (p["options"]?.array ?? []).compactMap(\.object) }
    private var disabled: Bool { p["disabled"] == .bool(true) || !context.session.pendingInstances.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(context: context)
            Group {
                switch kind {
                case "NumberField": number
                case "DatePicker", "TimeField", "DateRangePicker": dateButton
                case "CheckboxGroup", "ToggleGroup": choices
                default: comboButton
                }
            }.disabled(disabled)
            if let description = p["description"]?.string { Text(description).font(.caption).foregroundStyle(RenderTheme.muted).padding(.horizontal, 6) }
            if let error { FieldError(message: error) }
        }.animation(reduceMotion ? nil : RenderMotion.feedback, value: error)
            .animation(reduceMotion ? nil : RenderMotion.indicator, value: selected)
            .sensoryFeedback(.selection, trigger: selected)
            .onChange(of: keyboardFocus) { _, value in
                if value { context.session.setFocus(context.node.id) }
                else if !choosing && focused { context.session.setFocus(nil) }
            }
            .onChange(of: context.session.focusedInstanceId) { _, id in
                if id != context.node.id { keyboardFocus = false; choosing = false }
            }
            .onChange(of: disabled) { _, value in if value && focused { context.session.setFocus(nil) } }
            .onDisappear { if focused { context.session.setFocus(nil) } }

    }
    private func update(_ value: JSONValue) {
        guard !disabled else { return }
        context.session.setFocus(context.node.id)
        context.session.setControlValue(value, instanceId: context.node.id)
    }
    private func restoreDraft() { draft = p["value"]?.text ?? "" }
    private var number: some View {
        HStack(spacing: 8) {
            TextField(label, text: $draft).textFieldStyle(.plain).focused($keyboardFocus)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .onChange(of: draft) { _, text in
                    let parsed = Double(text.replacingOccurrences(of: ",", with: "."))
                    if keyboardFocus {
                        if let parsed, parsed.isFinite { context.session.setDraftError(nil, instanceId: context.node.id); update(.number(parsed)) }
                        else { context.session.setDraftError("请输入有效数字", instanceId: context.node.id) }
                    }
                }.accessibilityLabel(label)
            Button { increment(-1) } label: { Text("−").font(.title3).frame(width: 32, height: 32) }.buttonStyle(RenderPlainButtonStyle()).accessibilityLabel("减少" + label)
            Rectangle().fill(RenderTheme.border).frame(width: 1, height: 20)
            Button { increment(1) } label: { Text("+").font(.title3).frame(width: 32, height: 32) }.buttonStyle(RenderPlainButtonStyle()).accessibilityLabel("增加" + label)
        }.padding(.horizontal, 12).frame(minHeight: appearance.minHeight)
            .modifier(InputSurface(focused: focused, invalid: error != nil))
            .onChange(of: p["value"]) { _, _ in if !keyboardFocus { restoreDraft() } }
    }
    private func increment(_ direction: Double) {
        let value = p["value"]?.number ?? 0, step = p["step"]?.number ?? 1
        let next = min(p["max"]?.number ?? 1e12, max(p["min"]?.number ?? -1e12, value + direction * step))
        context.session.setDraftError(nil, instanceId: context.node.id)
        update(.number(next)); draft = next.formatted(.number.grouping(.never))
    }
    private var dateButton: some View {
        Button { context.session.setFocus(context.node.id); choosing = true } label: {
            HStack {
                Text(dateDisplay).foregroundStyle(dateDisplay == "请选择" ? RenderTheme.muted : RenderTheme.foreground)
                Spacer()
                Image("lucide-clock", bundle: .module).resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(accent)
            }.padding(.horizontal, 14).frame(minHeight: appearance.minHeight).contentShape(Rectangle())
        }.buttonStyle(RenderPlainButtonStyle()).modifier(InputSurface(focused: focused, invalid: error != nil))
            .accessibilityLabel(label).accessibilityValue(dateDisplay)
            .renderSheet(isPresented: $choosing, height: kind == "DateRangePicker" ? 440 : 330, onDismiss: {
                // Wheels always show a value, so closing an untouched empty field keeps what was shown.
                if kind == "TimeField", p["value"] == .string("") { update(.string(ExtendedInput.string(ExtendedInput.localDefault(time: true), time: true))) }
                if kind == "DatePicker", p["value"] == .string("") { update(.string(RenderDateWheel.shown(""))) }
                if focused { context.session.setFocus(nil) }
            }) {
                VStack(spacing: 0) {
                    RenderSheetTitle(title: label)
                    switch kind {
                    case "DateRangePicker":
                        DateRangePanel(values: [0, 1].map { selected.indices.contains($0) ? selected[$0].text : "" }) { index, day in
                            var range = selected
                            guard range.indices.contains(index) else { return }
                            range[index] = .string(day)
                            update(.array(range))
                        }.padding(.horizontal, 16)
                    case "TimeField":
                        DatePicker("", selection: Binding(get: {
                            ExtendedInput.date(p["value"]?.string ?? "", time: true) ?? ExtendedInput.localDefault(time: true)
                        }, set: { update(.string(ExtendedInput.string($0, time: true))) }), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                            #if os(iOS)
                            .datePickerStyle(.wheel)
                            #endif
                            .frame(maxWidth: .infinity)
                    default:
                        RenderDateWheel(selection: p["value"]?.string ?? "") { update(.string($0)) }
                            .padding(.horizontal, 12)
                    }
                }.tint(accent)
            }
    }
    private var dateDisplay: String {
        if kind == "DateRangePicker" { let parts = selected.compactMap(\.string); return parts.allSatisfy(\.isEmpty) ? "请选择" : parts.map { $0.isEmpty ? "待选择" : $0 }.joined(separator: " 至 ") }
        return p["value"]?.string?.isEmpty == false ? p["value"]!.text : "请选择"
    }
    private var comboButton: some View {
        Button { context.session.setFocus(context.node.id); choosing = true } label: {
            HStack {
                Text(selectionDisplay).foregroundStyle(selected.isEmpty ? RenderTheme.muted : RenderTheme.foreground).lineLimit(2)
                Spacer()
                Image("lucide-chevron-down", bundle: .module).resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(RenderTheme.muted)
                    .rotationEffect(.degrees(choosing ? 180 : 0))
            }.padding(.horizontal, 14).frame(minHeight: appearance.minHeight).contentShape(Rectangle())
        }.buttonStyle(RenderPlainButtonStyle()).modifier(InputSurface(focused: focused, invalid: error != nil))
            .accessibilityLabel(label).accessibilityValue(selectionDisplay)
            .renderSheet(isPresented: $choosing, height: min(CGFloat(options.count) * 58 + (multiple ? 220 : 160), 600)) {
                VStack(spacing: 12) {
                    RenderSheetTitle(title: label).padding(.bottom, -14)
                    TextField("搜索选项", text: $search).textFieldStyle(.plain).padding(12)
                        .background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 12)).focused($keyboardFocus)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(filteredOptions.enumerated()), id: \.offset) { _, option in
                                let value = option["value"]!
                                RenderSheetOption(
                                    title: option["label"]!.text, detail: option["description"]?.string,
                                    selected: selected.contains(value), multiple: multiple
                                ) { toggle(value) }
                                .disabled(option["disabled"] == .bool(true))
                                .opacity(option["disabled"] == .bool(true) ? RenderTheme.disabledOpacity : 1)
                            }
                            if filteredOptions.isEmpty { Text("没有匹配选项").font(.caption).foregroundStyle(RenderTheme.muted).padding() }
                        }.padding(.horizontal, 16)
                    }
                    // Multiple choice needs an explicit end; a single choice closes as soon as it is made.
                    if multiple {
                        Button("完成") { choosing = false; context.session.setFocus(nil) }
                            .buttonStyle(RenderButtonStyle(primary: true)).padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }.tint(accent)
            }.onChange(of: choosing) { _, value in if !value && focused { context.session.setFocus(nil) }; if !value { search = "" } }
            .animation(reduceMotion ? nil : RenderMotion.feedback, value: choosing)
    }
    private var multiple: Bool { kind == "CheckboxGroup" || p["multiple"] == .bool(true) }
    private var filteredOptions: [[String: JSONValue]] {
        options.filter { search.isEmpty || $0["label"]!.text.localizedCaseInsensitiveContains(search) }
    }
    private func toggle(_ value: JSONValue) {
        let isSelected = selected.contains(value)
        let next = multiple ? (isSelected ? selected.filter { $0 != value } : selected + [value]) : (isSelected ? [] : [value])
        update(.array(next))
        if kind == "ComboBox" && !multiple { choosing = false; context.session.setFocus(nil) }
    }
    private var selectionDisplay: String {
        let labels = options.filter { selected.contains($0["value"]!) }.map { $0["label"]!.text }
        return labels.isEmpty ? "请选择" : labels.joined(separator: "、")
    }
    private var choices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: kind == "ToggleGroup" ? 90 : 220), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in optionButton(option) }
        }
    }
    private func optionButton(_ option: [String: JSONValue]) -> some View {
        let isSelected = selected.contains(option["value"]!)
        return Button {
            toggle(option["value"]!)
        } label: {
            HStack(spacing: 10) {
                if kind != "ToggleGroup" {
                    RoundedRectangle(cornerRadius: 6).fill(isSelected ? accent : RenderTheme.neutral).frame(width: 22, height: 22)
                        .overlay { if isSelected { Image("lucide-check", bundle: .module).resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(.white) } }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(option["label"]!.text).font(.subheadline.weight(.medium))
                    if let description = option["description"]?.string { Text(description).font(.caption).foregroundStyle(RenderTheme.muted) }
                }.frame(maxWidth: .infinity, alignment: kind == "ToggleGroup" ? .center : .leading)
            }.padding(12).frame(minHeight: 48).contentShape(RoundedRectangle(cornerRadius: 14))
                .background(isSelected ? accent.opacity(0.1) : RenderTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(isSelected ? accent.opacity(0.4) : RenderTheme.border, lineWidth: 1) }
        }.buttonStyle(RenderPlainButtonStyle()).disabled(option["disabled"] == .bool(true))
            .opacity(option["disabled"] == .bool(true) ? RenderTheme.disabledOpacity : 1)
            .foregroundStyle(isSelected ? accent : RenderTheme.foreground)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
