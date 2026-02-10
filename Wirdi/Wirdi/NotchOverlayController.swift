//
//  NotchOverlayController.swift
//  Wirdi
//
//

import AppKit
import SwiftUI

// MARK: - Shared Word/Char Progress Helpers

/// Convert fractional word index to char offset using actual word lengths.
func charOffsetForWordProgress(_ progress: Double, words: [String], totalCharCount: Int) -> Int {
    let wholeWord = Int(progress)
    let frac = progress - Double(wholeWord)
    var offset = 0
    for i in 0..<min(wholeWord, words.count) {
        offset += words[i].count + 1
    }
    if wholeWord < words.count {
        offset += Int(Double(words[wholeWord].count) * frac)
    }
    return min(offset, totalCharCount)
}

/// Convert char offset back to fractional word index.
func wordProgressForCharOffset(_ charOffset: Int, words: [String]) -> Double {
    var offset = 0
    for (i, word) in words.enumerated() {
        let end = offset + word.count
        if charOffset <= end {
            let frac = Double(charOffset - offset) / Double(max(1, word.count))
            return Double(i) + frac
        }
        offset = end + 1
    }
    return Double(words.count)
}

@Observable
class NotchFrameTracker {
    var visibleHeight: CGFloat = 37 {
        didSet { updatePanel() }
    }
    var visibleWidth: CGFloat = 200 {
        didSet { updatePanel() }
    }
    weak var panel: NSPanel?
    var screenMidX: CGFloat = 0
    var screenMaxY: CGFloat = 0
    var menuBarHeight: CGFloat = 0

    func updatePanel() {
        guard let panel else { return }
        let x = screenMidX - visibleWidth / 2
        let y = screenMaxY - visibleHeight
        panel.setFrame(NSRect(x: x, y: y, width: visibleWidth, height: visibleHeight), display: false)
    }
}

// MARK: - Dynamic Island Shape (concave top corners, convex bottom corners)

struct DynamicIslandShape: Shape {
    var topInset: CGFloat = 16
    var bottomRadius: CGFloat = 18

    // Enable smooth animation by providing animatable data
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topInset, bottomRadius) }
        set {
            topInset = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let t = topInset
        let br = bottomRadius
        var p = Path()

        // Start at top-left corner
        p.move(to: CGPoint(x: 0, y: 0))

        // Top-left curve: from (0,0) curve down-right to (t, t)
        // Control at (t, 0) makes it bow DOWNWARD (like DynamicNotchKit)
        p.addQuadCurve(
            to: CGPoint(x: t, y: t),
            control: CGPoint(x: t, y: 0)
        )

        // Left edge down
        p.addLine(to: CGPoint(x: t, y: h - br))

        // Bottom-left convex corner
        p.addQuadCurve(
            to: CGPoint(x: t + br, y: h),
            control: CGPoint(x: t, y: h)
        )

        // Bottom edge
        p.addLine(to: CGPoint(x: w - t - br, y: h))

        // Bottom-right convex corner
        p.addQuadCurve(
            to: CGPoint(x: w - t, y: h - br),
            control: CGPoint(x: w - t, y: h)
        )

        // Right edge up
        p.addLine(to: CGPoint(x: w - t, y: t))

        // Top-right curve: from (w-t, t) curve up-right to (w, 0)
        // Control at (w-t, 0) makes it bow DOWNWARD
        p.addQuadCurve(
            to: CGPoint(x: w, y: 0),
            control: CGPoint(x: w - t, y: 0)
        )

        // Top edge back to start
        p.closeSubpath()
        return p
    }
}

// MARK: - Glass Effect View

struct GlassEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

// MARK: - NSScreen extension

extension NSScreen {
    var displayID: UInt32 {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return screenNumber.uint32Value
    }

    var displayName: String {
        return localizedName
    }
}
