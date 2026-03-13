#!/bin/bash

# Claude Usage Bar - Installer for macOS Sonoma
# No Xcode required - uses SwiftBar

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Change to script directory to ensure relative paths work
cd "$SCRIPT_DIR"

echo "╔════════════════════════════════════════════╗"
echo "║     Claude Usage Bar - Installer           ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Configuration
CONFIG_DIR="$HOME/.config/claude-usage"
PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
SWIFTBAR_APP="/Applications/SwiftBar.app"

# Create directories with secure permissions from the start
echo "→ Creating configuration directories..."
install -d -m 700 "$CONFIG_DIR"
mkdir -p "$PLUGIN_DIR"

# Install sync-token helper script for automatic token sync
echo "→ Installing token sync helper..."
if [[ -f "$SCRIPT_DIR/sync-token.sh" ]]; then
    cp "$SCRIPT_DIR/sync-token.sh" "$CONFIG_DIR/sync-token.sh"
    chmod +x "$CONFIG_DIR/sync-token.sh"
else
    echo "⚠️  sync-token.sh not found, skipping automatic token sync setup"
fi

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo ""
    echo "⚠️  Homebrew not found."
    echo ""
    echo "Install Homebrew first by running:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo ""
    echo "Then run this installer again."
    echo ""
    echo "Press any key to close..."
    read -n 1 -s
    exit 1
fi

# Check for/install SwiftBar
if [[ ! -d "$SWIFTBAR_APP" ]]; then
    echo "→ Installing SwiftBar via Homebrew..."
    brew install --cask swiftbar
else
    echo "✓ SwiftBar already installed"
fi

# Install the plugin
echo "→ Installing Claude Usage plugin..."

# Default refresh rate
DEFAULT_RATE="5m"

# Copy main plugin script
cp "$SCRIPT_DIR/claude-usage-plugin.sh" "$PLUGIN_DIR/claude-usage.${DEFAULT_RATE}.sh"
chmod +x "$PLUGIN_DIR/claude-usage.${DEFAULT_RATE}.sh"

# Create helper script for setting token (with validation)
cat > "$CONFIG_DIR/set-token.sh" << 'SETTOKEN'
#!/bin/bash
CONFIG_DIR="$HOME/.config/claude-usage"
TOKEN_FILE="$CONFIG_DIR/token"

TOKEN=$(osascript -e 'text returned of (display dialog "Paste your OAuth token:" default answer "" with title "Claude Usage - Sign In" buttons {"Cancel", "Save"} default button "Save")' 2>/dev/null)

if [[ -n "$TOKEN" ]]; then
    # Validate token format (sk-ant-oat or sk-ant-ort)
    if [[ ! "$TOKEN" =~ ^sk-ant-o[ar]t[0-9]{2}-[A-Za-z0-9_-]+$ ]]; then
        osascript -e 'display alert "Invalid Token" message "Token should start with sk-ant-oat or sk-ant-ort" as warning'
        exit 1
    fi
    # Create file with secure permissions from the start
    (umask 077 && echo "$TOKEN" > "$TOKEN_FILE")
    osascript -e 'display notification "Token saved successfully!" with title "Claude Usage"'
fi
SETTOKEN
chmod +x "$CONFIG_DIR/set-token.sh"

# Create helper script for changing refresh rate (with validation)
cat > "$CONFIG_DIR/change-rate.sh" << 'CHANGERATE'
#!/bin/bash
NEW_RATE="$1"
CONFIG_DIR="$HOME/.config/claude-usage"
SETTINGS_FILE="$CONFIG_DIR/settings"
PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"

# Validate rate format (1m, 5m, 10m, 30m, 1h only)
if [[ ! "$NEW_RATE" =~ ^(1m|5m|10m|30m|1h)$ ]]; then
    osascript -e 'display alert "Invalid Rate" message "Rate must be 1m, 5m, 10m, 30m, or 1h" as warning'
    exit 1
fi

# Update settings with validated rate
echo "refresh_rate=$NEW_RATE" > "$SETTINGS_FILE"

# Find and rename the current plugin
CURRENT_PLUGIN=$(ls "$PLUGIN_DIR"/claude-usage.*.sh 2>/dev/null | head -1)
if [[ -n "$CURRENT_PLUGIN" ]]; then
    NEW_PLUGIN="$PLUGIN_DIR/claude-usage.${NEW_RATE}.sh"
    if [[ "$CURRENT_PLUGIN" != "$NEW_PLUGIN" ]]; then
        mv "$CURRENT_PLUGIN" "$NEW_PLUGIN"
    fi
fi

osascript -e "display notification \"Refresh rate changed to $NEW_RATE\" with title \"Claude Usage\""
CHANGERATE
chmod +x "$CONFIG_DIR/change-rate.sh"

# Create default settings
echo "refresh_rate=${DEFAULT_RATE}" > "$CONFIG_DIR/settings"

echo ""
echo "✓ Installation complete!"
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║              Next Steps                    ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "1. Open SwiftBar:"
echo "   open -a SwiftBar"
echo ""
echo "2. If prompted for plugin folder, select:"
echo "   ~/Library/Application Support/SwiftBar/Plugins"
echo ""
echo "3. Ensure Claude Code is logged in:"
echo "   claude login"
echo ""
echo "4. The plugin will auto-sync your token from Claude Code!"
echo "   (No manual token copy needed)"
echo ""
echo "═══════════════════════════════════════════════"
echo ""

# Ask to launch SwiftBar
read -p "Launch SwiftBar now? [Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    # Set the plugin directory preference
    defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGIN_DIR"

    open -a SwiftBar
    echo ""
    echo "✓ SwiftBar launched! Look for the Claude Usage icon in your menu bar."
fi

echo ""
echo "Press any key to close this window..."
read -n 1 -s
