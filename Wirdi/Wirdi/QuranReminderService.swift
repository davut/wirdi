//
//  QuranReminderService.swift
//  Wirdi
//
//  Manages Quran reading reminders: schedules timers, shows the prompt
//  panel, presents the reading overlay, and tracks progress.
//

import AppKit
import SwiftUI

@Observable
class QuranReminderService {
    static let shared = QuranReminderService()

    private(set) var isPromptShowing = false
    private(set) var isReaderShowing = false
    var onReaderDismissed: (() -> Void)?

    private var reminderTimer: Timer?
    private var promptPanel: NSPanel?
    private var readerPanel: NSPanel?
    private var readerFrameTracker: NotchFrameTracker?
    private let speechRecognizer = SpeechRecognizer()
    private var isDismissingReader = false
    private var currentSegment: QuranReadingSegment?
    private var isManualRead = false
    private var readingCompleted = false

    private var settings: NotchSettings { NotchSettings.shared }

    // MARK: - Lifecycle

    func startIfEnabled() {
        scheduleNextReminder()
    }

    func settingsChanged() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        scheduleNextReminder()
    }

    // MARK: - Scheduling

    private func scheduleNextReminder() {
        reminderTimer?.invalidate()
        let interval = max(60, TimeInterval(settings.quranReminderInterval * 60))

        reminderTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showPrompt()
            }
        }
    }

    private func scheduleSnooze() {
        reminderTimer?.invalidate()
        let snoozeSeconds = TimeInterval(settings.quranSnoozeDurationMinutes * 60)
        reminderTimer = Timer.scheduledTimer(withTimeInterval: snoozeSeconds, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showPrompt()
            }
        }
    }

    // MARK: - Prompt

    func showPrompt() {
        // Don't show if reader or prompt is already active; reschedule instead
        guard !isPromptShowing, !isReaderShowing else {
            scheduleNextReminder()
            return
        }

        // Load data and get next segment (~100 words per minute)
        let targetWords = max(10, settings.quranReadingLengthSeconds * 100 / 60)
        guard let segment = QuranDataManager.shared.getReadingSegment(
            fromSurah: settings.quranCurrentSurah,
            fromAyah: settings.quranCurrentAyah,
            targetWordCount: targetWords
        ) else { return }

        currentSegment = segment

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let panelWidth: CGFloat = settings.notchWidth
        let panelHeight = menuBarHeight + 32

        let ayahRange: String
        if segment.startAyah == segment.endAyah {
            ayahRange = "\(segment.surahNumber):\(segment.startAyah)"
        } else {
            ayahRange = "\(segment.surahNumber):\(segment.startAyah)-\(segment.endAyah)"
        }

        let promptView = QuranPromptView(
            surahNumber: segment.surahNumber,
            ayahRange: ayahRange,
            onStart: { [weak self] in
                self?.dismissPrompt()
                // Brief delay so prompt animation completes before reader appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.showReader(segment: segment)
                }
            },
            onLater: { [weak self] in
                self?.dismissPrompt()
                self?.scheduleSnooze()
            },
            menuBarHeight: menuBarHeight
        )

        let contentView = NSHostingView(rootView: promptView)
        let xPosition = screenFrame.midX - panelWidth / 2
        let yPosition = screenFrame.maxY - panelHeight

        let panel = NSPanel(
            contentRect: NSRect(x: xPosition, y: yPosition, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
        panel.contentView = contentView

        panel.orderFrontRegardless()
        self.promptPanel = panel
        self.isPromptShowing = true
    }

    private func dismissPrompt() {
        promptPanel?.orderOut(nil)
        promptPanel = nil
        isPromptShowing = false
    }

    // MARK: - Reader

    private func showReader(segment: QuranReadingSegment) {
        isDismissingReader = false

        switch settings.overlayMode {
        case .pinned:
            showPinnedReader(segment: segment)
        case .floating:
            showFloatingReader(segment: segment)
        }

        // Start speech recognition if in word tracking or silence-paused mode
        if settings.listeningMode != .classic {
            speechRecognizer.start(with: segment.displayText)
        }

        // Observe dismiss signal
        observeReaderDismiss()
    }

    private func showPinnedReader(segment: QuranReadingSegment) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        let panelWidth = settings.notchWidth
        let textAreaHeight = settings.textAreaHeight

        let (words, totalCharCount) = parseSegmentWords(segment)

        let tracker = NotchFrameTracker()
        tracker.screenMidX = screenFrame.midX
        tracker.screenMaxY = screenFrame.maxY
        tracker.menuBarHeight = menuBarHeight
        tracker.visibleWidth = panelWidth
        tracker.visibleHeight = menuBarHeight + textAreaHeight
        self.readerFrameTracker = tracker

        let readerView = QuranReaderView(
            segment: segment,
            words: words,
            totalCharCount: totalCharCount,
            speechRecognizer: speechRecognizer,
            menuBarHeight: menuBarHeight,
            baseTextHeight: textAreaHeight,
            maxExtraHeight: 350,
            frameTracker: tracker,
            onComplete: { [weak self] in
                self?.onReadingComplete(segment: segment)
            },
            onDismiss: { [weak self] charOffset in
                guard let self, !self.readingCompleted, charOffset > 0 else { return }
                let ayah = segment.ayahAt(charOffset: charOffset)
                self.settings.quranCurrentAyah = ayah
            }
        )

        let contentView = NSHostingView(rootView: readerView)

        let targetHeight = menuBarHeight + textAreaHeight
        let xPosition = screenFrame.midX - panelWidth / 2
        let yPosition = screenFrame.maxY - targetHeight

        let panel = NSPanel(
            contentRect: NSRect(x: xPosition, y: yPosition, width: panelWidth, height: targetHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tracker.panel = panel

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
        panel.contentView = contentView

        panel.orderFrontRegardless()
        self.readerPanel = panel
        self.isReaderShowing = true
    }

    private func showFloatingReader(segment: QuranReadingSegment) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let panelWidth = settings.notchWidth
        let panelHeight = settings.textAreaHeight

        let (words, totalCharCount) = parseSegmentWords(segment)

        let floatingView = QuranFloatingReaderView(
            segment: segment,
            words: words,
            totalCharCount: totalCharCount,
            speechRecognizer: speechRecognizer,
            onComplete: { [weak self] in
                self?.onReadingComplete(segment: segment)
            },
            onDismiss: { [weak self] charOffset in
                guard let self, !self.readingCompleted, charOffset > 0 else { return }
                let ayah = segment.ayahAt(charOffset: charOffset)
                self.settings.quranCurrentAyah = ayah
            }
        )

        let contentView = NSHostingView(rootView: floatingView)

        let xPosition = screenFrame.midX - panelWidth / 2
        let yPosition = screenFrame.midY - panelHeight / 2 + 100

        let panel = NSPanel(
            contentRect: NSRect(x: xPosition, y: yPosition, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        panel.contentView = contentView

        panel.orderFrontRegardless()
        self.readerPanel = panel
        self.isReaderShowing = true
    }

    private func parseSegmentWords(_ segment: QuranReadingSegment) -> ([String], Int) {
        let normalized = segment.displayText
            .replacingOccurrences(of: "\n", with: " ")
            .split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            .map { String($0) }
        let totalCharCount = normalized.joined(separator: " ").count
        return (normalized, totalCharCount)
    }

    private func observeReaderDismiss() {
        // Use observation tracking instead of polling — fires only when shouldDismiss changes.
        func observe() {
            withObservationTracking {
                _ = self.speechRecognizer.shouldDismiss
            } onChange: { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.isReaderShowing else { return }
                    if self.speechRecognizer.shouldDismiss && !self.isDismissingReader {
                        self.isDismissingReader = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.dismissReader()
                        }
                    } else {
                        // Re-observe for future changes
                        observe()
                    }
                }
            }
        }
        observe()
    }

    private func dismissReader() {
        speechRecognizer.forceStop()
        speechRecognizer.shouldDismiss = false
        readerPanel?.orderOut(nil)
        readerPanel = nil
        readerFrameTracker = nil
        isReaderShowing = false
        let wasCompleted = readingCompleted
        readingCompleted = false
        if isManualRead {
            onReaderDismissed?()
            isManualRead = false
        }
        // If dismissed early (not completed), reschedule so reminders don't stop
        if !wasCompleted {
            scheduleNextReminder()
        }
    }

    private func onReadingComplete(segment: QuranReadingSegment) {
        readingCompleted = true

        // Update reading position
        let next = QuranDataManager.shared.nextPosition(after: segment)
        settings.quranCurrentSurah = next.surah
        settings.quranCurrentAyah = next.ayah

        // Schedule next reminder
        scheduleNextReminder()
    }

    // MARK: - Manual triggers

    func triggerNow() {
        reminderTimer?.invalidate()
        showPrompt()
    }

    /// Start reading immediately without showing the prompt panel.
    func readNow() {
        guard !isReaderShowing else { return }

        // Dismiss prompt if showing
        if isPromptShowing {
            dismissPrompt()
        }

        let targetWords = max(10, settings.quranReadingLengthSeconds * 100 / 60)
        guard let segment = QuranDataManager.shared.getReadingSegment(
            fromSurah: settings.quranCurrentSurah,
            fromAyah: settings.quranCurrentAyah,
            targetWordCount: targetWords
        ) else { return }

        currentSegment = segment
        isManualRead = true
        showReader(segment: segment)
    }
}
