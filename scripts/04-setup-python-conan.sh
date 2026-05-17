#!/usr/bin/env bash
# =============================================================================
# 04-setup-python-conan.sh — Install Conan (C++ Package Manager)
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  04 — Installing Conan"
echo "================================================"

# Skip if already installed
if command -v conan &>/dev/null; then
    echo "Conan already installed: $(conan --version)"
    exit 0
fi

echo "Installing Conan via pip3..."
pip3 install conan

echo ""
echo "✅ Conan installed: $(conan --version)"
echo ""
