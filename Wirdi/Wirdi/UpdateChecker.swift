//
//  UpdateChecker.swift
//  Wirdi
//
//

import AppKit

class UpdateChecker: NSObject, URLSessionDownloadDelegate {
    static let shared = UpdateChecker()

    private let repoOwner = "davut"
    private let repoName = "wirdi"

    private var progressPanel: NSPanel?
    private var progressBar: NSProgressIndicator?
    private var statusLabel: NSTextField?
    private var downloadTask: URLSessionDownloadTask?
    private var fallbackReleaseURL: String?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Public API

    func checkForUpdates(silent: Bool = false) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            DispatchQueue.main.async {
                if let error {
                    if !silent {
                        self.showError("Could not check for updates.\n\(error.localizedDescription)")
                    }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else {
                    if !silent {
                        self.showError("Could not parse the release information.")
                    }
                    return
                }

                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                // Extract DMG download URL from assets
                var dmgURL: String?
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.lowercased().hasSuffix(".dmg"),
                           let downloadURL = asset["browser_download_url"] as? String {
                            dmgURL = downloadURL
                            break
                        }
                    }
                }

                // Fallback: construct URL from tag
                if dmgURL == nil {
                    dmgURL = "https://github.com/\(self.repoOwner)/\(self.repoName)/releases/download/\(tagName)/Wirdi.dmg"
                }

                if self.isVersion(latestVersion, newerThan: self.currentVersion) {
                    self.showUpdateAvailable(latestVersion: latestVersion, dmgURL: dmgURL!, releaseURL: htmlURL)
                } else if !silent {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    // MARK: - Version comparison

    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    // MARK: - Update alert

    private func showUpdateAvailable(latestVersion: String, dmgURL: String, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Wirdi \(latestVersion) is available. You are currently running \(currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            fallbackReleaseURL = releaseURL
            startDownload(from: dmgURL)
        }
    }

    // MARK: - Progress panel

    private func showProgressPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        panel.title = "Updating Wirdi"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.center()

        let contentView = NSView(frame: panel.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: "Downloading update…")
        label.font = NSFont.systemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 55, width: 300, height: 20)
        label.autoresizingMask = [.width]
        contentView.addSubview(label)

        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 25, width: 300, height: 20))
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        bar.isIndeterminate = false
        bar.autoresizingMask = [.width]
        contentView.addSubview(bar)

        panel.contentView = contentView

        self.progressPanel = panel
        self.progressBar = bar
        self.statusLabel = label

        panel.makeKeyAndOrderFront(nil)
    }

    private func dismissProgressPanel() {
        progressPanel?.close()
        progressPanel = nil
        progressBar = nil
        statusLabel = nil
    }

    // MARK: - Download

    private func startDownload(from urlString: String) {
        guard let url = URL(string: urlString) else {
            handleUpdateError("Invalid download URL.")
            return
        }

        showProgressPanel()

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressBar?.doubleValue = progress
            let mb = Double(totalBytesWritten) / 1_048_576
            let totalMB = Double(totalBytesExpectedToWrite) / 1_048_576
            statusLabel?.stringValue = String(format: "Downloading update… %.1f / %.1f MB", mb, totalMB)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Validate HTTP response
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            guard httpResponse.statusCode == 200 else {
                handleUpdateError("Download failed with HTTP \(httpResponse.statusCode). The DMG may not exist for this release.")
                return
            }
        }

        // Validate file size (a real DMG should be at least ~100KB)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int) ?? 0
        if fileSize < 100_000 {
            handleUpdateError("Downloaded file is too small (\(fileSize) bytes) — likely not a valid disk image.")
            return
        }

        // Move to a stable temp path before the system cleans up the original
        let dmgPath = NSTemporaryDirectory() + "Wirdi-update.dmg"
        let dmgURL = URL(fileURLWithPath: dmgPath)
        try? FileManager.default.removeItem(at: dmgURL)
        do {
            try FileManager.default.moveItem(at: location, to: dmgURL)
        } catch {
            handleUpdateError("Failed to save download: \(error.localizedDescription)")
            return
        }
        installUpdate(dmgPath: dmgPath)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            handleUpdateError("Download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Install

    private func installUpdate(dmgPath: String) {
        statusLabel?.stringValue = "Installing…"
        progressBar?.isIndeterminate = true
        progressBar?.startAnimation(nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let fm = FileManager.default

            // Diagnostics: file size
            let fileSize = (try? fm.attributesOfItem(atPath: dmgPath)[.size] as? Int) ?? 0

            // 1. Mount the DMG (use -plist to parse actual mount point)
            let mountResult = self.runShell("/usr/bin/hdiutil", arguments: [
                "attach", dmgPath,
                "-nobrowse", "-noverify", "-plist"
            ])

            guard mountResult.status == 0 else {
                DispatchQueue.main.async {
                    self.handleUpdateError("Failed to mount disk image (file size: \(fileSize) bytes, exit code: \(mountResult.status)).\n\(mountResult.output)")
                }
                return
            }

            // Parse mount point from plist output
            guard let plistData = mountResult.output.data(using: .utf8),
                  let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
                DispatchQueue.main.async {
                    self.handleUpdateError("Could not determine mount point.\n\(mountResult.output)")
                }
                return
            }

            // 2. Find Wirdi.app on the mounted volume
            let mountedAppPath: String
            let directPath = "\(mountPoint)/Wirdi.app"

            if fm.fileExists(atPath: directPath) {
                mountedAppPath = directPath
            } else {
                let contents = (try? fm.contentsOfDirectory(atPath: mountPoint)) ?? []
                if let appName = contents.first(where: { $0.hasSuffix(".app") }) {
                    mountedAppPath = "\(mountPoint)/\(appName)"
                } else {
                    self.runShell("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-quiet"])
                    DispatchQueue.main.async {
                        self.handleUpdateError("Could not find the app in the disk image. Contents: \(contents)")
                    }
                    return
                }
            }

            // 3. Write and run the updater script
            let currentAppPath = Bundle.main.bundlePath
            let pid = ProcessInfo.processInfo.processIdentifier
            let scriptPath = "/tmp/wirdi-update.sh"

            let script = """
            #!/bin/bash
            # Wait for the current app to exit
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            # Remove the old app
            rm -rf "\(currentAppPath)"
            # Copy the new app
            cp -R "\(mountedAppPath)" "\(currentAppPath)"
            # Detach the DMG
            hdiutil detach "\(mountPoint)" -quiet
            # Remove quarantine attributes
            xattr -cr "\(currentAppPath)"
            # Remove the downloaded DMG
            rm -f "\(dmgPath)"
            # Relaunch
            open "\(currentAppPath)"
            # Clean up this script
            rm -f "\(scriptPath)"
            """

            do {
                try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            } catch {
                self.runShell("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-quiet"])
                DispatchQueue.main.async {
                    self.handleUpdateError("Failed to prepare installer: \(error.localizedDescription)")
                }
                return
            }

            // Make script executable
            self.runShell("/bin/chmod", arguments: ["+x", scriptPath])

            // Launch the script
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            do {
                try process.run()
            } catch {
                self.runShell("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-quiet"])
                DispatchQueue.main.async {
                    self.handleUpdateError("Failed to launch installer: \(error.localizedDescription)")
                }
                return
            }

            // Quit the app
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Error handling

    private func handleUpdateError(_ message: String) {
        dismissProgressPanel()

        let alert = NSAlert()
        alert.messageText = "Update Failed"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let urlString = fallbackReleaseURL, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Alerts

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Wirdi \(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Shell helper

    @discardableResult
    private func runShell(_ command: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
