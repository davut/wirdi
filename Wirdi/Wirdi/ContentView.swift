//
//  ContentView.swift
//  Wirdi
//
//

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var showOnboarding = false
    @Bindable private var settings = NotchSettings.shared
    @Bindable private var reminderService = QuranReminderService.shared

    private func formatInterval(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m) min"
    }

    private func formatReadingLength(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 && s > 0 { return "\(m)m \(s)s" }
        if m > 0 { return "\(m) min" }
        return "\(s)s"
    }

    private var maxAyah: Int {
        let count = QuranDataManager.shared.ayahCount(forSurah: settings.quranCurrentSurah)
        return max(1, count > 0 ? count : 286)
    }


    var body: some View {
        VStack(spacing: 0) {
            // Drag area
            Spacer().frame(height: 16)

            // Surah name (ligature font)
            Text(QuranDataManager.surahLigature(settings.quranCurrentSurah))
                .font(Font(QuranDataManager.surahNameFont(size: 40)))
                .foregroundStyle(.primary)

            Text("Ayah \(settings.quranCurrentAyah)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Spacer().frame(height: 20)

            // Pickers row
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surah")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.quranCurrentSurah) {
                        ForEach(1...114, id: \.self) { num in
                            Text("\(num). \(QuranDataManager.surahName(num))")
                                .font(Font(FontFamilyPreset.quran.font(size: 14)))
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
                            Text("Ayah \(num)").tag(num)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.quranReadingLengthSeconds) {
                        ForEach(Array(stride(from: 10, through: 1800, by: 10)), id: \.self) { s in
                            Text(formatReadingLength(s)).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
            }
            .padding(.horizontal, 20)
            .onChange(of: settings.quranCurrentSurah) { _, _ in
                settings.quranCurrentAyah = 1
            }

            Spacer().frame(height: 20)

            // Start Reading button
            Button {
                startReading()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Start Reading")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            Spacer().frame(height: 12)

            // Reminder status — tappable to open settings
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Reminders every \(formatInterval(settings.quranReminderInterval))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Bottom bar
            HStack {
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(width: 340, height: 300)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: NotchSettings.shared)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .onAppear {
            showOnboarding = !settings.hasCompletedOnboarding
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAbout)) { _ in
            showAbout = true
        }
    }

    private func startReading() {
        // Hide the main window
        for window in NSApp.windows where !(window is NSPanel) {
            window.orderOut(nil)
        }

        // Start reading
        reminderService.readNow()
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            VStack(spacing: 4) {
                Text("Wirdi")
                    .font(.system(size: 20, weight: .bold))
                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text("A Quran reading companion that displays verses with word-by-word tracking.")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            // TODO: Add donate button back later
            // HStack(spacing: 12) {
            //     Link(destination: URL(string: "DONATE_URL")!) {
            //         HStack(spacing: 5) {
            //             Image(systemName: "heart.fill")
            //                 .font(.system(size: 11, weight: .semibold))
            //                 .foregroundStyle(.pink)
            //             Text("Donate")
            //                 .font(.system(size: 12, weight: .medium))
            //         }
            //         .foregroundStyle(.primary)
            //         .padding(.horizontal, 14)
            //         .padding(.vertical, 7)
            //         .background(Color.pink.opacity(0.1))
            //         .clipShape(Capsule())
            //     }
            // }

            Divider().padding(.horizontal, 20)

            VStack(spacing: 4) {
                Text("Made by Davut Jepbarov")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Inspired by Fatih Kadir Akin / Semih Kışlar")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Button("OK") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ContentView()
}
