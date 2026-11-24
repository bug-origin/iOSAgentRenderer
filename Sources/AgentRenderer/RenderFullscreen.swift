import SwiftUI

private struct RenderFullscreenDismissKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var renderFullscreenDismiss: @MainActor @Sendable () -> Void {
        get { self[RenderFullscreenDismissKey.self] }
        set { self[RenderFullscreenDismissKey.self] = newValue }
    }
}

/// Shared source-to-center presentation for media, diagrams and future inspectors.
struct RenderFullscreenModifier<Destination: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let destination: () -> Destination
    @State private var source: CGRect = .zero
    @State private var visible = false

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { geometry in
                Color.clear.onAppear { source = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in source = frame }
            }
        }
        .onChange(of: isPresented) { _, value in
            if value { visible = true }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $visible, onDismiss: { isPresented = false }) {
            presentation.presentationBackground(.clear)
                .transaction { $0.disablesAnimations = false }
        }
        // Suppress UIKit's sheet slide; the shared content owns its animation.
        .transaction(value: visible) { transaction in transaction.disablesAnimations = true }
        #else
        .sheet(isPresented: $visible, onDismiss: { isPresented = false }) { presentation }
        #endif
    }

    private var presentation: some View {
        RenderFullscreenStage(source: source, requested: $isPresented, visible: $visible, destination: destination)
    }
}

private struct RenderFullscreenStage<Destination: View>: View {
    let source: CGRect
    @Binding var requested: Bool
    @Binding var visible: Bool
    @ViewBuilder let destination: () -> Destination
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var expanded = false
    @State private var closing = false

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let scale = min(1, max(0.05, min(source.width / max(1, frame.width), source.height / max(1, frame.height))))
            ZStack {
                Group {
                    if reduceTransparency { Color.black.opacity(0.94) }
                    else { Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.15)) }
                }.ignoresSafeArea().opacity(expanded ? 1 : 0)
                destination()
                    .environment(\.renderFullscreenDismiss, { close() })
                    .scaleEffect(expanded || reduceMotion ? 1 : scale)
                    .offset(x: expanded || reduceMotion ? 0 : source.midX - frame.midX,
                            y: expanded || reduceMotion ? 0 : source.midY - frame.midY)
                    .opacity(expanded ? 1 : 0)
            }
        }
        .task { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.88)) { expanded = true } }
        .onChange(of: requested) { _, value in if !value { close() } }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.9)) { expanded = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 160 : 360))
            visible = false
            requested = false
        }
    }
}
