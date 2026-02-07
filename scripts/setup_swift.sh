#!/bin/bash
set -euo pipefail

# SessionStart hook for Claude Code on the web.
# Installs Swift toolchain in the remote cloud environment.
#
# IMPORTANT: Your Claude Code on the web environment must allow
# network access to download.swift.org (Swift toolchain downloads).
# Configure this in your environment settings by either:
#   - Using "Full" internet access, OR
#   - Adding download.swift.org to your allowed domains

# Only run in remote (cloud) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  echo "Not a remote environment, skipping Swift setup."
  exit 0
fi

# Check if swift is already installed and meets minimum version (6.1+)
if command -v swift &>/dev/null; then
  INSTALLED_VERSION=$(swift --version 2>/dev/null | grep -oP 'Swift version \K[0-9]+\.[0-9]+' || echo "0.0")
  MAJOR=$(echo "$INSTALLED_VERSION" | cut -d. -f1)
  MINOR=$(echo "$INSTALLED_VERSION" | cut -d. -f2)
  if [ "$MAJOR" -gt 6 ] || { [ "$MAJOR" -eq 6 ] && [ "$MINOR" -ge 1 ]; }; then
    echo "Swift $INSTALLED_VERSION already installed, skipping setup."
    exit 0
  fi
  echo "Swift $INSTALLED_VERSION found but need >= 6.1, installing..."
fi

echo "Installing Swift toolchain for Ubuntu..."

# Install prerequisites (ignore apt-get update errors in sandboxed environments)
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq \
  binutils \
  git \
  gnupg2 \
  libc6-dev \
  libcurl4-openssl-dev \
  libedit2 \
  libgcc-13-dev \
  libncurses-dev \
  libpython3-dev \
  libsqlite3-0 \
  libstdc++-13-dev \
  libxml2-dev \
  libz3-dev \
  pkg-config \
  tzdata \
  unzip \
  zlib1g-dev \
  curl \
  2>/dev/null || true

# Swift version to install
SWIFT_VERSION="6.1.2"

# Determine architecture and set download URL
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"
elif [ "$ARCH" = "aarch64" ]; then
  SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404-aarch64/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04-aarch64.tar.gz"
else
  echo "Error: Unsupported architecture: $ARCH"
  exit 1
fi

SWIFT_TARBALL="/tmp/swift.tar.gz"
SWIFT_INSTALL_DIR="/usr/local/swift"

echo "Downloading Swift ${SWIFT_VERSION} for ${ARCH}..."
if ! curl -fsSL "$SWIFT_URL" -o "$SWIFT_TARBALL"; then
  echo ""
  echo "Error: Failed to download Swift toolchain."
  echo "This is likely because download.swift.org is not in your allowed domains."
  echo ""
  echo "To fix this, update your Claude Code on the web environment to allow"
  echo "network access to download.swift.org, or use 'Full' internet access."
  exit 1
fi

echo "Extracting Swift..."
mkdir -p "$SWIFT_INSTALL_DIR"
tar -xzf "$SWIFT_TARBALL" -C "$SWIFT_INSTALL_DIR" --strip-components=1

# Clean up tarball
rm -f "$SWIFT_TARBALL"

# Add Swift to PATH for subsequent commands
SWIFT_BIN="$SWIFT_INSTALL_DIR/usr/bin"
export PATH="$SWIFT_BIN:$PATH"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "PATH=$SWIFT_BIN:\$PATH" >> "$CLAUDE_ENV_FILE"
else
  # Fallback: add to common profile files
  echo "export PATH=\"$SWIFT_BIN:\$PATH\"" >> /etc/profile.d/swift.sh 2>/dev/null || true
  echo "export PATH=\"$SWIFT_BIN:\$PATH\"" >> "$HOME/.bashrc"
fi

echo "Swift installation complete:"
"$SWIFT_BIN/swift" --version

exit 0
