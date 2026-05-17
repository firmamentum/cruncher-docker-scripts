#!/usr/bin/env bash
# =============================================================================
# 06-setup-postgres.sh — PostgreSQL Server Installation
# =============================================================================
# Installs PostgreSQL server + dev headers + symlinks.
# Does NOT create application databases — that's done in 11-setup-databases.sh
# after the repos are cloned (schema files are in the repo).
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  06 — Installing PostgreSQL server"
echo "================================================"

export DEBIAN_FRONTEND=noninteractive

# --- Skip if already installed ---
if command -v psql &>/dev/null; then
    echo "PostgreSQL already installed: $(psql --version)"
    echo "Skipping installation."
    exit 0
fi

# --- Add PostgreSQL apt repository ---
echo "Adding PostgreSQL repository..."
timeout 10s echo | /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh || {
    echo "Warning: Auto-setup failed, attempting manual execution..."
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh || {
        echo "Error: Failed to add PostgreSQL repository" >&2
        exit 1
    }
}

# --- Install PostgreSQL ---
echo "Installing PostgreSQL server and client..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-client
rm -rf /var/lib/apt/lists/*

# --- Detect version and install dev headers ---
PG_VERSION=$(find /usr/lib/postgresql/ -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -V | tail -n 1)
echo "Detected PostgreSQL version: $PG_VERSION"

# Verify installation
ls -la "/usr/lib/postgresql/$PG_VERSION/bin/"
"/usr/lib/postgresql/$PG_VERSION/bin/psql" --version

# Dev headers
PG_VERSION_NUM=$("/usr/lib/postgresql/$PG_VERSION/bin/psql" -V | grep -oE '[0-9]+' | head -n 1)
DEV_PACKAGE="postgresql-server-dev-${PG_VERSION_NUM}"
echo "Installing ${DEV_PACKAGE}..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y "$DEV_PACKAGE"
rm -rf /var/lib/apt/lists/*

# --- Create symlinks for easier access ---
echo "Creating symlinks..."
ln -sf "/usr/lib/postgresql/$PG_VERSION/bin/psql" /usr/local/bin/psql
ln -sf "/usr/lib/postgresql/$PG_VERSION/bin/createdb" /usr/local/bin/createdb
ln -sf "/usr/lib/postgresql/$PG_VERSION/bin/dropdb" /usr/local/bin/dropdb
ln -sf "/usr/lib/postgresql/$PG_VERSION/bin/pg_dump" /usr/local/bin/pg_dump
ln -sf "/usr/lib/postgresql/$PG_VERSION/bin/pg_restore" /usr/local/bin/pg_restore

# --- Verify ---
echo ""
echo "✅ PostgreSQL installed and verified:"
psql --version
createdb --version
echo ""
