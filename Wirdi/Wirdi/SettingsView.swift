//
//  SettingsView.swift
//  Wirdi
//
//

import SwiftUI
import AppKit
import Speech
import Combine

// MARK: - Preview Panel Controller

class NotchPreviewController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchPreviewContent>?

    func show(settings: NotchSettings) {
        // If panel already exists, just re-show it
        if let panel {
            panel.orderFront(nil)
            return
        }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY

        let maxWidth = NotchSettings.maxWidth
        let maxHeight = menuBarHeight + NotchSettings.maxHeight + 40

        let xPosition = screenFrame.midX - maxWidth / 2
        let yPosition = screenFrame.maxY - maxHeight

        let content = NotchPreviewContent(settings: settings, menuBarHeight: menuBarHeight)
        let hostingView = NSHostingView(rootView: content)
        self.hostingView = hostingView

        let panel = NSPanel(
            contentRect: NSRect(x: xPosition, y: yPosition, width: maxWidth, height: maxHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
}

struct NotchPreviewContent: View {
    @Bindable var settings: NotchSettings
    let menuBarHeight: CGFloat

    private static let previewWords = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ مَٰلِكِ يَوۡمِ ٱلدِّينِ إِيَّاكَ نَعۡبُدُ وَإِيَّاكَ نَسۡتَعِينُ ٱهۡدِنَا ٱلصِّرَٰطَ ٱلۡمُسۡتَقِيمَ صِرَٰطَ ٱلَّذِينَ أَنۡعَمۡتَ عَلَيۡهِمۡ غَيۡرِ ٱلۡمَغۡضُوبِ عَلَيۡهِمۡ وَلَا ٱلضَّآلِّينَ".split(separator: " ").map(String.init)

    private let highlightedCount = 42
    @State private var previewWordProgress: Double = 0
    private let scrollTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    // Phase 1: corners flatten (0=concave, 1=squared)
    @State private var cornerPhase: CGFloat = 0
    // Phase 2: detach from top (0=stuck to top, 1=moved down + rounded)
    @State private var offsetPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let topPadding = menuBarHeight * (1 - offsetPhase) + 14 * offsetPhase
            let contentHeight = topPadding + settings.textAreaHeight
            let currentWidth = settings.notchWidth
            let yOffset = 60 * offsetPhase

            ZStack(alignment: .top) {
                // Shape: concave corners flatten via cornerPhase, then cross-fade to rounded via offsetPhase
                DynamicIslandShape(
                    topInset: 16 * (1 - cornerPhase),
                    bottomRadius: 18
                )
                .fill(.black)
                .opacity(Double(1 - offsetPhase))
                .frame(width: currentWidth, height: contentHeight)

                Group {
                    if settings.floatingGlassEffect {
                        ZStack {
                            GlassEffectView()
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.black.opacity(settings.glassOpacity))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black)
                    }
                }
                .opacity(Double(offsetPhase))
                .frame(width: currentWidth, height: contentHeight)

                VStack(spacing: 0) {
                    Spacer().frame(height: topPadding)

                    SpeechScrollView(
                        words: Self.previewWords,
                        highlightedCharCount: settings.listeningMode == .wordTracking ? highlightedCount : Self.previewWords.count * 5,
                        font: settings.quranFont,
                        highlightColor: settings.fontColorPreset.color,
                        smoothScroll: settings.listeningMode != .wordTracking,
                        smoothWordProgress: previewWordProgress,
                        isListening: settings.listeningMode != .wordTracking
                    )
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .frame(width: currentWidth, height: contentHeight)
            }
            .frame(width: currentWidth, height: contentHeight, alignment: .top)
            .offset(y: yOffset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(.easeInOut(duration: 0.15), value: settings.notchWidth)
            .animation(.easeInOut(duration: 0.15), value: settings.textAreaHeight)
        }
        .onChange(of: settings.overlayMode) { _, mode in
            if mode == .floating {
                // Phase 1: flatten corners while at top
                withAnimation(.easeInOut(duration: 0.25)) {
                    cornerPhase = 1
                }
                // Phase 2: move down + round corners
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        offsetPhase = 1
                    }
                }
            } else {
                // Reverse Phase 1: move back up to top
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    offsetPhase = 0
                }
                // Reverse Phase 2: restore concave corners
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        cornerPhase = 0
                    }
                }
            }
        }
        .onAppear {
            let isFloating = settings.overlayMode == .floating
            cornerPhase = isFloating ? 1 : 0
            offsetPhase = isFloating ? 1 : 0
        }
        .onReceive(scrollTimer) { _ in
            guard settings.listeningMode != .wordTracking else { return }
            let wordCount = Double(Self.previewWords.count)
            previewWordProgress += settings.scrollSpeed * 0.05
            if previewWordProgress >= wordCount {
                previewWordProgress = 0
            }
        }
        .onChange(of: settings.listeningMode) { _, mode in
            if mode != .wordTracking {
                previewWordProgress = 0
            }
        }
    }
}

// MARK: - Settings Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case quran, general, listeningMode, font, fontColor, overlayMode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quran: return "Quran"
        case .general: return "Size"
        case .listeningMode: return "Guidance"
        case .font: return "Font"
        case .fontColor: return "Color"
        case .overlayMode: return "Overlay"
        }
    }

    var icon: String {
        switch self {
        case .quran: return "book.fill"
        case .general: return "arrow.up.left.and.arrow.down.right"
        case .listeningMode: return "waveform"
        case .font: return "textformat"
        case .fontColor: return "paintpalette"
        case .overlayMode: return "macwindow"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var settings: NotchSettings
    @Environment(\.dismiss) private var dismiss
    @State private var previewController = NotchPreviewController()
    @State private var selectedTab: SettingsTab = .quran
    @State private var showResetConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)

                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 16)
                            Text(tab.label)
                                .font(.system(size: 13, weight: .regular))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("Reset") {
                    showResetConfirmation = true
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        resetAllSettings()
                    }
                } message: {
                    Text("This will reset all settings to their defaults, including your Quran reading progress.")
                }
            }
            .padding(12)
            .frame(width: 140)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.04))

            Divider()

            // Content
            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        switch selectedTab {
                        case .quran:
                            QuranSettingsView(settings: settings)
                        case .general:
                            generalTab
                        case .listeningMode:
                            listeningModeTab
                        case .font:
                            fontTab
                        case .fontColor:
                            fontColorTab
                        case .overlayMode:
                            overlayModeTab
                        }
                    }
                    .padding(16)
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 500)
        .frame(minHeight: 280, maxHeight: 500)
        .background(.ultraThinMaterial)
        .onAppear {
            previewController.show(settings: settings)
        }
        .onDisappear {
            previewController.dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            previewController.hide()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            previewController.show(settings: settings)
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(spacing: 14) {
            // Width slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Width")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(settings.notchWidth))px")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $settings.notchWidth,
                    in: NotchSettings.minWidth...NotchSettings.maxWidth,
                    step: 10
                )
            }

            // Height slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Height")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(settings.textAreaHeight))px")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $settings.textAreaHeight,
                    in: NotchSettings.minHeight...NotchSettings.maxHeight,
                    step: 10
                )
            }

        }
    }

    // MARK: - Listening Mode Tab

    private var listeningModeTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $settings.listeningMode) {
                ForEach(ListeningMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(settings.listeningMode.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if settings.listeningMode != .wordTracking {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Scroll Speed")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(String(format: "%.1f words/s", settings.scrollSpeed))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $settings.scrollSpeed,
                        in: 0.5...8,
                        step: 0.5
                    )
                    HStack {
                        Text("Slower")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Faster")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Font Tab

    private var fontTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quran Font")
                .font(.system(size: 13, weight: .medium))

            HStack(spacing: 8) {
                ForEach(QuranFontPreset.allCases) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.quranFontPreset = preset
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("بسم")
                                .font(Font(preset.font(size: 16)))
                                .frame(height: 24)
                            Text(preset.label)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(settings.quranFontPreset == preset ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(settings.quranFontPreset == preset ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Font Size")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(Int(settings.quranFontSize))pt")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.quranFontSize, in: 16...36, step: 2)
            }

            // Font preview
            Text("بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ")
                .font(Font(settings.quranFont))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                )
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    // MARK: - Font Color Tab

    private var fontColorTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlight Color")
                .font(.system(size: 13, weight: .medium))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                ForEach(FontColorPreset.allCases) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.fontColorPreset = preset
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                                .overlay(
                                    settings.fontColorPreset == preset
                                        ? Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(preset == .white ? .black : .white)
                                        : nil
                                )
                            Text(preset.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(settings.fontColorPreset == preset ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(settings.fontColorPreset == preset ? preset.color.opacity(0.1) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(settings.fontColorPreset == preset ? preset.color.opacity(0.4) : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Overlay Mode Tab

    @State private var overlayScreens: [NSScreen] = []

    private var overlayModeTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $settings.overlayMode) {
                ForEach(OverlayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(settings.overlayMode.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if settings.overlayMode == .pinned {
                Divider()

                Text("Display")
                    .font(.system(size: 13, weight: .medium))

                Picker("", selection: $settings.notchDisplayMode) {
                    ForEach(NotchDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(settings.notchDisplayMode.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if settings.notchDisplayMode == .fixedDisplay {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(overlayScreens, id: \.displayID) { screen in
                            Button {
                                settings.pinnedScreenID = screen.displayID
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "display")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(settings.pinnedScreenID == screen.displayID ? Color.accentColor : .secondary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(screen.displayName)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(settings.pinnedScreenID == screen.displayID ? Color.accentColor : .primary)
                                        Text("\(Int(screen.frame.width))×\(Int(screen.frame.height))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settings.pinnedScreenID == screen.displayID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(settings.pinnedScreenID == screen.displayID ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            refreshOverlayScreens()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Refresh")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if settings.overlayMode == .floating {
                Divider()

                Toggle(isOn: $settings.floatingGlassEffect) {
                    Text("Glass Effect")
                        .font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if settings.floatingGlassEffect {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Glass Opacity")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Int(settings.glassOpacity * 100))%")
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $settings.glassOpacity,
                            in: 0.0...0.6,
                            step: 0.05
                        )
                    }
                }
            }
        }
        .onAppear { refreshOverlayScreens() }
    }

    private func refreshOverlayScreens() {
        overlayScreens = NSScreen.screens
        if settings.pinnedScreenID == 0, let main = NSScreen.main {
            settings.pinnedScreenID = main.displayID
        }
    }

    private func resetAllSettings() {
        settings.notchWidth = NotchSettings.defaultWidth
        settings.textAreaHeight = NotchSettings.defaultHeight
        settings.fontSizePreset = .lg
        settings.fontFamilyPreset = .sans
        settings.fontColorPreset = .white
        settings.overlayMode = .pinned
        settings.notchDisplayMode = .followMouse
        settings.pinnedScreenID = 0
        settings.floatingGlassEffect = false
        settings.glassOpacity = 0.15
        settings.listeningMode = .wordTracking
        settings.scrollSpeed = 3
        settings.quranReminderInterval = 30
        settings.quranReadingLengthSeconds = 30
        settings.quranCurrentSurah = 1
        settings.quranCurrentAyah = 1
        settings.quranFontSize = 22
        settings.quranFontPreset = .uthmanic
        QuranReminderService.shared.settingsChanged()
    }
}
