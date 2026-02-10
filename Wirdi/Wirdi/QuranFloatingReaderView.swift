//
//  QuranFloatingReaderView.swift
//  Wirdi
//
//  Floating-window Quran reader. Mirrors FloatingOverlayView's look
//  (rounded rect, glass effect, draggable panel) but carries the
//  Quran-specific elements from QuranReaderView (surah header,
//  Uthmanic font, RTL layout, complete/dismiss callbacks).
//

import SwiftUI
import Combine

struct QuranFloatingReaderView: View {
    let segment: QuranReadingSegment
    let words: [String]
    let totalCharCount: Int
    @Bindable var speechRecognizer: SpeechRecognizer
    var onComplete: (() -> Void)?
    var onDismiss: ((Int) -> Void)?

    @State private var appeared = false
    @State private var showThankYou = false

    // Timer-based scroll
    @State private var timerWordProgress: Double = 0
    @State private var isPaused = false
    @State private var isUserScrolling = false
    private let scrollTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var settings: NotchSettings { NotchSettings.shared }

    private var listeningMode: ListeningMode {
        settings.listeningMode
    }

    // MARK: - Progress helpers


    private var effectiveCharCount: Int {
        switch listeningMode {
        case .wordTracking:
            return speechRecognizer.recognizedCharCount
        case .classic, .silencePaused:
            return charOffsetForWordProgress(timerWordProgress, words: words, totalCharCount: totalCharCount)
        }
    }

    var isDone: Bool {
        totalCharCount > 0 && effectiveCharCount >= totalCharCount
    }

    private var isEffectivelyListening: Bool {
        switch listeningMode {
        case .wordTracking, .silencePaused:
            return speechRecognizer.isListening
        case .classic:
            return !isPaused
        }
    }

    // MARK: - Header

    private var ayahRangeText: String {
        if segment.startAyah == segment.endAyah {
            return "آية \(segment.startAyah)"
        }
        return "\(segment.startAyah)-\(segment.endAyah)"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if showThankYou || isDone {
                thankYouView
            } else {
                quranPrompterView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
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
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.9)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
        .onChange(of: speechRecognizer.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss {
                withAnimation(.easeIn(duration: 0.25)) {
                    appeared = false
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isDone)
        .animation(.easeInOut(duration: 0.5), value: showThankYou)
        .onChange(of: isDone) { _, done in
            if done {
                withAnimation {
                    showThankYou = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    onComplete?()
                    speechRecognizer.shouldDismiss = true
                }
            }
        }
        .onReceive(scrollTimer) { _ in
            guard !isDone, !isUserScrolling else { return }
            let speed = settings.scrollSpeed
            switch listeningMode {
            case .classic:
                if !isPaused {
                    timerWordProgress += speed * 0.05
                }
            case .silencePaused:
                if !isPaused && speechRecognizer.isListening && speechRecognizer.isSpeaking {
                    timerWordProgress += speed * 0.05
                }
            case .wordTracking:
                break
            }
        }
    }

    // MARK: - Quran Prompter

    private var quranPrompterView: some View {
        VStack(spacing: 0) {
            // Surah header
            HStack(spacing: 6) {
                Text(QuranDataManager.surahLigature(segment.surahNumber))
                    .font(Font(QuranDataManager.surahNameFont(size: 18)))
                    .foregroundStyle(.white.opacity(0.45))
                Text(ayahRangeText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.top, 10)
            .padding(.bottom, 2)

            // Arabic text with RTL
            SpeechScrollView(
                words: words,
                highlightedCharCount: effectiveCharCount,
                font: settings.quranFont,
                highlightColor: settings.fontColorPreset.color,
                onWordTap: { charOffset in
                    if listeningMode == .wordTracking {
                        speechRecognizer.jumpTo(charOffset: charOffset)
                    } else {
                        timerWordProgress = wordProgressForCharOffset(charOffset, words: words)
                    }
                },
                onManualScroll: { scrolling, newProgress in
                    isUserScrolling = scrolling
                    if !scrolling {
                        timerWordProgress = max(0, min(Double(words.count), newProgress))
                    }
                },
                smoothScroll: listeningMode != .wordTracking,
                smoothWordProgress: timerWordProgress,
                isListening: isEffectivelyListening
            )
            .environment(\.layoutDirection, .rightToLeft)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Bottom controls
            HStack(alignment: .center, spacing: 8) {
                AudioWaveformProgressView(
                    levels: speechRecognizer.audioLevels,
                    progress: totalCharCount > 0
                        ? Double(effectiveCharCount) / Double(totalCharCount)
                        : 0
                )
                .frame(width: 120, height: 24)

                Spacer()

                if listeningMode == .classic {
                    Button {
                        isPaused.toggle()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isPaused ? .white.opacity(0.6) : .green.opacity(0.8))
                            .frame(width: 24, height: 24)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        if speechRecognizer.isListening {
                            speechRecognizer.stop()
                        } else {
                            speechRecognizer.resume()
                        }
                    } label: {
                        Image(systemName: speechRecognizer.isListening ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(speechRecognizer.isListening ? .green.opacity(0.8) : .white.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Finish reading — triggers thank-you page
                Button {
                    withAnimation {
                        showThankYou = true
                    }
                    onComplete?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        speechRecognizer.forceStop()
                        speechRecognizer.shouldDismiss = true
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Close without completing
                Button {
                    onDismiss?(effectiveCharCount)
                    speechRecognizer.forceStop()
                    speechRecognizer.shouldDismiss = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 24)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Thank You View

    private var thankYouView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            Text("جزاك الله خيرًا")
                .font(Font(FontFamilyPreset.quran.font(size: 20)))
                .foregroundStyle(.white)
            Text("May Allah reward you")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }
}
