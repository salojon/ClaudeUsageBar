# ClaudeUsageBar

A macOS menu bar app and CLI tool to monitor your Claude API usage (5-hour session and 7-day limits).

![Menu Bar](https://img.shields.io/badge/macOS-Menu%20Bar-blue)

## Features

- **Auto-sync** - Automatically reads token from Claude Code's keychain (no manual setup)
- **Menu bar indicator** - Color-coded usage status (🟢 🟡 🔴)
- **CLI tool** - Check usage from terminal with `claude-usage`
- **Secure** - Certificate pinning, token validation, no plaintext storage

## Installation

### SwiftBar Plugin (Recommended)

```bash
cd Installer
./install.sh
```

Prerequisites:
- [Homebrew](https://brew.sh)
- Claude Code logged in (`claude login`)

### CLI Tool

```bash
# Copy to your PATH
cp claude-usage /usr/local/bin/
chmod +x /usr/local/bin/claude-usage

# Run
claude-usage
```

## Usage

The app automatically syncs your token from Claude Code. Just ensure you're logged in:

```bash
claude login
```

Then the menu bar icon will show your usage:
- 🟢 Green: < 70% usage
- 🟡 Yellow: 70-90% usage
- 🔴 Red: > 90% usage

## Security

- Tokens read directly from macOS Keychain (no intermediate scripts for Swift app)
- Certificate pinning for API connections
- Token format validation
- No tokens in process arguments
- Secure file permissions (700/600)

## License

MIT
