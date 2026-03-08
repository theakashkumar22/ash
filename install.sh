#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Ash Language Installer for Linux / macOS
#
# Release layout:
#   ash/
#     install.sh           <- this file
#     bin/ash
#     runtime/ash_runtime.c
#     runtime/ash_runtime.h
#     examples/hello.ash
#
# Installs to:
#   ~/.local/share/ash/bin/ash
#   ~/.local/share/ash/runtime/
#
# Adds ~/.local/share/ash/bin to PATH via ~/.bashrc / ~/.zshrc
# ─────────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_BIN="$SCRIPT_DIR/bin/ash"
SRC_RUNTIME_C="$SCRIPT_DIR/runtime/ash_runtime.c"
SRC_RUNTIME_H="$SCRIPT_DIR/runtime/ash_runtime.h"

ASH_HOME="$HOME/.local/share/ash"
DST_BIN="$ASH_HOME/bin"
DST_RUNTIME="$ASH_HOME/runtime"

echo ""
echo "  Ash Programming Language — Installer"
echo ""

# Verify source files
if [ ! -f "$SRC_BIN" ]; then
    echo "  ERROR: bin/ash not found next to install.sh"
    echo "  Make sure you extracted the full archive first."
    exit 1
fi
if [ ! -f "$SRC_RUNTIME_C" ]; then
    echo "  ERROR: runtime/ash_runtime.c not found"
    exit 1
fi

# Check zig
if ! command -v zig &>/dev/null; then
    echo "  ERROR: 'zig' is not installed or not in PATH."
    echo ""
    echo "  Ash requires Zig to compile your programs."
    echo "  Download from: https://ziglang.org/download/"
    echo "  Then re-run this installer."
    exit 1
fi
echo "  Found zig $(zig version)"
echo "  Installing to: $ASH_HOME"
echo ""

# Create dirs and copy
mkdir -p "$DST_BIN" "$DST_RUNTIME"
cp "$SRC_BIN"         "$DST_BIN/ash"
chmod +x              "$DST_BIN/ash"
cp "$SRC_RUNTIME_C"   "$DST_RUNTIME/ash_runtime.c"
cp "$SRC_RUNTIME_H"   "$DST_RUNTIME/ash_runtime.h"

# ── Add to PATH ────────────────────────────────────────────────────
PATH_LINE="export PATH=\"\$PATH:$DST_BIN\""
ADDED=0

add_to_file() {
    local rc_file="$1"
    if [ -f "$rc_file" ]; then
        if grep -qF "$DST_BIN" "$rc_file" 2>/dev/null; then
            echo "  PATH already set in $rc_file — skipping."
        else
            echo "" >> "$rc_file"
            echo "# Ash language" >> "$rc_file"
            echo "$PATH_LINE" >> "$rc_file"
            echo "  Added PATH to $rc_file"
            ADDED=1
        fi
    fi
}

add_to_file "$HOME/.bashrc"
add_to_file "$HOME/.zshrc"
add_to_file "$HOME/.profile"

if [ "$ADDED" -eq 0 ] && ! echo "$PATH" | grep -q "$DST_BIN"; then
    # Fallback: create ~/.profile if nothing was found
    echo "" >> "$HOME/.profile"
    echo "# Ash language" >> "$HOME/.profile"
    echo "$PATH_LINE" >> "$HOME/.profile"
    echo "  Added PATH to ~/.profile"
fi

echo ""
echo "  ✓  Ash installed successfully!"
echo ""
echo "     ash      →  $DST_BIN/ash"
echo "     runtime  →  $DST_RUNTIME/"
echo ""
echo "  Run this to use ash in your current shell:"
echo ""
echo "     source ~/.bashrc   (or restart your terminal)"
echo ""
echo "  Then try:"
echo "     ash version"
echo "     ash init"
echo "     ash run main.ash"
echo ""
