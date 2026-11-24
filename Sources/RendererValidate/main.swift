import Foundation
import AgentRendererCore

// Validate model output using precisely the same contract and engine as the iOS renderer.
do {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    _ = try RenderDocument.decode(data)
    print("valid")
} catch {
    FileHandle.standardError.write(Data(error.localizedDescription.utf8))
    exit(1)
}
