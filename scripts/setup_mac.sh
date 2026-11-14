#!/usr/bin/env bash
# setup_mac.sh - Dual WorkBuddy account setup for macOS
#
# How it isolates the 2nd instance: WorkBuddy keeps its login/auth state and
# config under the user's HOME (~/.workbuddy and ~/Library/Application Support/...).
# By launching the 2nd instance with a DIFFERENT HOME, it gets its own login
# state + its own config dir, so it can log into a different account while the
# 1st instance keeps account A. We also clone your local chat history into that
# alt HOME so account B shows its on-this-device history (not a blank device).
#
# IMPORTANT (macOS-specific gotcha, verified on WorkBuddy 5.8.x/5.11.x builds):
#   WorkBuddy's Electron binary CANNOT be exec'd directly from a shell — it exits
#   with "Node.js environment variables are disabled because this process is
#   invoked by other apps." It MUST be launched via LaunchServices (`open -a`),
#   but `open` does NOT inherit the shell's HOME env var. So we wrap the launch in
#   a tiny .app whose executable sets HOME then `exec`s the real binary. `open -a`
#   launches that wrapper with a proper LaunchServices context, sidestepping the
#   error while still relocating HOME. This is more reliable than the "second
#   macOS user" fallback and needs no admin rights.
#
# Run as your normal user (no admin needed):
#   bash setup_mac.sh [ALT_HOME] [WORKBUDDY_APP]
#
# If the 2nd window still fails to start, see the "fallback" note at the bottom.

set -u
ALT_HOME="${1:-$HOME/WorkBuddyAltHome}"
WB_APP="${2:-/Applications/WorkBuddy.app}"
WRAPPER="$HOME/WorkBuddyAlt.app"

# locate the actual executable inside the .app bundle
if [ -d "$WB_APP" ]; then
  WB_BIN="$WB_APP/Contents/MacOS/Electron"
  if [ ! -x "$WB_BIN" ]; then
    WB_BIN=$(ls "$WB_APP"/Contents/MacOS/* 2>/dev/null | head -1)
  fi
else
  WB_BIN="$WB_APP"
fi

echo "=================================================="
echo " Dual WorkBuddy setup (macOS)"
echo "   Account A (primary) : $HOME"
echo "   Account B (alt HOME): $ALT_HOME"
echo "   WorkBuddy binary    : $WB_BIN"
echo "   Wrapper .app        : $WRAPPER"
echo "=================================================="

if [ ! -x "$WB_BIN" ]; then
  echo "ERROR: WorkBuddy binary not found. Pass the .app path: bash setup_mac.sh ~/WorkBuddyAltHome /Applications/WorkBuddy.app"
  exit 1
fi

# --- 1) create alt HOME + clone history (exclude heavy/regenerable dirs) ---
mkdir -p "$ALT_HOME"
SRC="$HOME/.workbuddy"
DST="$ALT_HOME/.workbuddy"
echo "[1/3] Cloning WorkBuddy local history into $DST ..."
EXCLUDES=(--exclude='workspace' --exclude='binaries' --exclude='app' --exclude='logs' \
  --exclude='plugins' --exclude='projects' --exclude='traces' \
  --exclude='connectors-marketplace-sources' --exclude='cache' --exclude='Crashpad' \
  --exclude='node_modules' --exclude='external-packages' --exclude='native-runtimes')
if [ -d "$SRC" ]; then
  rsync -a "${EXCLUDES[@]}" "$SRC/" "$DST/" 2>/dev/null
  echo "      done. (size: $(du -sh "$DST" 2>/dev/null | cut -f1))"
else
  echo "  WARN: $SRC not found - nothing to clone."
fi

# --- 2) wrapper .app: sets HOME then execs the real WorkBuddy binary ---
# Launched via `open -a`, so it gets a valid LaunchServices context and avoids
# the "invoked by other apps" error that direct binary exec triggers.
echo "[2/3] Creating wrapper .app: $WRAPPER ..."
rm -rf "$WRAPPER"
mkdir -p "$WRAPPER/Contents/MacOS"
cat > "$WRAPPER/Contents/MacOS/WorkBuddyAlt" <<EOF
#!/bin/bash
# Auto-generated dual-account wrapper (macOS).
# Runs WorkBuddy with an isolated HOME so a 2nd account can log in alongside A.
export HOME="$ALT_HOME"
exec "$WB_BIN"
EOF
chmod +x "$WRAPPER/Contents/MacOS/WorkBuddyAlt"
cat > "$WRAPPER/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>WorkBuddy Alt</string>
  <key>CFBundleDisplayName</key><string>WorkBuddy Alt</string>
  <key>CFBundleIdentifier</key><string>com.workbuddy.alt</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>WorkBuddyAlt</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>10.12</string>
</dict>
</plist>
EOF
# Drop quarantine flag so the locally-built app launches without Gatekeeper prompts
xattr -d com.apple.quarantine "$WRAPPER" 2>/dev/null || true
echo "      done."

# --- 3) desktop launcher (.command) using `open -a` (never direct binary exec) ---
LAUNCHER_DIR="$HOME/WorkBuddyDualLaunch"
mkdir -p "$LAUNCHER_DIR"
LAUNCHER="$LAUNCHER_DIR/launch_2workbuddy.command"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# 双 WorkBuddy 账号启动器 (macOS)
# 窗口 1 = 主账号 A（当前用户，已是你的主会话）
# 窗口 2 = 独立 HOME 下的实例，用于登录第二个账号 B
echo "打开主账号窗口 (A) ..."
open -a "$WB_APP"
sleep 3
echo "打开第二个账号窗口 (B, 独立 HOME) ..."
open -a "$WRAPPER"
EOF
chmod +x "$LAUNCHER"

DESK="$HOME/Desktop"
if [ -d "$DESK" ]; then
  cp "$LAUNCHER" "$DESK/WorkBuddy 2Accounts.command" 2>/dev/null && chmod +x "$DESK/WorkBuddy 2Accounts.command"
  echo "[3/3] Desktop launcher: $DESK/WorkBuddy 2Accounts.command"
else
  echo "[3/3] No Desktop dir found; launcher at: $LAUNCHER"
fi
echo "      Script launcher : $LAUNCHER"

echo ""
echo "================== DONE =================="
echo "Double-click 'WorkBuddy 2Accounts.command' on the Desktop:"
echo "  - Window 1: account A (primary user) - full history."
echo "  - Window 2: account B (alt HOME) - log in with your SECOND account."
echo ""
echo "NOTE (macOS): the 2nd instance runs via a wrapper .app with an isolated HOME."
echo "If the 2nd window still fails to start, use the FALLBACK:"
echo "  create a 2nd macOS user (System Settings > Users & Groups), log into it"
echo "  once (fast user switch), run WorkBuddy there and log in as account B."
echo "  Keep both users logged in and use Mission Control / Spaces to view both."
