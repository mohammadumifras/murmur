# Contributing to Murmur

Thanks for your interest in contributing!

## Getting Started

1. Fork the repo
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/murmur.git`
3. Create a branch: `git checkout -b my-feature`
4. Make your changes
5. Build and test: `swift build && .build/debug/Murmur`
6. Commit and push
7. Open a pull request against `main`

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+
- Xcode Command Line Tools

## Guidelines

- Keep changes focused. One feature or fix per PR.
- Test your changes by running the app and dictating in various apps (Notes, browser, terminal, Slack).
- Follow existing code style. No linters are configured yet, just match what's there.
- Open an issue before working on large changes so we can discuss the approach.

## Areas for Contribution

- Better STT (Whisper.cpp, Deepgram, AssemblyAI integration)
- Custom hotkey configuration
- Overlay UI for live transcription preview
- Per-app dictation profiles
- Voice commands
- Improved local text cleanup rules
- Tests

## Code of Conduct

Be respectful. This is a small project and everyone is here to make it better.
