#!/bin/bash
# Install or remove the MultiClip LaunchAgent (starts it at login).
#
#   scripts/launchagent.sh install
#   scripts/launchagent.sh uninstall
#   scripts/launchagent.sh status
set -euo pipefail

LABEL="${MULTICLIP_BUNDLE_ID:-dev.howlingmime.MultiClip}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="${MULTICLIP_APP:-$HOME/Applications/MultiClip.app}"
BIN="$APP/Contents/MacOS/MultiClip"
DOMAIN="gui/$(id -u)"

case "${1:-status}" in
install)
    [ -x "$BIN" ] || { echo "No app at $BIN — run scripts/package.sh first" >&2; exit 1; }

    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <!-- Restart if it crashes, but respect an intentional Quit from the
         menubar (a clean exit stays quit until the next login). -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/MultiClip.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/MultiClip.log</string>
</dict>
</plist>
PLISTEOF

    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    pkill -f "MultiClip.app/Contents/MacOS/MultiClip" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Installed and started: $PLIST"
    ;;

uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed: $PLIST"
    ;;

status)
    launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E '^\s+(state|pid|last exit)' || echo "Not loaded"
    ;;

*)
    echo "usage: $0 {install|uninstall|status}" >&2
    exit 1
    ;;
esac
