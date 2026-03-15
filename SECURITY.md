# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in Murmur, please report it responsibly.

**Do not open a public issue.**

Instead, use GitHub Security Advisories to report privately. Include:

1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact

You will receive a response within 48 hours. We will work with you to understand the issue and coordinate a fix before any public disclosure.

## Scope

Murmur runs locally on macOS and interacts with:

- **Microphone** (audio capture for dictation)
- **Clipboard** (temporary text storage for pasting)
- **Accessibility API** (simulated keystrokes for text insertion)
- **Claude Code CLI** (optional, shells out to local `claude` binary)

Security concerns include but are not limited to:

- Unauthorized microphone access or recording
- Clipboard data leakage
- Keystroke injection beyond intended text insertion
- Unsafe handling of user speech data
- Command injection through transcript content passed to Claude CLI
