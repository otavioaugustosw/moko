import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct MokoMotionOverride: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var mokoReduceMotion: Bool {
        get { accessibilityReduceMotion || self[MokoMotionOverride.self] }
        set { self[MokoMotionOverride.self] = newValue }
    }
}

enum MokoTheme {
    static let accent = Color("AccentColor")
    static let ink = Color("Ink")
    // Citrus text variant: HSL 65°, 100%, 23%; contrast 5.04:1 on white.
    static let selectionInk = Color("SelectionInk")
    static let canvas = Color("Canvas")
    static let sidebar = Color("Sidebar")
    static let wordmark = Color("Wordmark")
    static let secondaryInk = Color("SecondaryInk")
    static let errorInk = Color("ErrorInk")
    static let surface = Color("Surface")
    static let featureSurface = Color("FeatureSurface")
    static let separator = Color("Separator")
    static let onAccent = Color("OnAccent")
    static let onboardingEnd = Color("OnboardingEnd")
    static func native(_ name: String) -> NSColor { NSColor(named: name) ?? .labelColor }
}
