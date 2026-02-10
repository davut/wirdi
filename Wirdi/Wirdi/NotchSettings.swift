//
//  NotchSettings.swift
//  Wirdi
//
//

import SwiftUI

// MARK: - Font Size Preset

enum FontSizePreset: String, CaseIterable, Identifiable {
    case xs, sm, lg, xl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .xs: return "XS"
        case .sm: return "SM"
        case .lg: return "LG"
        case .xl: return "XL"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .xs: return 14
        case .sm: return 16
        case .lg: return 20
        case .xl: return 24
        }
    }
}

// MARK: - Font Family Preset

enum FontFamilyPreset: String, CaseIterable, Identifiable {
    case sans, serif, mono, dyslexia, quran

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sans:     return "Sans"
        case .serif:    return "Serif"
        case .mono:     return "Mono"
        case .dyslexia: return "Dyslexia"
        case .quran:    return "Quran"
        }
    }

    var sampleText: String {
        switch self {
        case .sans:     return "Aa"
        case .serif:    return "Aa"
        case .mono:     return "Aa"
        case .dyslexia: return "Aa"
        case .quran:    return "بسم"
        }
    }

    func font(size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor
        switch self {
        case .sans:
            return base
        case .serif:
            if let designed = descriptor.withDesign(.serif) {
                return NSFont(descriptor: designed, size: size) ?? base
            }
            return base
        case .mono:
            if let designed = descriptor.withDesign(.monospaced) {
                return NSFont(descriptor: designed, size: size) ?? base
            }
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .dyslexia:
            if let dyslexicFont = NSFont(name: "OpenDyslexic3", size: size) {
                return dyslexicFont
            }
            if let designed = descriptor.withDesign(.rounded) {
                return NSFont(descriptor: designed, size: size) ?? base
            }
            return base
        case .quran:
            if let quranFont = NSFont(name: "KFGQPCHAFSUthmanicScript-Regula", size: size) {
                return quranFont
            }
            return base
        }
    }
}

// MARK: - Quran Font Preset

enum QuranFontPreset: String, CaseIterable, Identifiable {
    case uthmanic, nastaleeq, indopak

    var id: String { rawValue }

    var label: String {
        switch self {
        case .uthmanic:  return "Uthmanic"
        case .nastaleeq: return "Nastaleeq"
        case .indopak:   return "IndoPak"
        }
    }

    var postScriptName: String {
        switch self {
        case .uthmanic:  return "KFGQPCHAFSUthmanicScript-Regula"
        case .nastaleeq: return "KFGQPCNastaleeq-Regular"
        case .indopak:   return "AlQuranIndoPakbyQuranWBW"
        }
    }

    func font(size: CGFloat) -> NSFont {
        if let font = NSFont(name: postScriptName, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }
}

// MARK: - Font Color Preset

enum FontColorPreset: String, CaseIterable, Identifiable {
    case white, yellow, green, blue, pink, orange

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .white:  return .white
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .green:  return Color(red: 0.2, green: 0.84, blue: 0.29)
        case .blue:   return Color(red: 0.31, green: 0.55, blue: 1.0)
        case .pink:   return Color(red: 1.0, green: 0.38, blue: 0.57)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.04)
        }
    }

    var label: String {
        switch self {
        case .white:  return "White"
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .pink:   return "Pink"
        case .orange: return "Orange"
        }
    }
}

// MARK: - Overlay Mode

enum OverlayMode: String, CaseIterable, Identifiable {
    case pinned, floating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pinned:   return "Pinned to Notch"
        case .floating: return "Floating Window"
        }
    }

    var description: String {
        switch self {
        case .pinned:   return "Anchored below the notch at the top of your screen."
        case .floating: return "A draggable window you can place anywhere. Always on top."
        }
    }

    var icon: String {
        switch self {
        case .pinned:   return "rectangle.topthird.inset.filled"
        case .floating: return "macwindow.on.rectangle"
        }
    }
}

// MARK: - Notch Display Mode

enum NotchDisplayMode: String, CaseIterable, Identifiable {
    case followMouse, fixedDisplay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followMouse:  return "Follow Mouse"
        case .fixedDisplay: return "Fixed Display"
        }
    }

    var description: String {
        switch self {
        case .followMouse:  return "The notch moves to whichever display your mouse is on."
        case .fixedDisplay: return "The notch stays on the selected display."
        }
    }
}

// MARK: - Listening Mode

enum ListeningMode: String, CaseIterable, Identifiable {
    case wordTracking, classic, silencePaused

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic:        return "Classic"
        case .silencePaused:  return "Voice-Activated"
        case .wordTracking:   return "Word Tracking"
        }
    }

    var description: String {
        switch self {
        case .classic:        return "Auto-scrolls at a constant speed. No microphone needed."
        case .silencePaused:  return "Scrolls while you speak, pauses when you're silent."
        case .wordTracking:   return "Tracks each word you say and highlights it in real time."
        }
    }

    var icon: String {
        switch self {
        case .classic:        return "arrow.down.circle"
        case .silencePaused:  return "waveform.circle"
        case .wordTracking:   return "text.word.spacing"
        }
    }
}

// MARK: - Settings

@Observable
class NotchSettings {
    static let shared = NotchSettings()

    var notchWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(notchWidth), forKey: "notchWidth") }
    }
    var textAreaHeight: CGFloat {
        didSet { UserDefaults.standard.set(Double(textAreaHeight), forKey: "textAreaHeight") }
    }

    var fontSizePreset: FontSizePreset {
        didSet { UserDefaults.standard.set(fontSizePreset.rawValue, forKey: "fontSizePreset") }
    }

    var fontFamilyPreset: FontFamilyPreset {
        didSet { UserDefaults.standard.set(fontFamilyPreset.rawValue, forKey: "fontFamilyPreset") }
    }

    var fontColorPreset: FontColorPreset {
        didSet { UserDefaults.standard.set(fontColorPreset.rawValue, forKey: "fontColorPreset") }
    }

    var overlayMode: OverlayMode {
        didSet { UserDefaults.standard.set(overlayMode.rawValue, forKey: "overlayMode") }
    }

    var notchDisplayMode: NotchDisplayMode {
        didSet { UserDefaults.standard.set(notchDisplayMode.rawValue, forKey: "notchDisplayMode") }
    }

    var pinnedScreenID: UInt32 {
        didSet { UserDefaults.standard.set(Int(pinnedScreenID), forKey: "pinnedScreenID") }
    }

    var floatingGlassEffect: Bool {
        didSet { UserDefaults.standard.set(floatingGlassEffect, forKey: "floatingGlassEffect") }
    }

    var glassOpacity: Double {
        didSet { UserDefaults.standard.set(glassOpacity, forKey: "glassOpacity") }
    }

    var listeningMode: ListeningMode {
        didSet { UserDefaults.standard.set(listeningMode.rawValue, forKey: "listeningMode") }
    }

    /// Words per second for classic and silence-paused modes
    var scrollSpeed: Double {
        didSet { UserDefaults.standard.set(scrollSpeed, forKey: "scrollSpeed") }
    }

    // MARK: - Quran Reminder Settings

    var quranReminderInterval: Int {
        didSet { UserDefaults.standard.set(quranReminderInterval, forKey: "quranReminderInterval") }
    }

    /// Reading length in seconds (10–3600)
    var quranReadingLengthSeconds: Int {
        didSet { UserDefaults.standard.set(quranReadingLengthSeconds, forKey: "quranReadingLengthSeconds") }
    }

    /// Snooze duration in minutes when user taps "Later"
    var quranSnoozeDurationMinutes: Int {
        didSet { UserDefaults.standard.set(quranSnoozeDurationMinutes, forKey: "quranSnoozeDurationMinutes") }
    }

    var quranCurrentSurah: Int {
        didSet { UserDefaults.standard.set(quranCurrentSurah, forKey: "quranCurrentSurah") }
    }

    var quranCurrentAyah: Int {
        didSet { UserDefaults.standard.set(quranCurrentAyah, forKey: "quranCurrentAyah") }
    }

    var quranFontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(quranFontSize), forKey: "quranFontSize") }
    }

    var quranFontPreset: QuranFontPreset {
        didSet { UserDefaults.standard.set(quranFontPreset.rawValue, forKey: "quranFontPreset") }
    }

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var quranFont: NSFont {
        quranFontPreset.font(size: quranFontSize)
    }

    var font: NSFont {
        fontFamilyPreset.font(size: fontSizePreset.pointSize)
    }

    static let defaultWidth: CGFloat = 340
    static let defaultHeight: CGFloat = 210

    static let minWidth: CGFloat = 280
    static let maxWidth: CGFloat = 500
    static let minHeight: CGFloat = 100
    static let maxHeight: CGFloat = 400

    init() {
        let savedWidth = UserDefaults.standard.double(forKey: "notchWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "textAreaHeight")
        self.notchWidth = savedWidth > 0 ? CGFloat(savedWidth) : Self.defaultWidth
        self.textAreaHeight = savedHeight > 0 ? CGFloat(savedHeight) : Self.defaultHeight
        self.fontSizePreset = FontSizePreset(rawValue: UserDefaults.standard.string(forKey: "fontSizePreset") ?? "") ?? .lg
        self.fontFamilyPreset = FontFamilyPreset(rawValue: UserDefaults.standard.string(forKey: "fontFamilyPreset") ?? "") ?? .sans
        self.fontColorPreset = FontColorPreset(rawValue: UserDefaults.standard.string(forKey: "fontColorPreset") ?? "") ?? .white
        self.overlayMode = OverlayMode(rawValue: UserDefaults.standard.string(forKey: "overlayMode") ?? "") ?? .pinned
        self.notchDisplayMode = NotchDisplayMode(rawValue: UserDefaults.standard.string(forKey: "notchDisplayMode") ?? "") ?? .followMouse
        let savedPinnedScreenID = UserDefaults.standard.integer(forKey: "pinnedScreenID")
        self.pinnedScreenID = UInt32(savedPinnedScreenID)
        self.floatingGlassEffect = UserDefaults.standard.object(forKey: "floatingGlassEffect") as? Bool ?? false
        let savedOpacity = UserDefaults.standard.double(forKey: "glassOpacity")
        self.glassOpacity = savedOpacity > 0 ? savedOpacity : 0.15
        self.listeningMode = ListeningMode(rawValue: UserDefaults.standard.string(forKey: "listeningMode") ?? "") ?? .wordTracking
        let savedSpeed = UserDefaults.standard.double(forKey: "scrollSpeed")
        self.scrollSpeed = savedSpeed > 0 ? savedSpeed : 3

        // Quran settings
        self.quranReminderInterval = UserDefaults.standard.object(forKey: "quranReminderInterval") as? Int ?? 30
        let savedLengthSec = UserDefaults.standard.object(forKey: "quranReadingLengthSeconds") as? Int
        self.quranReadingLengthSeconds = savedLengthSec ?? 30
        self.quranSnoozeDurationMinutes = UserDefaults.standard.object(forKey: "quranSnoozeDurationMinutes") as? Int ?? 5
        self.quranCurrentSurah = UserDefaults.standard.object(forKey: "quranCurrentSurah") as? Int ?? 1
        self.quranCurrentAyah = UserDefaults.standard.object(forKey: "quranCurrentAyah") as? Int ?? 1
        let savedQuranFontSize = UserDefaults.standard.double(forKey: "quranFontSize")
        self.quranFontSize = savedQuranFontSize > 0 ? CGFloat(savedQuranFontSize) : 22
        self.quranFontPreset = QuranFontPreset(rawValue: UserDefaults.standard.string(forKey: "quranFontPreset") ?? "") ?? .uthmanic
        self.hasCompletedOnboarding = UserDefaults.standard.object(forKey: "hasCompletedOnboarding") as? Bool ?? false
    }
}
