//
//  OnboardingView.swift
//  Wirdi
//
//  First-launch onboarding flow for Quran Reader.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = NotchSettings.shared
    @State private var currentPage = 0

    private let pageCount = 4
    private let totalQuranWords = 77_430
    private let activeHoursPerDay = 8.0

    private var estimatedCompletionText: String {
        let interval = max(1, settings.quranReminderInterval)
        let wordsPerSession = max(10, settings.quranReadingLengthSeconds * 100 / 60)
        let sessionsPerDay = activeHoursPerDay * 60.0 / Double(interval)
        let wordsPerDay = Double(wordsPerSession) * sessionsPerDay
        guard wordsPerDay > 0 else { return "—" }
        let days = Int(ceil(Double(totalQuranWords) / wordsPerDay))
        if days == 1 { return "Complete the Quran in about 1 day" }
        if days < 365 { return "Complete the Quran in about \(days) days" }
        let months = Int(round(Double(days) / 30.0))
        return "Complete the Quran in about \(months) months"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Page content — manual paging with transition
            ZStack {
                Group {
                    switch currentPage {
                    case 0: welcomePage
                    case 1: howItWorksPage
                    case 2: readingPacePage
                    default: setupPage
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(currentPage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Bottom navigation bar
            VStack(spacing: 14) {
                // Page indicator dots
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.accentColor : Color.primary.opacity(0.15))
                            .frame(width: index == currentPage ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.35), value: currentPage)
                    }
                }

                // Buttons
                HStack(spacing: 12) {
                    if currentPage > 0 {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                currentPage -= 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Back")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if currentPage < pageCount - 1 {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                currentPage += 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Next")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
        .frame(width: 440, height: 480)
        .background(.ultraThinMaterial)
        .onKeyPress(.rightArrow) {
            if currentPage < pageCount - 1 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentPage += 1 }
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if currentPage > 0 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentPage -= 1 }
            }
            return .handled
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon with glow
            ZStack {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 20, y: 4)
                }
            }

            Spacer().frame(height: 20)

            Text("Wirdi")
                .font(.system(size: 32, weight: .bold))

            Spacer().frame(height: 10)

            Text("Read Quran throughout your day\nwith gentle reminders")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer().frame(height: 28)

            // Decorative bismillah in a subtle card
            Text("بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ")
                .font(Font(FontFamilyPreset.quran.font(size: 26)))
                .foregroundStyle(.primary.opacity(0.5))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.04))
                )
                .environment(\.layoutDirection, .rightToLeft)

            Spacer()
        }
        .padding(.horizontal, 36)
    }

    // MARK: - Page 2: How It Works

    private var howItWorksPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            Text("How It Works")
                .font(.system(size: 24, weight: .bold))

            Spacer().frame(height: 8)

            Text("Three simple steps to daily reading")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 28)

            VStack(spacing: 16) {
                featureCard(
                    icon: "bell.badge",
                    color: .orange,
                    title: "Gentle Reminders",
                    description: "A reminder appears in your notch at your chosen interval"
                )

                featureCard(
                    icon: "text.word.spacing",
                    color: .blue,
                    title: "Word-by-Word Display",
                    description: "Arabic text displays beautifully with voice tracking"
                )

                featureCard(
                    icon: "bookmark.fill",
                    color: .green,
                    title: "Auto-Save Progress",
                    description: "Pick up exactly where you left off, every time"
                )
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    private func featureCard(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Page 3: Reading Pace

    private var readingPacePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)

            Text("Reading Pace")
                .font(.system(size: 24, weight: .bold))

            Spacer().frame(height: 8)

            Text("A little each day completes the whole Quran")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 24)

            // Pace cards
            VStack(spacing: 10) {
                paceCard(
                    interval: "Every 15 min",
                    length: "~30 sec each",
                    days: "48",
                    icon: "hare",
                    highlight: false
                )
                paceCard(
                    interval: "Every 30 min",
                    length: "~1 min each",
                    days: "48",
                    icon: "figure.walk",
                    highlight: true
                )
                paceCard(
                    interval: "Every 1 hour",
                    length: "~2 min each",
                    days: "49",
                    icon: "tortoise",
                    highlight: false
                )
            }
            .padding(.horizontal, 28)

            Spacer().frame(height: 16)

            Text("All paces finish in roughly the same time")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private func paceCard(interval: String, length: String, days: String, icon: String, highlight: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(highlight ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(interval)
                    .font(.system(size: 13, weight: .medium))
                Text(length)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(days)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(highlight ? Color.accentColor : .primary)
                Text("days")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(highlight ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(highlight ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Page 4: Setup & Start

    private var setupPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            Text("Set Up Your Reading")
                .font(.system(size: 24, weight: .bold))

            Spacer().frame(height: 8)

            Text("You can change these anytime in settings")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 16) {
                // Reminder interval
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remind every")
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Picker("", selection: Binding(
                                get: { settings.quranReminderInterval / 60 },
                                set: { settings.quranReminderInterval = $0 * 60 + settings.quranReminderInterval % 60 }
                            )) {
                                ForEach(0...12, id: \.self) { h in Text("\(h)h").tag(h) }
                            }
                            .labelsHidden()
                            .frame(width: 70)
                        }
                        HStack(spacing: 4) {
                            Picker("", selection: Binding(
                                get: { settings.quranReminderInterval % 60 },
                                set: { settings.quranReminderInterval = (settings.quranReminderInterval / 60) * 60 + $0 }
                            )) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { m in Text("\(m)m").tag(m) }
                            }
                            .labelsHidden()
                            .frame(width: 70)
                        }
                    }
                }

                // Reading length
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reading length")
                        .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Picker("", selection: Binding(
                                get: { settings.quranReadingLengthSeconds / 60 },
                                set: { settings.quranReadingLengthSeconds = max(10, $0 * 60 + settings.quranReadingLengthSeconds % 60) }
                            )) {
                                ForEach(0...60, id: \.self) { m in Text("\(m)m").tag(m) }
                            }
                            .labelsHidden()
                            .frame(width: 70)
                        }
                        HStack(spacing: 4) {
                            Picker("", selection: Binding(
                                get: { settings.quranReadingLengthSeconds % 60 / 10 * 10 },
                                set: { settings.quranReadingLengthSeconds = max(10, (settings.quranReadingLengthSeconds / 60) * 60 + $0) }
                            )) {
                                ForEach(Array(stride(from: 0, through: 50, by: 10)), id: \.self) { s in Text("\(s)s").tag(s) }
                            }
                            .labelsHidden()
                            .frame(width: 70)
                        }
                    }
                }

            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 28)

            Spacer().frame(height: 16)

            // Estimated completion
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(estimatedCompletionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Get Started button
            Button {
                settings.hasCompletedOnboarding = true
                QuranReminderService.shared.settingsChanged()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Text("Get Started")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)

            Spacer().frame(height: 16)
        }
    }
}
