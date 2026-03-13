#!/bin/bash
# Reads Claude Code's OAuth token from keychain
# Outputs just the accessToken for the app to capture
# NOTE: The Swift app now reads directly from keychain; this script is for shell tools only

CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
if [ -z "$CREDS" ]; then
    echo "NO_CREDENTIALS" >&2
    exit 1
fi

# Extract accessToken from JSON using grep and cut (no jq dependency)
TOKEN=$(echo "$CREDS" | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
if [ -z "$TOKEN" ]; then
    echo "NO_TOKEN" >&2
    exit 1
fi

# Validate token format (sk-ant-oat or sk-ant-ort followed by version and random string)
if [[ ! "$TOKEN" =~ ^sk-ant-o[ar]t[0-9]{2}-[A-Za-z0-9_-]+$ ]]; then
    echo "INVALID_TOKEN_FORMAT" >&2
    exit 1
fi

echo "$TOKEN"
