#!/usr/bin/env bash
# =============================================================================
# 07-setup-redis.sh — Redis Server Configuration
# =============================================================================
# Redis was installed via apt in 02-setup-system.sh. This script only
# configures it: bind localhost, no password, and runs a test cycle.
# Does NOT write .env — that's done in 11-setup-databases.sh (needs repo paths).
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  07 — Configuring Redis"
echo "================================================"

# --- Verify Redis is installed ---
if ! command -v redis-server &>/dev/null; then
    echo "Error: redis-server not found. Did 02-setup-system.sh run?" >&2
    exit 1
fi
echo "Redis version: $(redis-server --version)"

CONFIG_FILE="/etc/redis/redis.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Redis config file '$CONFIG_FILE' not found." >&2
    exit 1
fi

# --- Bind to localhost only ---
echo "Configuring Redis to bind 127.0.0.1..."
sed -i 's/^bind .*/bind 127.0.0.1/' "$CONFIG_FILE" || \
    echo "bind 127.0.0.1" >> "$CONFIG_FILE"

# --- Disable password (comment out requirepass) ---
echo "Disabling requirepass..."
sed -i 's/^requirepass/#requirepass/' "$CONFIG_FILE"

# --- Test cycle: start → ping → shutdown ---
echo "Testing Redis configuration..."
redis-server "$CONFIG_FILE" --daemonize yes
sleep 2

if redis-cli -h 127.0.0.1 -p 6379 ping | grep -q PONG; then
    echo "Redis PING → PONG ✓"
else
    echo "Error: Redis ping failed" >&2
    pkill redis-server 2>/dev/null || true
    exit 1
fi

redis-cli -h 127.0.0.1 -p 6379 shutdown 2>/dev/null || pkill redis-server 2>/dev/null || true
sleep 1

echo ""
echo "✅ Redis configured (bind 127.0.0.1, no password)"
echo "   Start with: redis-server /etc/redis/redis.conf"
echo ""
