import Foundation
import SwiftUI
import AgentRenderer
import AgentRendererCore
import AgentRendererExamples

#if os(macOS)
import AppKit

@main
struct RendererSnapshots {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let catalog = try RenderCatalog.bundled()
        let registry = ComponentRegistry.standard()
        guard registry.types == Set(catalog.components.keys) else { throw RendererError("Catalog and SwiftUI registry differ") }
        let requested = CommandLine.arguments.dropFirst(2).filter { !$0.hasPrefix("--") }
        for name in requested.isEmpty ? RendererExample.names : requested {
            let example = try RendererExample.load(name)
            let session = try RendererSession(spec: example.spec, state: example.state, context: example.context, catalog: catalog) { action in
                ActionOutcome(status: .accepted, message: "演示动作已捕获：" + action.action)
            }
            for width in [390.0, 820.0] {
                let view = RendererView(session: session)
                    .padding(20).frame(width: width, alignment: .topLeading)
                    .background(Color.gray.opacity(0.06)).environment(\.colorScheme, CommandLine.arguments.contains("--dark") ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw RendererError("SwiftUI snapshot failed: \(name)")
                }
                let destination = output.appendingPathComponent("\(name)-\(Int(width)).png")
                try png.write(to: destination)
                print(destination.path)
            }
        }
    }
}
#else
@main
struct RendererSnapshots {
    static func main() { print("Snapshot export uses macOS; the renderer library supports iOS 17+") }
}
#endif
