╔══════════════════════════════════════════════════════════════╗
║                    CLAUDE USAGE BAR                          ║
║              Menu Bar App for macOS Sonoma                   ║
╚══════════════════════════════════════════════════════════════╝

INSTALLATION
────────────
Run the installer:

    cd ~/ClaudeUsageBar/Installer
    ./install.sh

The installer will:
  • Install SwiftBar (via Homebrew) if needed
  • Set up the Claude Usage plugin
  • Configure everything automatically


FEATURES
────────
  • Shows Claude Pro usage in your menu bar
  • Session (5hr) and Weekly (7day) usage
  • Color-coded status (green/yellow/red)
  • Configurable refresh rate (1min to 1hr)
  • Time until usage resets


SETTING YOUR TOKEN
──────────────────
1. Run 'claude login' in Terminal (if not already done)
2. Open Keychain Access app
3. Search for "Claude Code"
4. Double-click the entry, click "Show Password"
5. Find "accessToken" in the JSON and copy its value
6. Click "Set Token..." in the menu bar app


CHANGING REFRESH RATE
─────────────────────
Click on the menu bar icon → Settings → Refresh Rate
Options: 1 minute, 5 minutes, 10 minutes, 30 minutes, 1 hour


UNINSTALLING
────────────
    cd ~/ClaudeUsageBar/Installer
    ./uninstall.sh


FILES
─────
Plugin:     ~/Library/Application Support/SwiftBar/Plugins/
Config:     ~/.config/claude-usage/
  • token       - Your OAuth token (encrypted by macOS)
  • settings    - Refresh rate preference
