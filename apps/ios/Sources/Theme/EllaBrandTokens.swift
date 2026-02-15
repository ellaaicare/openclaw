import SwiftUI

/// V6 "Ella Home" brand identity — single source of truth.
/// Philosophy: "Technology that feels like home, not like technology."
/// V3 warmth + V2 precision. Warm aquamarine teal, cream backgrounds.

// MARK: - Brand Colors

enum EllaBrand {

    // MARK: Core Palette

    /// Primary brand teal — warm aquamarine
    static let primary = Color(red: 0.353, green: 0.620, blue: 0.561) // #5A9E8F
    /// Primary darkened for pressed states
    static let primaryDark = Color(red: 0.290, green: 0.541, blue: 0.482) // #4A8A7B
    /// Primary lightened for highlights
    static let primaryLight = Color(red: 0.478, green: 0.710, blue: 0.659) // #7AB5A8
    /// Primary at 10% for subtle fills
    static let primarySubtle = Color(red: 0.910, green: 0.961, blue: 0.941) // #E8F5F0

    /// Warm cream — main background
    static let backgroundPrimary = Color(red: 0.980, green: 0.961, blue: 0.941) // #FAF5F0
    /// Deeper warm cream — card/surface background
    static let backgroundSecondary = Color(red: 0.961, green: 0.941, blue: 0.910) // #F5F0E8
    /// Warm taupe — borders, dividers
    static let backgroundTertiary = Color(red: 0.910, green: 0.878, blue: 0.839) // #E8E0D6

    /// Dark charcoal — primary text
    static let textPrimary = Color(red: 0.176, green: 0.176, blue: 0.176) // #2D2D2D
    /// Medium charcoal — secondary text
    static let textSecondary = Color(red: 0.290, green: 0.290, blue: 0.290) // #4A4A4A
    /// Light gray — tertiary/caption text
    static let textTertiary = Color(red: 0.478, green: 0.478, blue: 0.478) // #7A7A7A
    /// Disabled text
    static let textDisabled = Color(red: 0.690, green: 0.690, blue: 0.690) // #B0B0B0

    /// Warm taupe border
    static let border = Color(red: 0.910, green: 0.878, blue: 0.839) // #E8E0D6

    // MARK: Orb State Colors (Harmonized for V6)

    /// Idle: Brand teal — the "home" state (80%+ of screen time)
    static let orbIdle = Color(red: 0.353, green: 0.620, blue: 0.561) // #5A9E8F
    /// Listening: Warm sage green
    static let orbListening = Color(red: 0.490, green: 0.722, blue: 0.541) // #7DB88A
    /// Thinking: Warm mauve
    static let orbThinking = Color(red: 0.627, green: 0.553, blue: 0.722) // #A08DB8
    /// Speaking: Warm aqua
    static let orbSpeaking = Color(red: 0.361, green: 0.722, blue: 0.678) // #5CB8AD
    /// Confirm: Same as listening
    static let orbConfirm = Color(red: 0.490, green: 0.722, blue: 0.541) // #7DB88A
    /// Reminder: Warm sky
    static let orbReminder = Color(red: 0.482, green: 0.686, blue: 0.773) // #7BAFC5
    /// Alert: Warm amber
    static let orbAlert = Color(red: 0.910, green: 0.655, blue: 0.337) // #E8A756
    /// Wake detected: Same as listening
    static let orbWakeDetected = Color(red: 0.490, green: 0.722, blue: 0.541) // #7DB88A

    // MARK: Dark Mode (for orb screen)

    /// Deep warm charcoal (not pure black)
    static let backgroundDark = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    /// Slightly lighter dark surface
    static let surfaceDark = Color(red: 0.165, green: 0.165, blue: 0.165) // #2A2A2A

    // MARK: Semantic Colors

    static let success = Color(red: 0.490, green: 0.722, blue: 0.541) // #7DB88A
    static let warning = Color(red: 0.910, green: 0.655, blue: 0.337) // #E8A756
    static let error = Color(red: 0.831, green: 0.447, blue: 0.416) // #D4726A
    static let info = Color(red: 0.482, green: 0.686, blue: 0.773) // #7BAFC5

    // MARK: Typography (SF Pro — system font, optimal for elderly accessibility)

    enum Typography {
        static let largeTitle: Font = .system(size: 34, weight: .bold)
        static let title1: Font = .system(size: 28, weight: .bold)
        static let title2: Font = .system(size: 22, weight: .semibold)
        static let headline: Font = .system(size: 17, weight: .semibold)
        static let body: Font = .system(size: 17, weight: .regular)
        static let bodyLarge: Font = .system(size: 20, weight: .regular)
        static let callout: Font = .system(size: 16, weight: .regular)
        static let caption: Font = .system(size: 13, weight: .regular)
    }

    // MARK: Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Corner Radii

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 999
    }
}
