# Murmur

A lightweight, open source voice dictation app for macOS. Hold the Fn key, speak, release, and your words appear as clean text wherever your cursor is.

Murmur uses Apple Speech for transcription and optionally polishes text with [Claude Code](https://claude.ai/claude-code) in the background.

## Why Murmur

**Free, private, and tiny.** Murmur is a ~400KB native Swift binary that lives in your menu bar. No Electron, no browser engine, no background services eating your RAM. It does one thing well.

**Your voice stays on your Mac.** Speech recognition runs entirely on-device through Apple's Speech Framework. No audio is sent to any server. If you enable the optional Claude polish, only the transcribed text (not audio) is processed.

**Zero setup if you use Claude Code.** Already logged into the Claude CLI? Murmur picks it up automatically. No API keys to configure, no new accounts to create, no subscriptions to manage. Your existing Claude plan powers the intelligent text rewriting.

**Hackable by design.** Every component is a single, focused Swift file. Swap out the speech engine, change the cleanup rules, add your own hotkey. The entire codebase is under 800 lines.

## How It Works

1. **Hold Fn** to start recording
2. **Speak** naturally
3. **Release Fn** to stop
4. Text is cleaned up and pasted at your cursor

## Features

- **Fn key activation** via IOKit HID (hardware level, bypasses macOS emoji picker)
- **On-device transcription** through Apple Speech Framework. No audio leaves your Mac.
- **Local text cleanup** removes filler words (um, uh), stutters, and fixes spacing in under 2ms
- **Optional Claude polish** rewrites text with Claude Haiku for grammar and style. Works with any Claude plan through the [Claude Code CLI](https://claude.ai/claude-code).
- **Smart insertion** re-activates the app you were in before recording and pastes at your cursor
- **Minimal footprint** with a clean menu bar UI (waveform icon, Claude toggle, quit)

## Requirements

- macOS 14 (Sonoma) or later
- Microphone permission
- Speech Recognition permission
- Accessibility permission (for text insertion via simulated keystrokes)
- [Claude Code CLI](https://claude.ai/claude-code) (optional, for the polish feature)

## Build

```bash
git clone https://github.com/mohammadumifras/murmur.git
cd murmur
swift build
```

## Run

```bash
.build/debug/Murmur
```

On first launch, macOS will prompt for:
1. **Microphone access** (allow)
2. **Speech recognition** (allow)
3. **Accessibility** (System Settings > Privacy & Security > Accessibility > add Murmur)

### Fn Key Setup

macOS intercepts the Fn/Globe key by default for the emoji picker. To use it with Murmur:

**System Settings > Keyboard > set "Press 🌐 key to" > "Do Nothing"**

Murmur uses IOKit HID to detect the Fn key at the hardware level, but this system setting must be changed for reliable detection.

## Architecture

```
Hold Fn ──> IOKit HID detects hardware key
              │
              ▼
         SpeechRecognizerService    Apple Speech (mic capture + STT)
              │                     Streams partial transcripts live
              │
Release Fn    │
              ▼
         500ms audio buffer         Keeps mic open to catch last word
              │
              ▼
         LocalTextProcessor         Regex cleanup (<2ms):
              │                       - Remove fillers (um, uh, hmm)
              │                       - Remove stutters (I I > I)
              │                       - Fix spacing
              ▼
         TextInserter               Re-activates target app
              │                     Clipboard + Cmd+V paste
              │
              ▼
         TEXT APPEARS               ~100ms from Fn release
              │
              ▼  (background, optional)
         ClaudeRewriter             claude --print --model haiku
              │                     Undo raw paste + re-paste polished
              ▼
         POLISHED TEXT              ~3-5s later (if Claude enabled)
```

## Project Structure

```
Sources/Murmur/
├── MurmurApp.swift              App entry, menu bar, IOKit HID Fn key
├── DictationEngine.swift        Orchestrates the full pipeline
├── SpeechRecognizerService.swift Apple Speech Framework wrapper
├── LocalTextProcessor.swift     Regex-based filler/stutter cleanup
├── ClaudeRewriter.swift         Claude Code CLI integration
├── TextInserter.swift           Clipboard + paste into target app
├── MenuBarView.swift            Menu bar dropdown UI
└── Info.plist                   Permissions and app config
```

## Configuration

Click the waveform icon in the menu bar to toggle **Claude polish** on/off. When off, only local regex cleanup is applied (instant, no network).

## Contributing

Contributions are welcome! Some ideas:

- [ ] Whisper.cpp integration for better local STT
- [ ] Streaming STT (Deepgram/AssemblyAI) for real-time transcription
- [ ] Custom hotkey configuration
- [ ] Per-app dictation profiles
- [ ] Voice commands (e.g., "new line", "select all")
- [ ] Overlay UI showing live transcription

Please open an issue before starting work on large changes.

## License

MIT. See [LICENSE](LICENSE).
