#!/bin/bash
set -euo pipefail

SWIFT_VERSION="6.1.2"
SWIFT_RELEASE="swift-${SWIFT_VERSION}-RELEASE"
SWIFT_PLATFORM="ubuntu24.04"
SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/${SWIFT_RELEASE}/${SWIFT_RELEASE}-${SWIFT_PLATFORM}.tar.gz"
SWIFT_INSTALL_DIR="/usr/local/swift"

# Check if Swift is already installed and at the right version
if command -v swift &>/dev/null; then
    INSTALLED_VERSION=$(swift --version 2>/dev/null | grep -oP 'Swift version \K[0-9.]+' || true)
    if [ "$INSTALLED_VERSION" = "$SWIFT_VERSION" ]; then
        echo "Swift $SWIFT_VERSION is already installed."
        exit 0
    fi
    echo "Found Swift $INSTALLED_VERSION, need $SWIFT_VERSION"
fi

echo "Installing Swift $SWIFT_VERSION for $SWIFT_PLATFORM..."

# Download
echo "Downloading Swift toolchain..."
curl -sL -o /tmp/swift.tar.gz "$SWIFT_URL"

# Extract
echo "Extracting to $SWIFT_INSTALL_DIR..."
mkdir -p "$SWIFT_INSTALL_DIR"
tar -xzf /tmp/swift.tar.gz -C "$SWIFT_INSTALL_DIR" --strip-components=1

# Add to PATH if not already there
if ! echo "$PATH" | grep -q "$SWIFT_INSTALL_DIR/usr/bin"; then
    export PATH="$SWIFT_INSTALL_DIR/usr/bin:$PATH"
fi

# Verify
swift --version
echo "Swift $SWIFT_VERSION installed successfully."

# Clean up
rm -f /tmp/swift.tar.gz
