#!/bin/bash

# Claude Usage Bar - Uninstaller

echo "╔════════════════════════════════════════════╗"
echo "║     Claude Usage Bar - Uninstaller         ║"
echo "╚════════════════════════════════════════════╝"
echo ""

CONFIG_DIR="$HOME/.config/claude-usage"
PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"

read -p "Remove Claude Usage Bar? This will delete your saved token. [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "→ Removing plugin..."
    rm -f "$PLUGIN_DIR"/claude-usage.*.sh

    echo "→ Removing configuration..."
    rm -rf "$CONFIG_DIR"

    echo ""
    echo "✓ Claude Usage Bar has been uninstalled."
    echo ""
    echo "Note: SwiftBar was not removed. To remove it:"
    echo "  brew uninstall --cask swiftbar"
else
    echo "Uninstall cancelled."
fi
