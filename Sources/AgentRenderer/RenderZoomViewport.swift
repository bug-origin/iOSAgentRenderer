import SwiftUI

/// Fit first, then allow two-finger inspection without stealing the chat's vertical scroll.
struct RenderZoomViewport<Content: View>: View {
    let canvasSize: CGSize
    @ViewBuilder let content: () -> Content
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero
    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / max(1, canvasSize.width), geometry.size.height / max(1, canvasSize.height))
            content().frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(fit * min(8, max(1, scale * pinch)))
                .position(x: geometry.size.width / 2 + offset.width + pan.width, y: geometry.size.height / 2 + offset.height + pan.height)
                // Bound hit testing as well as drawing: the unscaled canvas can be much
                // larger than the viewport and otherwise covers neighboring controls.
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }.onEnded { scale = min(8, max(1, scale * $0.magnification)); if scale == 1 { offset = .zero } })
                .simultaneousGesture(DragGesture(minimumDistance: scale > 1 ? 10 : .greatestFiniteMagnitude).updating($pan) { value, state, _ in if scale > 1 { state = value.translation } }.onEnded { if scale > 1 { offset.width += $0.translation.width; offset.height += $0.translation.height } })
                .simultaneousGesture(TapGesture(count: 2).onEnded { scale = 1; offset = .zero })
        }.clipped().accessibilityHint("双指缩放，放大后拖动，双击恢复完整流程图")
            .onChange(of: canvasSize) { _, _ in scale = 1; offset = .zero }
    }
}
