#!/usr/bin/env bash
# package.sh — builds ash and creates release tarballs for Linux and macOS
set -e

echo "Building ash compiler..."
zig build -Doptimize=ReleaseFast

build_release() {
    local TARGET="$1"       # e.g. x86_64-linux
    local OS_NAME="$2"      # e.g. linux
    local EXE_NAME="$3"     # e.g. ash or ash.exe
    local ARCHIVE="ash-${TARGET}"

    echo "Packaging $ARCHIVE..."

    rm -rf "$ARCHIVE"
    mkdir -p "$ARCHIVE/ash/bin"
    mkdir -p "$ARCHIVE/ash/runtime"
    mkdir -p "$ARCHIVE/ash/examples"

    cp "zig-out/bin/${EXE_NAME}"    "$ARCHIVE/ash/bin/${EXE_NAME}"
    chmod +x                         "$ARCHIVE/ash/bin/${EXE_NAME}"
    cp runtime/ash_runtime.c         "$ARCHIVE/ash/runtime/"
    cp runtime/ash_runtime.h         "$ARCHIVE/ash/runtime/"
    cp install.sh                    "$ARCHIVE/ash/install.sh"
    chmod +x                         "$ARCHIVE/ash/install.sh"
    cp examples/hello.ash            "$ARCHIVE/ash/examples/"
    cp examples/fib.ash              "$ARCHIVE/ash/examples/"
    cp examples/fizzbuzz.ash         "$ARCHIVE/ash/examples/"
    cp README.md                     "$ARCHIVE/ash/"

    tar -czf "${ARCHIVE}.tar.gz" -C "$ARCHIVE" ash
    rm -rf "$ARCHIVE"
    echo "  Created: ${ARCHIVE}.tar.gz"
}

# Build for current platform
UNAME="$(uname -s)"
case "$UNAME" in
    Linux*)  build_release "x86_64-linux"  "linux"  "ash" ;;
    Darwin*) build_release "x86_64-macos"  "macos"  "ash" ;;
    *)       build_release "unknown"        "unknown" "ash" ;;
esac

echo ""
echo "To install from the tarball:"
echo "  tar xzf ash-*.tar.gz"
echo "  cd ash"
echo "  ./install.sh"
