#!/usr/bin/env bash
# =============================================================================
# 08-clone-repos.sh — Clone Private Repositories
# =============================================================================
# Deploy-time. Requires GITHUB_TOKEN env var (set by token-watcher.sh).
# Clones firmamentum/cruncher and firmamentum/yireh, then builds geth.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  08 — Cloning private repositories"
echo "================================================"

# --- Require GITHUB_TOKEN ---
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "Error: GITHUB_TOKEN is not set." >&2
    exit 1
fi

# --- Source environment files ---
for env_file in /etc/profile.d/cuda-env.sh /etc/profile.d/go-env.sh; do
    # shellcheck source=/dev/null
    [ -f "$env_file" ] && source "$env_file"
done

# --- Configure git to use token for github.com ---
# Credentials are kept persistent for auto-pull-repos.sh cron job.
# File is chmod 600 (root-only) and container is ephemeral.
echo "Configuring git credentials..."
git config --global credential.helper store
echo "https://oauth2:${GITHUB_TOKEN}@github.com" > /root/.git-credentials
chmod 600 /root/.git-credentials

# --- Clone cruncher ---
if [ -d "/root/cruncher" ]; then
    echo "cruncher already exists at /root/cruncher, pulling latest..."
    cd /root/cruncher
    git checkout main
    git pull origin main
else
    echo "Cloning firmamentum/cruncher → /root/cruncher..."
    git clone "https://github.com/firmamentum/cruncher.git" /root/cruncher
    cd /root/cruncher
    git checkout main
fi
echo "cruncher: $(git log --oneline -1)"

# --- Clone yireh ---
if [ -d "/root/yireh" ]; then
    echo "yireh already exists at /root/yireh, pulling latest..."
    cd /root/yireh
    git checkout main
    git pull origin main
else
    echo "Cloning firmamentum/yireh → /root/yireh..."
    git clone "https://github.com/firmamentum/yireh.git" /root/yireh
    cd /root/yireh
    git checkout main
fi
echo "yireh: $(git log --oneline -1)"

# --- Build geth (yireh is a geth fork) ---
echo "Building geth in /root/yireh..."
cd /root/yireh
make geth
echo "geth build complete."

echo ""
echo "✅ Repositories cloned and geth built"
echo "   /root/cruncher — DEX aggregation engine"
echo "   /root/yireh    — geth fork"
echo ""
