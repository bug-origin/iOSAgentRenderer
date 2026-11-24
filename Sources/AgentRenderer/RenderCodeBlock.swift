import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// The same code presentation serves message text and structured cards.
public struct RenderCodeBlock<Content: View>: View {
    private let content: Content
    let language: String?
    let code: String
    @State private var wraps = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(language: String?, code: String) where Content == Text {
        self.init(language: language, code: code) { Text(verbatim: code) }
    }

    public init(language: String?, code: String, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.language = language
        self.code = code
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: language.flatMap { $0.isEmpty ? nil : $0 } ?? "代码")
                    .font(.caption).foregroundStyle(RenderTheme.muted)
                Spacer()
                Button(wraps ? "取消折行" : "折行") { wraps.toggle() }
                    .accessibilityValue(wraps ? "已折行" : "未折行")
                Button {
                    #if os(iOS)
                        UIPasteboard.general.string = code
                    #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    #endif
                    withAnimation(reduceMotion ? nil : RenderMotion.feedback) { copied = true }
                } label: {
                    Text(copied ? "已复制" : "复制").contentTransition(.opacity)
                }
                .accessibilityLabel(copied ? "代码已复制" : "复制代码")
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
            }.buttonStyle(RenderButtonStyle(primary: false))
            if wraps {
                codeText.fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal) { codeText.fixedSize() }
            }
        }
        .padding(16)
        .background(RenderTheme.neutral, in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: code) { _, _ in copied = false }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            withAnimation(reduceMotion ? nil : RenderMotion.feedback) { copied = false }
        }
    }

    private var codeText: some View {
        content.font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
    }
}
