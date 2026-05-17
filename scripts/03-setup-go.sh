#!/usr/bin/env bash
# =============================================================================
# 03-setup-go.sh — Install Go 1.24.0
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  03 — Installing Go 1.24.0"
echo "================================================"

GO_VERSION="1.24.0"
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")

# Skip if already installed
if command -v go &>/dev/null; then
    INSTALLED_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    if [ "$INSTALLED_VERSION" = "$GO_VERSION" ]; then
        echo "Go $GO_VERSION already installed, skipping."
        exit 0
    fi
fi

echo "Downloading Go ${GO_VERSION} for linux-${ARCH}..."
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -O /tmp/go.tar.gz

echo "Extracting to /usr/local..."
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tar.gz
rm /tmp/go.tar.gz

# Set PATH for subsequent scripts and interactive shells
ENV_FILE="/etc/profile.d/go-env.sh"
cat > "$ENV_FILE" << 'EOF'
export PATH="/usr/local/go/bin:${PATH}"
EOF
# shellcheck source=/dev/null
source "$ENV_FILE"

echo ""
echo "✅ Go installed: $(/usr/local/go/bin/go version)"
echo ""
