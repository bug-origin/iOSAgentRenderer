import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Shared HeroUI Agents visual tokens. Accent is supplied by the host.
/// See THIRD_PARTY_NOTICES.md for the upstream source and Apache-2.0 license.
enum RenderTheme {
    static let foreground = adaptive(RenderTokens.foreground)
    static let muted = adaptive(RenderTokens.muted)
    static let surface = adaptive(RenderTokens.surface)
    static let secondary = adaptive(RenderTokens.secondary)
    static let neutral = adaptive(RenderTokens.neutral)
    static let border = adaptive(RenderTokens.border)
    static let danger = adaptive(RenderTokens.danger)
    static let success = adaptive(RenderTokens.success)
    static let warning = adaptive(RenderTokens.warning)
    static let fieldRadius = RenderTokens.fieldRadius
    static let surfaceRadius = RenderTokens.surfaceRadius
    static let disabledOpacity = RenderTokens.disabledOpacity

    private static func adaptive(_ pair: (light: UInt32, dark: UInt32)) -> Color {
        adaptive(pair.light, pair.dark)
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
        #endif
    }
}

/// The upstream field/surface shadow is absent in dark mode.
struct RenderShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.renderSurfaceDepth) private var depth
    func body(content: Content) -> some View {
        let shown = depth == 0 && colorScheme != .dark
        let layers = RenderTokens.surfaceShadow
        content
            .shadow(color: .black.opacity(shown ? layers[0].opacity : 0), radius: layers[0].radius, y: layers[0].y)
            .shadow(color: .black.opacity(shown ? layers[1].opacity : 0), radius: layers[1].radius, y: layers[1].y)
            .shadow(color: .black.opacity(shown ? layers[2].opacity : 0), radius: layers[2].radius, y: layers[2].y)
    }
}

/// Solid surfaces only; never inherits iOS Liquid Glass button styling.
struct RenderButtonStyle: ButtonStyle {
    var primary = true
    var variant: String? = nil
    @Environment(\.renderAccent) private var accent
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var labelSize = RenderTokens.buttonFontSize
    private var isPrimary: Bool { variant.map { $0 == "primary" } ?? primary }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: labelSize, weight: .medium))
            .padding(.horizontal, RenderTokens.buttonPaddingX).padding(.vertical, 6)
            .frame(minHeight: RenderTokens.buttonMinHeight)
            .foregroundStyle(isPrimary ? Color.white : variant == "outline" ? RenderTheme.foreground : accent)
            .background(isPrimary ? accent : variant == "outline" || variant == "tertiary" ? Color.clear : RenderTheme.neutral,
                        in: RoundedRectangle(cornerRadius: RenderTokens.buttonRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: RenderTokens.buttonRadius).strokeBorder(variant == "outline" ? RenderTheme.border : .clear, lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RenderTokens.buttonRadius, style: .continuous)
                    .fill(RenderTheme.foreground.opacity(configuration.isPressed && enabled ? RenderTokens.pressOverlayOpacity : 0))
                    .allowsHitTesting(false)
            }
            .modifier(RenderPressFeedback(pressed: configuration.isPressed && enabled))
            .frame(minHeight: 44).contentShape(Rectangle())
            .opacity(enabled ? 1 : RenderTheme.disabledOpacity)
            .animation(reduceMotion ? nil : RenderMotion.highlight, value: configuration.isPressed)
            .animation(reduceMotion ? nil : RenderMotion.feedback, value: enabled)
    }
}

struct RenderPressFeedback: ViewModifier {
    let pressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let shouldScale = pressed && !reduceMotion
        return content.visualEffect { view, geometry in
            // HeroUI scales by 0.985 at 300pt, compensating for the control width.
            let scale = 1 - min(0.06, 4.5 / max(geometry.size.width, 1))
            return view.scaleEffect(shouldScale ? scale : 1)
        }
        .animation(reduceMotion ? nil : RenderMotion.press, value: pressed)
    }
}

struct RenderPlainButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && enabled ? 0.8 : 1)
            .modifier(RenderPressFeedback(pressed: configuration.isPressed && enabled))
            .animation(reduceMotion ? nil : RenderMotion.highlight, value: configuration.isPressed)
    }
}

private struct RenderSurfaceDepthKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var renderSurfaceDepth: Int {
        get { self[RenderSurfaceDepthKey.self] }
        set { self[RenderSurfaceDepthKey.self] = newValue }
    }
}
