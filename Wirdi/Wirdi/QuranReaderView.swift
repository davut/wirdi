//
//  QuranReaderView.swift
//  Wirdi
//
//  Quran reading overlay displayed in the notch. Reuses SpeechScrollView
//  with the Uthmanic Hafs font and right-to-left layout.
//

import SwiftUI
import Combine

struct QuranReaderView: View {
    let segment: QuranReadingSegment
    let words: [String]
    let totalCharCount: Int
    @Bindable var speechRecognizer: SpeechRecognizer
    let menuBarHeight: CGFloat
    let baseTextHeight: CGFloat
    let maxExtraHeight: CGFloat
    var frameTracker: NotchFrameTracker
    var onComplete: (() -> Void)?
    var onDismiss: ((Int) -> Void)?

    // Animation state
    @State private var expansion: CGFloat = 0
    @State private var contentVisible = false
    @State private var extraHeight: CGFloat = 0
    @State private var isHovering = false
    @State private var dragStartHeight: CGFloat = -1
    @State private var showThankYou = false

    // Timer-based scroll
    @State private var timerWordProgress: Double = 0
    @State private var isPaused = false
    @State private var isUserScrolling = false
    private let scrollTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let topInset: CGFloat = 16
    private let collapsedInset: CGFloat = 8
    private let notchHeight: CGFloat = 37
    private let notchWidth: CGFloat = 200

    private var settings: NotchSettings { NotchSettings.shared }

    private var listeningMode: ListeningMode {
        settings.listeningMode
    }



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

    private var currentTopInset: CGFloat {
        collapsedInset + (topInset - collapsedInset) * expansion
    }

    private var currentBottomRadius: CGFloat {
        8 + (18 - 8) * expansion
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
        GeometryReader { geo in
            let targetHeight = menuBarHeight + baseTextHeight + extraHeight
            let currentHeight = notchHeight + (targetHeight - notchHeight) * expansion
            let currentWidth = notchWidth + (geo.size.width - notchWidth) * expansion

            ZStack(alignment: .top) {
                DynamicIslandShape(
                    topInset: currentTopInset,
                    bottomRadius: currentBottomRadius
                )
                .fill(.black)
                .frame(width: currentWidth, height: currentHeight)

                if contentVisible {
                    VStack(spacing: 0) {
                        Spacer().frame(height: menuBarHeight)

                        if showThankYou || isDone {
                            thankYouView
                        } else {
                            quranPrompterView(geoWidth: geo.size.width)
                        }
                    }
                    .padding(.horizontal, topInset)
                    .frame(width: geo.size.width, height: targetHeight)
                    .transition(.opacity)
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onChange(of: extraHeight) { _, _ in updateFrameTracker() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                expansion = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.25)) {
                    contentVisible = true
                }
            }
        }
        .onChange(of: speechRecognizer.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss {
                withAnimation(.easeIn(duration: 0.15)) {
                    contentVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        expansion = 0
                    }
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

    private func updateFrameTracker() {
        let targetHeight = menuBarHeight + baseTextHeight + extraHeight
        frameTracker.visibleHeight = targetHeight
        frameTracker.visibleWidth = settings.notchWidth
    }

    // MARK: - Quran Prompter

    private func quranPrompterView(geoWidth: CGFloat) -> some View {
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
            .padding(.top, 4)
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
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))

            // Bottom controls
            Group {
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
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

                // Resize handle
                if isHovering {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 36, height: 4)
                        Spacer().frame(height: 8)
                    }
                    .frame(height: 16)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { value in
                                if dragStartHeight < 0 { dragStartHeight = extraHeight }
                                extraHeight = max(0, min(maxExtraHeight, dragStartHeight + value.translation.height))
                            }
                            .onEnded { _ in dragStartHeight = -1 }
                    )
                    .onHover { hovering in
                        if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
            .transition(.opacity)
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
