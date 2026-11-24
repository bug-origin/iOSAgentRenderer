---
name: ios-agent-renderer
description: Integrate iOSAgentRenderer into a SwiftUI app or generate and validate agent-ui/0.2 JSON cards for it. Use for Swift Package Manager setup, interactive agent cards, form bindings, and host action callbacks.
license: Apache-2.0
---

# iOSAgentRenderer

用户要接入 App 时，完成 Swift 包接入和原生卡片显示。用户只要一张卡片时，直接生成 JSON。`agent-ui/0.2` 是这个库的卡片协议，版本号独立于 Swift 包的版本。

## 接入现有 App

1. 找到实际展示消息的 App target 和它现有的依赖管理入口。包地址是 `https://github.com/bug-origin/iOSAgentRenderer.git`，支持 Swift 6、iOS 17+ 和 macOS 14+。Xcode 可以从 File → Add Package Dependencies 添加。SwiftPM 项目在 `dependencies` 中添加 `.package(url: "https://github.com/bug-origin/iOSAgentRenderer.git", from: "0.2.0")`。已有兼容版本时沿用项目的选择。
2. 给展示卡片的 target 链接 `AgentRenderer` 和 `AgentRendererCore`。SwiftPM target 使用 `.product(name: "AgentRenderer", package: "iOSAgentRenderer")` 和 `.product(name: "AgentRendererCore", package: "iOSAgentRenderer")`。
3. 在消息入口调用 `try RenderDocument.decode(data)`。在主线程用 `try RendererSession(document: document, onAction: handler)` 创建会话，用 `RendererView(session: session)` 展示。由消息持有会话，避免 SwiftUI 刷新时丢失输入。同一卡片收到新修订时调用 `try session.replace(spec:state:context:)`。[完整 Swift 示例](https://github.com/bug-origin/iOSAgentRenderer/blob/0.2.0/README.md)
4. 在 `handler` 中根据 `envelope.params["actionId"]` 匹配宿主已注册的操作，检查参数和权限，返回实际执行得到的 `ActionOutcome`。演示可以只在本地显示收到的动作及参数，明确标为演示。用真实的 App target 构建，打开卡片并检查输入或点击的结果。

## 生成卡片

按任务提供的内容、`context` 和可用宿主动作生成完整文档。下方提示词包含可离线使用的组件写法、状态绑定和完整示例。它也可以原样交给应用后端调用的模型。[生成卡片的提示词](references/card-prompt.md)

使用更多组件时，优先查宿主锁定版本中的 `Sources/AgentRendererCore/Resources/catalog.json`。其中 `required`、`properties`、`events` 和 `slots` 决定每种组件可以写什么。结构化属性的形状可在同版本图库里查到。图库条目中的 `name`、`title` 是示例元数据，构造文档时取 `context`、`spec`、`state` 并加上 `protocolVersion`。[组件目录](https://raw.githubusercontent.com/bug-origin/iOSAgentRenderer/0.2.0/Sources/AgentRendererCore/Resources/catalog.json) · [文档 Schema](https://raw.githubusercontent.com/bug-origin/iOSAgentRenderer/0.2.0/Schema/document.schema.json) · [图库示例](https://github.com/bug-origin/iOSAgentRenderer/tree/0.2.0/Sources/AgentRendererExamples/Resources)

## 验证

在有 Swift 6 和 Apple SDK 的开发机上，把输出保存为 `card.json`，从渲染器检出目录运行 `swift run renderer-validate < card.json`。从宿主项目运行时，用 `swift run --package-path "$renderer_checkout" renderer-validate < card.json`，其中 `renderer_checkout` 指向该版本的渲染器仓库根目录。输出 `valid` 表示原生引擎可以解析这张卡片。表单提交和宿主动作还需要在会话中实际触发。
