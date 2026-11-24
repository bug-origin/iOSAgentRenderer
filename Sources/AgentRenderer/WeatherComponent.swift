import SwiftUI
import AgentRendererCore

struct WeatherComponent: View {
    let context: ComponentRenderContext
    private var props: [String: JSONValue] { context.node.props }
    private var unit: String { props["unit"] == .string("fahrenheit") ? "°F" : "°C" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(props["location"]?.text ?? "").font(.headline)
            HStack(alignment: .center, spacing: 16) {
                Text((props["temperature"]?.text ?? "") + unit)
                    .font(.largeTitle.weight(.medium)).monospacedDigit()
                Spacer(minLength: 0)
                condition(props["condition"])
            }
            ForEach(Array((props["forecast"]?.array ?? []).enumerated()), id: \.offset) { _, entry in
                let row = entry.object ?? [:]
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(row["label"]?.text ?? "")
                        Spacer()
                        condition(row["condition"])
                        temperatures(row)
                    }
                    VStack(alignment: .leading) {
                        Text(row["label"]?.text ?? "")
                        condition(row["condition"])
                        temperatures(row)
                    }
                }.font(.subheadline).accessibilityElement(children: .combine)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.cyan.opacity(0.15), RenderTheme.surface],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20))
    }

    private func temperatures(_ row: [String: JSONValue]) -> some View {
        Text((row["low"]?.text ?? "") + "° – " + (row["high"]?.text ?? "") + "°")
            .monospacedDigit().foregroundStyle(.secondary)
    }

    private func condition(_ value: JSONValue?) -> some View {
        let appearance: (String, String) = switch value?.string {
        case "clear": ("晴", "sun.max.fill")
        case "cloudy": ("多云", "cloud.fill")
        case "rain": ("雨", "cloud.rain.fill")
        case "snow": ("雪", "snowflake")
        case "storm": ("雷暴", "cloud.bolt.fill")
        default: ("雾", "cloud.fog.fill")
        }
        return Label(appearance.0, systemImage: appearance.1)
    }
}
