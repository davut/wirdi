<p align="center">
  <img src="Wirdi/Wirdi/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="Wirdi icon">
</p>

<h1 align="center">Wirdi</h1>

<p align="center">
  <strong>A macOS Quran reading companion with word-by-word tracking in a Dynamic Island-style overlay.</strong>
</p>

<p align="center">
  <a href="#install">Install</a> · <a href="#features">Features</a> · <a href="#building-from-source">Build</a>
</p>

---

<p align="center">
  <img src="docs/wirdi-video.gif" width="600" alt="Wirdi demo">
</p>

## What is Wirdi?

Wirdi is a macOS app that helps you maintain a daily Quran reading habit. It displays ayahs word-by-word in a **Dynamic Island-style overlay** at the top of your screen, tracks your reading progress, and reminds you when it's time for your next session. All processing happens on-device — no accounts, no cloud, no data leaves your Mac.

## Install

### Homebrew

```bash
brew install davut/wirdi/wirdi
```

### Manual

**[Download the latest .dmg from Releases](https://github.com/davut/wirdi/releases/latest)**

> Requires **macOS 15 Sequoia** or later. Works on Apple Silicon and Intel.

Since Wirdi is not notarized, macOS may block it on first open. Run this once in Terminal:

```bash
xattr -cr /Applications/Wirdi.app
```

Then right-click the app → **Open**. After the first launch, macOS remembers your choice.

## Features

### Quran Reading

- **Word-by-word display** — Ayahs shown with authentic Uthmanic Hafs, Nastaleeq, or IndoPak script
- **Reading progress** — Remembers where you left off across sessions
- **Configurable reading length** — Choose how long each session is (10 seconds to 30 minutes)
- **Reading reminders** — Configurable intervals with snooze support
- **Estimated completion** — Shows how long it will take to finish the Quran at your pace

### Three Guidance Modes

- **Word Tracking** — Real-time word-by-word highlighting as you speak, using speech recognition with Arabic-aware fuzzy matching
- **Classic** — Auto-scrolling at a constant speed (no microphone needed)
- **Voice-Activated** — Scrolls when you speak, pauses when you're silent

### Display

- **Dynamic Island overlay** — A notch-shaped overlay at the top of your screen, always on top
- **Floating window mode** — A draggable window you can place anywhere, with optional glass effect
- **Multi-display support** — Follow your mouse across displays, or pin the overlay to a specific screen

### Customization

- **3 Quran fonts** — Uthmanic Hafs, Nastaleeq, IndoPak with adjustable size
- **6 highlight colors** — White, yellow, green, blue, pink, orange
- **Right-to-left layout** — Native RTL support for Arabic text

## Building from Source

### Requirements

- macOS 15+
- Xcode 16+

### Build

```
cd Wirdi
open Wirdi.xcodeproj
```

Build and run with `Cmd+R`.

## Acknowledgments

Wirdi was inspired by and built on top of [Textream](https://github.com/f/textream) by [Fatih Kadir Akin](https://github.com/f).

## License

MIT
