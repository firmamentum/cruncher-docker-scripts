#!/usr/bin/env bash
# =============================================================================
# 10-build-cruncher.sh — Build Graph Server + BFS Library
# =============================================================================
# Deploy-time. Runs after dependencies are installed (09).
# Builds the main cruncher binaries: graph-server HTTP API and graphbfs CGO lib.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  10 — Building cruncher"
echo "================================================"

# --- Source environment files ---
for env_file in /etc/profile.d/cuda-env.sh /etc/profile.d/go-env.sh; do
    # shellcheck source=/dev/null
    [ -f "$env_file" ] && source "$env_file"
done

# Ensure PATH has Go and CUDA
export PATH="/usr/local/go/bin:/usr/local/cuda/bin:${PATH}"
export LIBRARY_PATH="/usr/local/cuda/lib64/stubs:${LIBRARY_PATH:-}"

# --- Verify prerequisites ---
if [ ! -d "/root/cruncher" ]; then
    echo "Error: /root/cruncher not found. Run 08-clone-repos.sh first." >&2
    exit 1
fi

cd /root/cruncher

# --- Build graph-server ---
if [ -f "bin/graph-server" ]; then
    echo "graph-server already built, skipping."
else
    echo "Building Graph Server (HTTP API for pathfinding)..."
    make graph-server
    echo "Graph Server built: $(ls -la bin/graph-server)"
fi

# --- Build graphbfs-lib ---
if ls bin/libgraphbfs.* 1>/dev/null 2>&1; then
    echo "graphbfs-lib already built, skipping."
else
    echo "Building Graph BFS CGO library..."
    make graphbfs-lib
    echo "Graph BFS lib built: $(ls -la bin/libgraphbfs.*)"
fi

echo ""
echo "✅ Cruncher built"
echo "   bin/graph-server  — HTTP API for pathfinding"
echo "   bin/libgraphbfs.* — CGO shared library"
echo ""
