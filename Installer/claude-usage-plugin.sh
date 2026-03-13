#!/bin/bash

# Claude Usage Menu Bar Plugin for SwiftBar/xbar
# Refresh rate is configurable via Settings menu

# Configuration
CONFIG_DIR="$HOME/.config/claude-usage"
TOKEN_FILE="$CONFIG_DIR/token"
SETTINGS_FILE="$CONFIG_DIR/settings"
PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
SCRIPT_NAME="claude-usage"

# Colors
GREEN="#34C759"
YELLOW="#FF9500"
RED="#FF3B30"
GRAY="#8E8E93"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# Initialize settings if needed
if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "refresh_rate=5m" > "$SETTINGS_FILE"
fi

# Read settings safely (no source to prevent code injection)
REFRESH_RATE="5m"
if [[ -f "$SETTINGS_FILE" ]]; then
    REFRESH_RATE=$(grep -E '^refresh_rate=[0-9]+[mh]$' "$SETTINGS_FILE" 2>/dev/null | cut -d= -f2)
    REFRESH_RATE="${REFRESH_RATE:-5m}"
fi

# Validate token format (sk-ant-oat or sk-ant-ort followed by version and random string)
validate_token() {
    local token="$1"
    [[ "$token" =~ ^sk-ant-o[ar]t[0-9]{2}-[A-Za-z0-9_-]+$ ]]
}

# Function to get token - tries Claude Code keychain first, then manual file
get_token() {
    # Try Claude Code keychain first (automatic sync)
    local creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [[ -n "$creds" ]]; then
        # Extract accessToken using grep and cut
        local token=$(echo "$creds" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$token" ]] && validate_token "$token"; then
            echo "$token"
            return
        fi
    fi

    # Fall back to manual token file (validate format)
    if [[ -f "$TOKEN_FILE" ]]; then
        local token=$(cat "$TOKEN_FILE")
        if validate_token "$token"; then
            echo "$token"
            return
        fi
    fi

    echo ""
}

# Function to change refresh rate
change_refresh_rate() {
    local new_rate="$1"
    echo "refresh_rate=$new_rate" > "$SETTINGS_FILE"

    # Rename the plugin file to apply new rate
    local current_script="$0"
    local base_dir=$(dirname "$current_script")
    local old_name=$(basename "$current_script")
    local new_name="${SCRIPT_NAME}.${new_rate}.sh"

    if [[ "$old_name" != "$new_name" ]]; then
        mv "$current_script" "$base_dir/$new_name"
    fi
}

# Function to pick color based on usage
pick_color() {
    local usage=$1
    if (( $(echo "$usage >= 90" | bc -l) )); then
        echo "$RED"
    elif (( $(echo "$usage >= 70" | bc -l) )); then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

# Function to format time until reset
format_time() {
    local reset_time="$1"
    local now=$(date +%s)

    # Strip fractional seconds and convert +00:00 to Z for parsing
    # Input: 2026-03-13T05:00:00.124142+00:00 -> 2026-03-13T05:00:00Z
    local cleaned=$(echo "$reset_time" | sed -E 's/\.[0-9]+//; s/\+00:00$/Z/')
    local reset=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cleaned" +%s 2>/dev/null)

    if [[ -z "$reset" || "$reset" == "" ]]; then
        echo "unknown"
        return
    fi

    local diff=$((reset - now))

    if [[ $diff -le 0 ]]; then
        echo "now"
        return
    fi

    local days=$((diff / 86400))
    local hours=$(((diff % 86400) / 3600))
    local mins=$(((diff % 3600) / 60))

    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

# Get the script directory for self-modification
SCRIPT_PATH="$0"
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Get token
TOKEN=$(get_token)

# If no token, show sign-in prompt
if [[ -z "$TOKEN" ]]; then
    echo "☁️ Sign In"
    echo "---"
    echo "No token found | color=$GRAY"
    echo "---"
    echo "Run this in Terminal: | size=12"
    echo "claude login | size=12 font=Menlo bash='echo \"Run: claude login\" && open -a Terminal' terminal=false"
    echo "---"
    echo "Then click Refresh below | size=11 color=$GRAY"
    echo "(Token syncs automatically from Claude Code) | size=10 color=$GRAY"
    echo "---"
    echo "Refresh | refresh=true"
    echo "---"
    echo "Or enter token manually... | bash='$CONFIG_DIR/set-token.sh' terminal=false refresh=true color=$GRAY size=11"
    exit 0
fi

# Fetch usage data (use -K with process substitution to avoid token in process args)
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -K <(echo "header = \"Authorization: Bearer $TOKEN\"") \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

# Handle errors
if [[ "$HTTP_CODE" != "200" ]]; then
    if [[ "$HTTP_CODE" == "401" ]]; then
        echo "⚠️ Expired"
        echo "---"
        echo "Token expired or invalid | color=$RED"
        echo "---"
        echo "Run 'claude login' to refresh | size=11 color=$GRAY"
        echo "---"
        echo "Refresh | refresh=true"
        echo "Enter token manually... | bash='$CONFIG_DIR/set-token.sh' terminal=false refresh=true color=$GRAY size=11"
        echo "Sign Out | bash='rm -f $TOKEN_FILE' terminal=false refresh=true"
    else
        echo "⚠️ Error"
        echo "---"
        echo "Failed to fetch usage (HTTP $HTTP_CODE) | color=$RED"
        echo "---"
        echo "Refresh | refresh=true"
    fi
    exit 0
fi

# Parse JSON response using grep/sed (no jq dependency)
FIVE_HOUR_UTIL=$(echo "$BODY" | grep -o '"five_hour"[^}]*' | grep -o '"utilization":[0-9.]*' | cut -d':' -f2)
FIVE_HOUR_RESET=$(echo "$BODY" | grep -o '"five_hour"[^}]*' | grep -o '"resets_at":"[^"]*"' | cut -d'"' -f4)
SEVEN_DAY_UTIL=$(echo "$BODY" | grep -o '"seven_day"[^}]*' | grep -o '"utilization":[0-9.]*' | cut -d':' -f2)
SEVEN_DAY_RESET=$(echo "$BODY" | grep -o '"seven_day"[^}]*' | grep -o '"resets_at":"[^"]*"' | cut -d'"' -f4)

# Round to integers
FIVE_HOUR_PCT=$(printf "%.0f" "$FIVE_HOUR_UTIL")
SEVEN_DAY_PCT=$(printf "%.0f" "$SEVEN_DAY_UTIL")

# Pick color based on max usage
MAX_USAGE=$(echo "$FIVE_HOUR_UTIL $SEVEN_DAY_UTIL" | tr ' ' '\n' | sort -rn | head -1)
ICON_COLOR=$(pick_color "$MAX_USAGE")

# Format reset times
FIVE_HOUR_TIME=$(format_time "$FIVE_HOUR_RESET")
SEVEN_DAY_TIME=$(format_time "$SEVEN_DAY_RESET")

# Menu bar display - colored ball based on session (5hr) usage only
if (( $(echo "$FIVE_HOUR_UTIL >= 90" | bc -l) )); then
    echo "🔴"
elif (( $(echo "$FIVE_HOUR_UTIL >= 70" | bc -l) )); then
    echo "🟡"
else
    echo "🟢"
fi

echo "---"

# Session usage
FIVE_COLOR=$(pick_color "$FIVE_HOUR_UTIL")
echo "Session (5hr): ${FIVE_HOUR_PCT}% | color=$FIVE_COLOR"
echo "Resets in $FIVE_HOUR_TIME | size=11 color=$GRAY"

echo "---"

# Weekly usage
SEVEN_COLOR=$(pick_color "$SEVEN_DAY_UTIL")
echo "Weekly (7day): ${SEVEN_DAY_PCT}% | color=$SEVEN_COLOR"
echo "Resets in $SEVEN_DAY_TIME | size=11 color=$GRAY"

echo "---"

# Settings submenu
echo "Settings"
echo "--Refresh Rate | size=12"

# Refresh rate options with checkmark for current
RATES=("1m:1 minute" "5m:5 minutes" "10m:10 minutes" "30m:30 minutes" "1h:1 hour")
for rate_pair in "${RATES[@]}"; do
    rate_val="${rate_pair%%:*}"
    rate_label="${rate_pair#*:}"
    if [[ "$REFRESH_RATE" == "$rate_val" ]]; then
        echo "--✓ $rate_label | bash='$CONFIG_DIR/change-rate.sh' param1='$rate_val' terminal=false refresh=true"
    else
        echo "--$rate_label | bash='$CONFIG_DIR/change-rate.sh' param1='$rate_val' terminal=false refresh=true"
    fi
done

echo "---"
echo "Refresh Now | refresh=true"
echo "---"
echo "Sign Out | bash='rm -f $TOKEN_FILE' terminal=false refresh=true"
