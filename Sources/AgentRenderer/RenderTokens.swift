import SwiftUI

/// Default colors, sizing and motion for the native components.
enum RenderTokens {
    static let foreground: (light: UInt32, dark: UInt32) = (0x18181B, 0xFCFCFC)
    static let muted: (light: UInt32, dark: UInt32) = (0x71717A, 0x9F9FA9)
    static let surface: (light: UInt32, dark: UInt32) = (0xFFFFFF, 0x18181B)
    static let secondary: (light: UInt32, dark: UInt32) = (0xEFEFF0, 0x222225)
    static let neutral: (light: UInt32, dark: UInt32) = (0xEBEBEC, 0x27272A)
    static let border: (light: UInt32, dark: UInt32) = (0xDEDEE0, 0x28282C)
    static let danger: (light: UInt32, dark: UInt32) = (0xFF383C, 0xDB3B3E)
    static let success: (light: UInt32, dark: UInt32) = (0x17C964, 0x17C964)
    static let warning: (light: UInt32, dark: UInt32) = (0xF5A524, 0xFBBF45)
    static let chartPrimary: UInt32 = 0x0AB7C7
    static let chartPositive: UInt32 = 0x0AC76D
    static let chartWarning: UInt32 = 0xC7880A
    static let chartNegative: UInt32 = 0xC7580A
    static let chartDeep: UInt32 = 0x2C6C72
    static let fieldRadius: CGFloat = 12
    static let surfaceRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 24
    static let buttonMinHeight: CGFloat = 36
    static let buttonPaddingX: CGFloat = 12
    static let buttonFontSize: CGFloat = 14
    static let disabledOpacity = 0.5
    static let pressOverlayOpacity = 0.06
    /// Light mode only; renderer surfaces have no shadow in dark mode.
    static let surfaceShadow: [(y: CGFloat, radius: CGFloat, opacity: Double)] = [
        (y: 2, radius: 2, opacity: 0.04),
        (y: 1, radius: 1, opacity: 0.06),
        (y: 0, radius: 0.5, opacity: 0.06),
    ]
}

/// Renderer animations.
enum RenderMotion {
    static let feedback = Animation.easeOut(duration: 0.2)
    static let press = Animation.timingCurve(0, 0, 0.58, 1, duration: 0.3)
    static let highlight = Animation.easeOut(duration: 0.2)
    static let chart = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.65)
    static let indicator = Animation.interpolatingSpring(mass: 4, stiffness: 1000, damping: 140)
    static let errorIn = Animation.easeOut(duration: 0.15)
    static let errorOut = Animation.easeOut(duration: 0.1)
    static let step = Animation.smooth(duration: 0.35)
}
