# iOSAgentRenderer

iOSAgentRenderer turns JSON from an agent into native SwiftUI cards. An agent can return a form, a chart, a map, or a music player in a conversation. The renderer draws the card and tracks edits. Your app supplies the data and handles actions such as saving a note or playing a track.

Requires Swift 6, with iOS 17+ or macOS 14+ as the deployment target. [View a card on iPhone](Documentation/sequence-card.png)

## Open the iOS gallery

Clone this repository and open the [RendererGallery Xcode project](Examples/RendererGallery/RendererGallery.xcodeproj). Select the **RendererGallery** scheme, choose an iPhone or iPad simulator, and press **Run**.

Browse the bundled examples, edit a form, or tap Play on the music card to inspect the action your app would receive. The gallery captures actions locally. It links the Swift package from this checkout, so changes to the renderer appear the next time you build.

## Install with Swift Package Manager

In Xcode, choose **File > Add Package Dependencies**, enter `https://github.com/bug-origin/iOSAgentRenderer.git`, and select version `0.2.1` or a compatible later version. Add **AgentRenderer** and **AgentRendererCore** to the target that displays the cards.

In a `Package.swift` manifest, the package dependency goes in the package's `dependencies` array.

```swift
.package(url: "https://github.com/bug-origin/iOSAgentRenderer.git", from: "0.2.1")
```

The target that displays the cards needs both products.

```swift
.product(name: "AgentRenderer", package: "iOSAgentRenderer"),
.product(name: "AgentRendererCore", package: "iOSAgentRenderer")
```

## Render your first card

This card has a text field and a Clear button. Type a note and tap Clear to reset the field locally.

```json
{
  "protocolVersion": "agent-ui/0.2",
  "context": { "threadId": "", "viewId": "note", "revision": 1 },
  "spec": {
    "root": "card",
    "elements": {
      "card": {
        "type": "Card",
        "props": { "title": "Quick note" },
        "children": ["note", "clear"]
      },
      "note": {
        "type": "TextField",
        "props": { "label": "Note", "value": { "$bindState": "/form/text" } },
        "children": []
      },
      "clear": {
        "type": "Button",
        "props": { "label": "Clear" },
        "children": [],
        "on": { "press": { "action": "setState", "params": { "statePath": "/form/text", "value": "" } } }
      }
    }
  },
  "state": { "data": {}, "form": { "text": "My first note" }, "ui": {} }
}
```

When a message arrives, decode its JSON and create a session on the main actor. Keep one session per card so a SwiftUI refresh or a scroll offscreen preserves the draft.

```swift
import AgentRenderer
import AgentRendererCore
import Foundation
import SwiftUI

@MainActor
func makeCardSession(
    from data: Data,
    onAction: @escaping @MainActor (ActionEnvelope) async throws -> ActionOutcome
) throws -> RendererSession {
    let document = try RenderDocument.decode(data)
    return try RendererSession(document: document, onAction: onAction)
}

struct AgentCard: View {
    let session: RendererSession

    var body: some View {
        RendererView(session: session)
    }
}
```

For host actions, match `envelope.params["actionId"]` to an operation your app supports, validate its inputs, and return the outcome from `onAction`. When the agent sends a new revision of the same card, call `try session.replace(spec:state:context:)` with the updated document. [Form with a submit action](Examples/note.json)

## Give it to your agent

Paste this request into a coding agent that can edit your app.

> Add https://github.com/bug-origin/iOSAgentRenderer to this app with Swift Package Manager. Follow the repository's ios-agent-renderer skill. Show an editable note card in the conversation, then build the app and verify that tapping Clear empties the field.

Run this command from your project directory to install the skill.

```sh
npx skills add bug-origin/iOSAgentRenderer --skill ios-agent-renderer
```

For a model that only produces JSON, give it the card prompt, the card's `context`, the data to display, and the actions your app supports. For example, ask it to plot the squares of the numbers 1 through 5 and show the values in a table. [Agent skill](skills/ios-agent-renderer/SKILL.md) · [Standalone card prompt](skills/ios-agent-renderer/references/card-prompt.md)

## Music, maps, and weather

| Component | What the card displays | What your app supplies |
| --- | --- | --- |
| [MusicPlayer](Sources/AgentRendererExamples/Resources/music-player.json) | Track title, artist, optional artwork, playback progress, and a play or pause control | Track metadata and playback state. The app handles the play and pause events. |
| [Map](Sources/AgentRendererExamples/Resources/map-route.json) | Selectable MapKit markers and lines connecting stops | Coordinates, location IDs, and the order of stops on each route. |
| [Weather](Sources/AgentRendererExamples/Resources/weather-forecast.json) | Current conditions and up to 14 days of forecast highs and lows in Celsius or Fahrenheit | A location label, observations, forecast values, and the temperature unit. |

All three examples use synthetic data. Music and weather cards require package version 0.2.1 or later.

## Card format

`agent-ui/0.2` is the card protocol defined by this library. Its version is independent of the Swift package version. Every document contains four fields.

| Field | Purpose |
| --- | --- |
| `protocolVersion` | Selects the card format. Use `"agent-ui/0.2"`. |
| `context` | Identifies the conversation, card, and revision through `threadId`, `viewId`, and `revision`. |
| `spec` | Declares the component tree. `root` names the first element, and `elements` maps keys to component definitions. |
| `state` | Holds read-only input in `data`, editable values in `form`, and local display state in `ui`. |

The schemas use JSON Schema Draft 2020-12. The component catalog lists supported properties, events, and slots. The native validator also resolves the tree and checks component values and bindings. [Document schema](Schema/document.schema.json) · [Action schema](Schema/action.schema.json) · [Component catalog](Sources/AgentRendererCore/Resources/catalog.json)

The package uses Swift Package Manager for installation and the Agent Skills format for agent instructions. [Apple package dependency guide](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) · [Agent Skills specification](https://agentskills.io/specification)

## Validate and preview

Run the validator from a checkout of this repository on macOS. It prints `valid` when the example passes.

```sh
swift run renderer-validate < Examples/note.json
swift test
```

To browse the examples in an app, link the `AgentRendererExamples` product, import it, and display `RendererGallery()`. The gallery displays action callbacks locally. The snapshot command exports a SwiftUI preview on macOS.

```sh
swift run renderer-snapshots /tmp/agent-cards music-player
```

## Design and license

The default theme draws on HeroUI Native. Some component interactions follow the public HeroUI Agents designs. The bundled icons come from Lucide. iOSAgentRenderer is available under Apache License 2.0. [License](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)
