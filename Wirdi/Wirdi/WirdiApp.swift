//
//  WirdiApp.swift
//  Wirdi
//
//

import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openAbout = Notification.Name("openAbout")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app icon is set for Stage Manager / Mission Control
        if let icon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = icon
        }

        // Silent update check on launch
        UpdateChecker.shared.checkForUpdates(silent: true)

        // Load Quran data in background and start reminders
        DispatchQueue.global(qos: .userInitiated).async {
            QuranDataManager.shared.loadIfNeeded()
            DispatchQueue.main.async {
                QuranReminderService.shared.startIfEnabled()
            }
        }

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
                return false
            }
        }
        return true
    }
}

@main
struct WirdiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Wirdi") {
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                }
                Divider()
                Button("Check for Updates…") {
                    UpdateChecker.shared.checkForUpdates()
                }
            }
            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
