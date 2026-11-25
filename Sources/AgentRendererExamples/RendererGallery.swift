import Foundation
import SwiftUI
import AgentRenderer
import AgentRendererCore

/// Embed in an iOS 17+ host or Xcode preview. This gallery captures actions locally; it never calls a backend.
@MainActor
public struct RendererGallery: View {
    @State private var selection: String?
    private static let titles = Dictionary(uniqueKeysWithValues: RendererExample.names.map { name in
        (name, (try? RendererExample.load(name).title) ?? name)
    })

    public init() {
        self.init(initialSelection: RendererExample.names.first)
    }

    /// Pass nil to open the example list first on iPhone.
    public init(initialSelection: String?) {
        _selection = State(initialValue: initialSelection)
    }

    public var body: some View {
        NavigationSplitView {
            List(RendererExample.names, id: \.self, selection: $selection) { name in
                Text(Self.titles[name] ?? name).tag(name)
            }.navigationTitle("Renderer 样例")
        } detail: {
            if let selection {
                ExampleScreen(name: selection).id(selection)
            } else { Text("选择一个样例") }
        }
    }

}

@MainActor
private struct ExampleScreen: View {
    let name: String
    @State private var session: RendererSession?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let session {
                    RendererView(session: session)
                    if let action = session.lastAction {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("捕获的交互（尚未发送至 Agent）").font(.headline)
                            Text(encoded(action)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                } else if let error { Text(error).foregroundStyle(.red) }
                else { ProgressView() }
            }.padding(20).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
        }
        .navigationTitle("SwiftUI Renderer")
        .task {
            do {
                let example = try RendererExample.load(name)
                session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: .bundled()) { invocation in
                    ActionOutcome(status: .accepted, message: "演示：动作已捕获，未调用真实服务（" + invocation.action + "）")
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func encoded(_ action: ActionEnvelope) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return String(decoding: try encoder.encode(action), as: UTF8.self)
        } catch { return "无法编码交互：" + error.localizedDescription }
    }
}
