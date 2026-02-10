//
//  QuranSettingsView.swift
//  Wirdi
//
//  Settings tab for Quran reading reminders.
//

import SwiftUI

struct QuranSettingsView: View {
    @Bindable var settings: NotchSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Reminder interval
            VStack(alignment: .leading, spacing: 6) {
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
                .onChange(of: settings.quranReminderInterval) { _, _ in
                    QuranReminderService.shared.settingsChanged()
                }
            }

            Divider()

            // Reading length
            VStack(alignment: .leading, spacing: 6) {
                Text("Reading length")
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Picker("", selection: Binding(
                            get: { min(settings.quranReadingLengthSeconds / 60, 30) },
                            set: { settings.quranReadingLengthSeconds = min(1800, max(10, $0 * 60 + settings.quranReadingLengthSeconds % 60)) }
                        )) {
                            ForEach(0...30, id: \.self) { m in Text("\(m)m").tag(m) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }
                    HStack(spacing: 4) {
                        Picker("", selection: Binding(
                            get: { settings.quranReadingLengthSeconds % 60 / 10 * 10 },
                            set: { settings.quranReadingLengthSeconds = min(1800, max(10, (settings.quranReadingLengthSeconds / 60) * 60 + $0)) }
                        )) {
                            ForEach(Array(stride(from: 0, through: 50, by: 10)), id: \.self) { s in Text("\(s)s").tag(s) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }
                }
            }

            Divider()

            // Snooze duration
            VStack(alignment: .leading, spacing: 6) {
                Text("Snooze duration")
                    .font(.system(size: 13, weight: .medium))

                Picker("", selection: $settings.quranSnoozeDurationMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                }
                .labelsHidden()
                .frame(width: 100)
            }

            Divider()

            // Current position
            VStack(alignment: .leading, spacing: 6) {
                Text("Current position")
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Surah")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $settings.quranCurrentSurah) {
                            ForEach(1...114, id: \.self) { num in
                                Text("\(num). \(QuranDataManager.surahName(num))")
                                    .font(Font(FontFamilyPreset.quran.font(size: 13)))
                                    .tag(num)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ayah")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $settings.quranCurrentAyah) {
                            ForEach(1...maxAyah, id: \.self) { num in
                                Text("\(num)").tag(num)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }
                }
                .onChange(of: settings.quranCurrentSurah) { _, _ in
                    settings.quranCurrentAyah = 1
                }
            }

            Divider()

            // Test button
            Button {
                QuranReminderService.shared.triggerNow()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Test reminder now")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private var maxAyah: Int {
        let count = QuranDataManager.shared.ayahCount(forSurah: settings.quranCurrentSurah)
        return max(1, count > 0 ? count : 286)
    }
}
