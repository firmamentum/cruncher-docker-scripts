#!/usr/bin/env bash
# =============================================================================
# 02-setup-system.sh — System Packages, Tools, Timezone, Git Config
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  02 — Installing system packages and tools"
echo "================================================"

export DEBIAN_FRONTEND=noninteractive
export TZ=Africa/Nairobi

# --- System packages ---
echo "Installing system packages..."
apt-get update && apt-get install -y --no-install-recommends \
    git curl wget jq ccache build-essential \
    ocl-icd-libopencl1 redis-server openssl traceroute \
    opencl-headers postgresql-common nano nginx \
    aria2 zstd libzstd-dev libzstd1 unzip \
    lshw clinfo pkg-config python3 cron tzdata \
    python3-pip cmake make net-tools iputils-ping \
    libtbb-dev libhwloc-dev gcc-11 g++-11 \
    numactl hwloc-nox cpufrequtils \
    && rm -rf /var/lib/apt/lists/*

# --- Timezone ---
echo "Setting timezone to Africa/Nairobi..."
ln -fs /usr/share/zoneinfo/Africa/Nairobi /etc/localtime
echo "Africa/Nairobi" > /etc/timezone
echo "Timezone: $(date)"

# --- Git config ---
echo "Configuring Git..."
git config --global user.name "0xhomelander"
git config --global user.email "ampoule.cart.0r@icloud.com"
echo "Git config: $(git config --global --list | grep -E '(user.name|user.email)')"

# --- Speedtest CLI ---
echo "Installing Ookla Speedtest CLI..."
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
apt-get update && apt-get install -y speedtest && rm -rf /var/lib/apt/lists/*

echo ""
echo "✅ System packages, timezone, git config, and speedtest installed"
echo ""
