import SwiftUI
import AgentRendererCore

extension View {
    public func renderFullScreen<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(RenderFullscreenModifier(isPresented: isPresented, destination: content))
    }
    /// Shared by image nodes, generated scenes, records and host chat images.
    public func chatImagePreview(url: URL?, title: String = "图片") -> some View {
        modifier(ChatImagePreviewModifier(url: url, title: title))
    }
}

private struct ChatImagePreviewModifier: ViewModifier {
    let url: URL?
    let title: String
    @State private var presented = false
    func body(content: Content) -> some View {
        content.contentShape(Rectangle()).onTapGesture { if url != nil { presented = true } }
            .accessibilityAddTraits(.isButton).accessibilityHint("打开全屏图片预览")
            .renderFullScreen(isPresented: $presented) { RenderImageViewer(url: url, title: title) }
    }
}

/// A single full-screen presentation for every remote image surface.
public struct RenderImageViewer: View {
    let url: URL?
    let title: String
    @Environment(\.renderFullscreenDismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var angle: Angle = .zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var translation: CGSize = .zero
    @GestureState private var rotation: Angle = .zero
    public init(url: URL?, title: String = "图片") { self.url = url; self.title = title }
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if reduceTransparency { Color.black.opacity(0.94).ignoresSafeArea() }
                else { Color.clear }
                AsyncImage(url: url, transaction: RenderMotion.imageLoad(reduceMotion)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(min(8, max(0.5, scale * magnification)))
                            .rotationEffect(angle + rotation)
                            .offset(x: offset.width + translation.width, y: offset.height + translation.height)
                            .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }.onEnded { scale = min(8, max(0.5, scale * $0.magnification)) })
                            .simultaneousGesture(RotateGesture().updating($rotation) { value, state, _ in state = value.rotation }.onEnded { angle += $0.rotation })
                            .simultaneousGesture(DragGesture().updating($translation) { value, state, _ in state = value.translation }.onEnded { offset.width += $0.translation.width; offset.height += $0.translation.height })
                            .onTapGesture(count: 2) { withAnimation(reduceMotion ? nil : .snappy) { if scale == 1 { scale = 2 } else { reset() } } }
                            .accessibilityLabel(title).accessibilityIdentifier("global-image-preview")
                    case .failure: ContentUnavailableView("图片加载失败", systemImage: "photo", description: Text("请关闭后重试"))
                    default: ProgressView().tint(.white)
                    }
                }
            }.clipped().overlay(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    Button("复位") { withAnimation(reduceMotion ? nil : .snappy) { reset() } }
                    Button { dismiss() } label: { Image("lucide-x", bundle: .module).resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 32, height: 32) }.accessibilityLabel("关闭图片预览")
                }.buttonStyle(.bordered).tint(.primary).padding()
            }
        }.presentationBackground(.clear).accessibilityAction(named: "复位图片") { reset() }
    }
    private func reset() { scale = 1; offset = .zero; angle = .zero }
}

struct RenderMediaPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let image: [String: JSONValue]
    var height: CGFloat = 180
    var body: some View {
        AsyncImage(url: image["src"]?.string.flatMap(URL.init(string:)), transaction: RenderMotion.imageLoad(reduceMotion)) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: height)
            case .failure: Text("图片暂不可用").font(.caption).foregroundStyle(RenderTheme.muted).frame(maxWidth: .infinity).frame(height: height)
            default: ProgressView().frame(maxWidth: .infinity).frame(height: height)
            }
        }.background(RenderTheme.neutral).clipShape(RoundedRectangle(cornerRadius: 12))
            .chatImagePreview(url: image["src"]?.string.flatMap(URL.init(string:)), title: image["alt"]?.text ?? "图片")
    }
}
