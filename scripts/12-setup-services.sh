#!/usr/bin/env bash
# =============================================================================
# 12-setup-services.sh — Management Scripts, Cron, Logs
# =============================================================================
# Deploy-time. The LAST step. Copies management scripts from the cloned
# cruncher repo to /usr/local/bin/ and sets up auto-pull cron.
#
# WARNING: The management scripts in cruncher/scripts/sys/ likely have bugs.
# They're copied as-is here but need a separate audit.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  12 — Setting up services and management scripts"
echo "================================================"

CRUNCHER_SCRIPTS="/root/cruncher/scripts/sys"

if [ ! -d "$CRUNCHER_SCRIPTS" ]; then
    echo "Error: $CRUNCHER_SCRIPTS not found. Did 08-clone-repos.sh run?" >&2
    exit 1
fi

# --- Create logs directory ---
echo "Creating logs directory..."
mkdir -p /root/logs
chmod 755 /root/logs
mkdir -p /var/log/postgresql
chown -R postgres:postgres /var/log/postgresql

# --- Copy management scripts ---
echo "Copying management scripts to /usr/local/bin/..."

SCRIPTS=(
    "start-postgres.sh:start-postgres.sh"
    "pg-manage.sh:pg-manage"
    "start-redis.sh:start-redis.sh"
    "redis-manage.sh:redis-manage"
    "db-services.sh:db-services"
    "auto-pull-repos.sh:auto-pull-repos.sh"
    "graph-server-manage.sh:graph-server-manage"
)

for entry in "${SCRIPTS[@]}"; do
    src="${entry%%:*}"
    dst="${entry##*:}"
    src_path="$CRUNCHER_SCRIPTS/$src"
    dst_path="/usr/local/bin/$dst"

    if [ -f "$src_path" ]; then
        cp "$src_path" "$dst_path"
        chmod +x "$dst_path"
        echo "  ✓ $src → $dst"
    else
        echo "  ⚠ $src not found, skipping"
    fi
done

# --- Set up auto-pull cron job ---
echo "Setting up auto-pull cron job (every 5 min)..."
touch /root/logs/auto-pull-repos.log
chmod 644 /root/logs/auto-pull-repos.log

printf "# Auto-pull repositories every 5 minutes\n*/5 * * * * root /usr/local/bin/auto-pull-repos.sh >/dev/null 2>&1\n" > /etc/cron.d/auto-pull-repos
chmod 0644 /etc/cron.d/auto-pull-repos

echo "Cron job configured:"
cat /etc/cron.d/auto-pull-repos
echo "NOTE: Cron daemon must be started manually: service cron start"

# --- Final touches ---
touch /root/.no_auto_tmux

echo ""
echo "✅ Services setup complete"
echo "   Management scripts installed to /usr/local/bin/"
echo "   Auto-pull cron: every 5 minutes"
echo "   Logs: /root/logs/"
echo ""
