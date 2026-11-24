import SwiftUI
import AgentRendererCore

struct MusicPlayerComponent: View {
    let context: ComponentRenderContext
    @Environment(\.renderAccent) private var accent

    private var props: [String: JSONValue] { context.node.props }
    private var playing: Bool { props["playing"] == .bool(true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if let artwork = props["artwork"]?.object {
                    RenderMediaPreview(image: artwork, height: 62).frame(width: 62)
                } else {
                    Image(systemName: "music.note").font(.title2.bold())
                        .frame(width: 62, height: 62).foregroundStyle(.white)
                        .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(props["title"]?.text ?? "").font(.headline)
                    if let artist = props["artist"]?.string {
                        Text(artist).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                let event = playing ? "pause" : "play"
                if context.session.canEmit(node: context.node, event: event) {
                    Button { context.emit(event) } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44)
                            .background(accent.opacity(0.12), in: Circle())
                    }.buttonStyle(.plain).foregroundStyle(accent)
                        .accessibilityLabel(playing ? "暂停" : "播放")
                        .disabled(context.session.pendingInstances.contains(context.node.id))
                }
            }
            if let duration = props["duration"]?.number {
                let elapsed = props["elapsed"]?.number ?? 0
                VStack(spacing: 4) {
                    GeometryReader { bounds in
                        ZStack(alignment: .leading) {
                            Capsule().fill(RenderTheme.neutral)
                            Capsule().fill(accent)
                                .frame(width: bounds.size.width * (elapsed / duration))
                        }
                    }
                    .frame(height: 4)
                    .accessibilityElement()
                    .accessibilityLabel("播放进度")
                    .accessibilityValue(time(elapsed) + " / " + time(duration))
                    HStack {
                        Text(time(elapsed))
                        Spacer()
                        Text(time(duration))
                    }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }.padding(18).background(RenderTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func time(_ seconds: Double) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
