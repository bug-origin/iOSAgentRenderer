import SwiftUI
import AgentRendererCore

@MainActor
struct StepsComponent: View {
    let context: ComponentRenderContext
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var index: Int { Int(context.node.props["value"]?.number ?? 0) }
    private var labels: [JSONValue] { context.node.props["labels"]?.array ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if context.node.children.indices.contains(index) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("第 \(index + 1) / \(labels.count) 步 · \(labels[index].text)")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(RenderTheme.muted).contentTransition(.numericText())
                    ProgressView(value: Double(index + 1), total: Double(labels.count))
                        .accessibilityLabel("表单进度")
                }
                VStack(alignment: .leading, spacing: 12) {
                    context.renderChild(context.node.children[index])
                        .id(context.node.children[index].id)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                HStack(spacing: 12) {
                    Button("上一步") { move(-1) }.buttonStyle(RenderButtonStyle(primary: false)).disabled(index == 0)
                    Spacer()
                    if index < labels.count - 1 {
                        Button("下一步") { move(1) }.buttonStyle(RenderButtonStyle())
                    }
                }
            }
        }
        .disabled(context.node.props["disabled"] == .bool(true) || !context.session.pendingInstances.isEmpty)
        .animation(reduceMotion ? nil : RenderMotion.feedback, value: index)
        .sensoryFeedback(.impact(weight: .light), trigger: index)
    }
    private func move(_ offset: Int) {
        // Direction must be committed before SwiftUI removes the old page.
        forward = offset > 0
        withAnimation(reduceMotion ? nil : RenderMotion.step) {
            context.session.moveStep(instanceId: context.node.id, offset: offset)
        }
    }
}
