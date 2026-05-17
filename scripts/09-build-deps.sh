#!/usr/bin/env bash
# =============================================================================
# 09-build-deps.sh — Install Conan + Go Dependencies
# =============================================================================
# Deploy-time. Runs after repos are cloned (08).
# Installs C++ deps via Conan and Go modules via go mod tidy.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  09 — Building dependencies (Conan + Go)"
echo "================================================"

# --- Source environment files ---
for env_file in /etc/profile.d/cuda-env.sh /etc/profile.d/go-env.sh; do
    # shellcheck source=/dev/null
    [ -f "$env_file" ] && source "$env_file"
done

# Ensure PATH has Go and CUDA
export PATH="/usr/local/go/bin:/usr/local/cuda/bin:${PATH}"

# --- Verify prerequisites ---
if [ ! -d "/root/cruncher" ]; then
    echo "Error: /root/cruncher not found. Run 08-clone-repos.sh first." >&2
    exit 1
fi

cd /root/cruncher

# --- Conan dependencies ---
if [ -f "build/conandeps.mk" ]; then
    echo "Conan deps already built (build/conandeps.mk exists), skipping."
else
    echo "Detecting Conan profile..."
    conan profile detect --force

    echo "Installing Conan dependencies (this takes a while)..."
    conan install . --output-folder=build --build=missing \
        -s compiler.libcxx=libstdc++11 \
        -o "hwloc/*:shared=True"

    echo "Conan dependencies installed."
fi

# --- Go dependencies ---
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Warning: GITHUB_TOKEN not set. Go private modules may fail." >&2
fi

echo "Installing Go dependencies..."

# Configure git for private Go modules (if token is available)
if [ -n "${GITHUB_TOKEN:-}" ]; then
    git config --global url."https://oauth2:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
fi

export GOPRIVATE="github.com/firmamentum/*"
export GONOSUMCHECK="github.com/firmamentum/*"
export GOFLAGS="-mod=mod"

go mod tidy

echo "Go dependencies installed."

# Clean up git credential config
if [ -n "${GITHUB_TOKEN:-}" ]; then
    git config --global --remove-section url."https://oauth2:${GITHUB_TOKEN}@github.com/" 2>/dev/null || true
fi

echo ""
echo "✅ All dependencies installed"
echo "   Conan: build/conandeps.mk"
echo "   Go: go.sum updated"
echo ""
