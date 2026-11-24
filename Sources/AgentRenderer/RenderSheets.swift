import SwiftUI
import AgentRendererCore

/// Pickers rise from the bottom as native sheets: one surface for Select, ComboBox and date inputs.
extension View {
    func renderSheet<Content: View>(
        isPresented: Binding<Bool>, height: CGFloat, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .presentationDetents([.height(height), .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationBackground(RenderTheme.surface)
                .presentationCornerRadius(28)
        }
    }
}

/// Centered sheet title; the field label lives here instead of beside the control.
struct RenderSheetTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(RenderTheme.foreground)
            .frame(maxWidth: .infinity).padding(.top, 22).padding(.bottom, 14)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One option row in a bottom sheet list.
struct RenderSheetOption: View {
    let title: String
    var detail: String? = nil
    let selected: Bool
    var multiple = false
    let action: () -> Void
    @Environment(\.renderAccent) private var accent
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: selected ? .semibold : .regular))
                    if let detail { Text(detail).font(.caption).foregroundStyle(RenderTheme.muted) }
                }
                Spacer(minLength: 8)
                if multiple {
                    RoundedRectangle(cornerRadius: 6).fill(selected ? accent : RenderTheme.neutral).frame(width: 22, height: 22)
                        .overlay { if selected { Image("lucide-check", bundle: .module).resizable().scaledToFit().frame(width: 14, height: 14).foregroundStyle(.white) } }
                } else if selected {
                    Image("lucide-check", bundle: .module).resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(accent)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .foregroundStyle(RenderTheme.foreground)
            .padding(.horizontal, 16).frame(minHeight: 54)
            .background(selected ? RenderTheme.neutral : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(RenderPlainButtonStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wall-clock dates (`yyyy-MM-dd`) shown the way people read them, e.g. "10月20日 周一".
enum RenderDateText {
    static func friendly(_ raw: String) -> String? {
        guard let date = ExtendedInput.date(raw) else { return nil }
        var style = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        let sameYear = Calendar.current.component(.year, from: .now) == Int(raw.prefix(4))
        if !sameYear { style = style.year() }
        return date.formatted(style)
    }
}

/// Native date wheel. A wheel always shows a day, so callers commit the shown day when a field is still
/// empty (on expanding a range section, or on closing the sheet). `lower`/`upper` are inclusive `yyyy-MM-dd`.
struct RenderDateWheel: View {
    let selection: String
    var lower = ""
    var upper = ""
    let onSelect: (String) -> Void
    @Environment(\.renderAccent) private var accent
    /// The day the wheel shows: the value, else the lower bound, else today; always inside the bounds.
    static func shown(_ selection: String, lower: String = "", upper: String = "") -> String {
        let candidate = ExtendedInput.date(selection) != nil ? selection : ExtendedInput.string(ExtendedInput.localDefault())
        if ExtendedInput.date(lower) != nil, candidate < lower { return lower }
        if ExtendedInput.date(upper) != nil, candidate > upper { return upper }
        return candidate
    }
    var body: some View {
        DatePicker("", selection: Binding(
            get: { ExtendedInput.date(Self.shown(selection, lower: lower, upper: upper)) ?? ExtendedInput.localDefault() },
            set: { onSelect(ExtendedInput.string($0)) }
        ), in: (ExtendedInput.date(lower) ?? .distantPast)...(ExtendedInput.date(upper) ?? .distantFuture), displayedComponents: .date)
            .labelsHidden()
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            #if os(iOS)
            .datePickerStyle(.wheel)
            #else
            .datePickerStyle(.graphical)
            #endif
            .tint(accent)
            .frame(maxWidth: .infinity)
    }
}

/// Start and end as two collapsible sections, each a native wheel; only one is open at a time and the closed
/// one shows its date.
struct DateRangePanel: View {
    let values: [String]
    let commit: (Int, String) -> Void
    @State private var open: Int?
    @Environment(\.renderAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(values: [String], commit: @escaping (Int, String) -> Void) {
        self.values = values
        self.commit = commit
        // Reopening with only a start date continues where the person left off.
        _open = State(initialValue: !values[0].isEmpty && values[1].isEmpty ? 1 : 0)
    }

    private func bounds(_ index: Int) -> (lower: String, upper: String) {
        index == 1 ? (values[0], "") : ("", values[1])
    }

    /// An open section always shows a day, so an empty one takes that day; the collapsed row then matches the wheel.
    private func adoptShownDay(_ index: Int?) {
        guard let index, values.indices.contains(index), values[index].isEmpty else { return }
        let range = bounds(index)
        commit(index, RenderDateWheel.shown("", lower: range.lower, upper: range.upper))
    }

    var body: some View {
        VStack(spacing: 0) {
            section(0, title: "开始日期")
            Rectangle().fill(RenderTheme.border).frame(height: 1).padding(.horizontal, 16)
            section(1, title: "结束日期")
        }
        .background(RenderTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(RenderTheme.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .sensoryFeedback(.selection, trigger: open)
        .onAppear { adoptShownDay(open) }
        .onChange(of: open) { _, index in adoptShownDay(index) }
    }

    private func section(_ index: Int, title: String) -> some View {
        let raw = values.indices.contains(index) ? values[index] : ""
        let expanded = open == index
        let shown = RenderDateText.friendly(raw) ?? "未选择"
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : RenderMotion.indicator) { open = expanded ? nil : index }
            } label: {
                HStack(spacing: 10) {
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(RenderTheme.foreground)
                    Spacer(minLength: 8)
                    Text(shown).font(.system(size: 15))
                        .foregroundStyle(raw.isEmpty ? RenderTheme.muted : expanded ? accent : RenderTheme.foreground)
                        .contentTransition(.opacity)
                    ChevronShape().stroke(RenderTheme.muted, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 10, height: 6).rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 16).frame(minHeight: 56).contentShape(Rectangle())
            }.buttonStyle(RenderPlainButtonStyle())
                .accessibilityLabel(title).accessibilityValue(shown)
                .accessibilityHint(expanded ? "已展开" : "点按展开并选择日期")
            if expanded {
                RenderDateWheel(selection: raw, lower: bounds(index).lower, upper: bounds(index).upper) { commit(index, $0) }
                    .padding(.horizontal, 8).padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
    }
}
