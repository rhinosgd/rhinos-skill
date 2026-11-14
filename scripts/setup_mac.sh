#!/usr/bin/env bash
# setup_mac.sh - Dual WorkBuddy account setup for macOS (best-effort)
#
# How it isolates the 2nd instance: WorkBuddy keeps its login/auth state and
# config under the user's HOME (~/.workbuddy and ~/Library/Application Support/...).
# By launching the 2nd instance with a DIFFERENT HOME, it gets its own login
# state + its own config dir, so it can log into a different account while the
# 1st instance keeps account A. We also clone your local chat history into that
# alt HOME so account B shows its on-this-device history (not a blank device).
#
# Run as your normal user (no admin needed for this method):
#   bash setup_mac.sh [ALT_HOME] [WORKBUDDY_APP]
#
# If the 2nd window is blocked by a single-instance lock, see the "fallback"
# note at the bottom / skill references.

set -u
ALT_HOME="${1:-$HOME/WorkBuddyAltHome}"
WB_APP="${2:-/Applications/WorkBuddy.app}"

# locate the actual executable inside the .app bundle
if [ -d "$WB_APP" ]; then
  WB_BIN="$WB_APP/Contents/MacOS/WorkBuddy"
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

# --- 2) launcher (.command) ---
LAUNCHER_DIR="$HOME/WorkBuddyDualLaunch"
mkdir -p "$LAUNCHER_DIR"
LAUNCHER="$LAUNCHER_DIR/launch_2workbuddy.command"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# Auto-generated dual-account launcher (macOS)
WB_APP="$WB_APP"
WB_BIN="$WB_BIN"
ALT_HOME="$ALT_HOME"
echo "Opening account A (primary user)..."
open -a "\$WB_APP"
sleep 4
echo "Opening account B (alt HOME)..."
HOME="\$ALT_HOME" "\$WB_BIN" >/dev/null 2>&1 &
sleep 2
EOF
chmod +x "$LAUNCHER"

# --- 3) desktop copy ---
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
echo "NOTE (macOS): this uses a separate HOME for the 2nd instance."
echo "If the 2nd window is blocked by a single-instance lock, use the FALLBACK:"
echo "  create a 2nd macOS user (System Settings > Users & Groups), log into it"
echo "  once (fast user switch), run WorkBuddy there and log in as account B."
echo "  Keep both users logged in and use Mission Control / Spaces to view both."
