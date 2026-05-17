#!/usr/bin/env bash
# =============================================================================
# 11-setup-databases.sh — PostgreSQL Database + Schema + Extensions + .env
# =============================================================================
# Deploy-time. Runs after cruncher is built (10).
# This is the biggest script — handles everything from Dockerfile.cuda L330-L650:
#   - Start PG, create DB/user, apply schema, install system_stats extension
#   - Write OVERLORD_DB_URL + REDIS_HOST + REDIS_PORT to .env
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  11 — Setting up databases and .env"
echo "================================================"

# --- Source environment ---
for env_file in /etc/profile.d/cuda-env.sh /etc/profile.d/go-env.sh; do
    # shellcheck source=/dev/null
    [ -f "$env_file" ] && source "$env_file"
done
export PATH="/usr/local/go/bin:/usr/local/cuda/bin:${PATH}"

# --- Configuration ---
PG_DB_NAME="cruncher_db"
PG_DB_USER="cruncher"
PG_PASSWORD=$(openssl rand -hex 16)
PG_DB_USER_PASSWORD=$(openssl rand -hex 16)
QUERY_FILE="/root/yireh/overlord/db/queries/queries.txt"
ENV_DIR="/root/yireh/overlord/env"
ENV_FILE="$ENV_DIR/.env"

REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"

echo "Database: $PG_DB_NAME, User: $PG_DB_USER"

# --- Detect PostgreSQL version ---
PG_VERSION=$(psql -V | grep -oE '[0-9]+' | head -n 1)
PG_DATA_DIR="/var/lib/postgresql/$PG_VERSION/main"
PG_BIN_DIR="/usr/lib/postgresql/$PG_VERSION/bin"

echo "PostgreSQL version: $PG_VERSION"
echo "Data directory: $PG_DATA_DIR"

# --- Ensure directories exist with correct ownership ---
mkdir -p "/var/lib/postgresql/$PG_VERSION"
chown -R postgres:postgres /var/lib/postgresql
mkdir -p /var/log/postgresql
chown -R postgres:postgres /var/log/postgresql

# --- Initialize cluster if needed ---
if [ ! -d "$PG_DATA_DIR" ]; then
    echo "Initializing PostgreSQL cluster..."
    su - postgres -c "$PG_BIN_DIR/initdb -D $PG_DATA_DIR --auth-local peer --auth-host scram-sha-256"
    echo "Cluster initialized."
else
    echo "PostgreSQL cluster already exists."
fi

PG_CONF="$PG_DATA_DIR/postgresql.conf"
PG_HBA_CONF="$PG_DATA_DIR/pg_hba.conf"

# --- Ensure config files exist ---
if [ ! -f "$PG_CONF" ]; then
    echo "Creating postgresql.conf from template..."
    if [ -f "/usr/share/postgresql/$PG_VERSION/postgresql.conf.sample" ]; then
        cp "/usr/share/postgresql/$PG_VERSION/postgresql.conf.sample" "$PG_CONF"
    elif [ -f "/etc/postgresql/$PG_VERSION/main/postgresql.conf" ]; then
        cp "/etc/postgresql/$PG_VERSION/main/postgresql.conf" "$PG_CONF"
    else
        echo "Creating minimal postgresql.conf..."
        cat > "$PG_CONF" << 'PGCONF'
listen_addresses = '*'
port = 5432
max_connections = 100
shared_buffers = 128MB
dynamic_shared_memory_type = posix
log_timezone = 'Etc/UTC'
datestyle = 'iso, mdy'
timezone = 'Etc/UTC'
lc_messages = 'en_US.utf8'
lc_monetary = 'en_US.utf8'
lc_numeric = 'en_US.utf8'
lc_time = 'en_US.utf8'
default_text_search_config = 'pg_catalog.english'
PGCONF
    fi
    chown postgres:postgres "$PG_CONF"
fi

if [ ! -f "$PG_HBA_CONF" ]; then
    echo "Creating pg_hba.conf..."
    cat > "$PG_HBA_CONF" << PGHBA
# PostgreSQL Client Authentication Configuration File
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     scram-sha-256
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
PGHBA
    chown postgres:postgres "$PG_HBA_CONF"
fi

# --- Configure for network access ---
echo "Configuring PostgreSQL for network access..."
sed -i.bak1 -E "s/^#?listen_addresses\s*=.*/listen_addresses = '*'/" "$PG_CONF"
sed -i.bak_port -E "s/^#?port\s*=.*/port = 5432/" "$PG_CONF"

# --- Set initial auth to peer for setup, then switch to scram-sha-256 ---
echo "Setting initial auth for setup (peer for local)..."
sed -i -E \
    -e "/^local\s+all\s+all\s+/ s/(\s+)\S+$/\1peer/" \
    -e "/^host\s+all\s+all\s+127\.0\.0\.1\/32\s+/ s/(\s+)\S+$/\1md5/" \
    -e "/^host\s+all\s+all\s+::1\/128\s+/ s/(\s+)\S+$/\1md5/" \
    "$PG_HBA_CONF"

# Add remote access rules
echo "Adding remote access rules..."
{
    echo "# --- Added by deploy script for remote access ---"
    echo "host    all             $PG_DB_USER             0.0.0.0/0               scram-sha-256"
    echo "host    all             $PG_DB_USER             ::/0                    scram-sha-256"
} >> "$PG_HBA_CONF"

# --- Start PostgreSQL ---
echo "Starting PostgreSQL..."
su - postgres -c "$PG_BIN_DIR/pg_ctl -D $PG_DATA_DIR -l /var/log/postgresql/postgresql-$PG_VERSION-main.log start"
sleep 5

# Verify it started
if ! su - postgres -c "$PG_BIN_DIR/pg_ctl -D $PG_DATA_DIR status" > /dev/null 2>&1; then
    echo "Error: PostgreSQL failed to start. Logs:" >&2
    cat "/var/log/postgresql/postgresql-$PG_VERSION-main.log" 2>/dev/null || true
    exit 1
fi

echo "PostgreSQL started successfully."
su - postgres -c "psql -c \"SHOW listen_addresses;\""

# --- Set postgres user password ---
echo "Setting postgres user password..."
su - postgres -c "psql -c \"ALTER USER postgres WITH ENCRYPTED PASSWORD '$PG_PASSWORD';\""

# --- Create application user ---
echo "Creating user '$PG_DB_USER'..."
if su - postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$PG_DB_USER'\"" | grep -q 1; then
    echo "User '$PG_DB_USER' already exists, updating password..."
    su - postgres -c "psql -c \"ALTER USER $PG_DB_USER WITH ENCRYPTED PASSWORD '$PG_DB_USER_PASSWORD';\""
else
    su - postgres -c "psql -c \"CREATE USER $PG_DB_USER WITH ENCRYPTED PASSWORD '$PG_DB_USER_PASSWORD';\""
fi

# --- Create database ---
echo "Creating database '$PG_DB_NAME'..."
if su - postgres -c "psql -lqt" | cut -d \| -f 1 | grep -qw "$PG_DB_NAME"; then
    echo "Database '$PG_DB_NAME' already exists, ensuring ownership..."
    su - postgres -c "psql -c \"ALTER DATABASE \\\"$PG_DB_NAME\\\" OWNER TO \\\"$PG_DB_USER\\\";\""
else
    su - postgres -c "createdb \"$PG_DB_NAME\" -O \"$PG_DB_USER\""
    echo "Database '$PG_DB_NAME' created."
fi

# --- Create .pgpass for postgres user ---
echo "Setting up .pgpass..."
PG_PASS_FILE="/var/lib/postgresql/.pgpass"
echo "localhost:5432:*:postgres:$PG_PASSWORD" > "$PG_PASS_FILE"
echo "localhost:5432:*:$PG_DB_USER:$PG_DB_USER_PASSWORD" >> "$PG_PASS_FILE"
chown postgres:postgres "$PG_PASS_FILE"
chmod 600 "$PG_PASS_FILE"

# --- Switch to scram-sha-256 auth ---
echo "Switching to scram-sha-256 authentication..."
sed -i -E \
    -e "/^local\s+all\s+all\s+/ s/(\s+)\S+$/\1scram-sha-256/" \
    -e "/^host\s+all\s+all\s+127\.0\.0\.1\/32\s+/ s/(\s+)\S+$/\1scram-sha-256/" \
    -e "/^host\s+all\s+all\s+::1\/128\s+/ s/(\s+)\S+$/\1scram-sha-256/" \
    "$PG_HBA_CONF"

su - postgres -c "$PG_BIN_DIR/pg_ctl -D $PG_DATA_DIR reload"
sleep 2

# Verify auth works
su - postgres -c "psql -c 'SELECT version();'"

# --- Apply schema ---
if [ -f "$QUERY_FILE" ]; then
    echo "Applying schema from '$QUERY_FILE'..."
    TMP_PASSFILE=$(mktemp)
    echo "localhost:5432:$PG_DB_NAME:$PG_DB_USER:$PG_DB_USER_PASSWORD" > "$TMP_PASSFILE"
    chmod 600 "$TMP_PASSFILE"

    CREATE_SQL=$(awk '/^-- name: create/ { create_mode=1; next } /^-- name:/ { create_mode=0 } create_mode && !/^[[:space:]]*$/ { print }' "$QUERY_FILE")

    if [ -n "$CREATE_SQL" ]; then
        echo "Executing CREATE statements..."
        echo "$CREATE_SQL" | PGPASSFILE="$TMP_PASSFILE" psql -v ON_ERROR_STOP=1 \
            --host localhost --dbname "$PG_DB_NAME" --username "$PG_DB_USER" --no-password
        echo "Schema applied successfully."
    else
        echo "Warning: No 'create' statements found in '$QUERY_FILE'."
    fi

    rm -f "$TMP_PASSFILE"
else
    echo "Warning: Query file '$QUERY_FILE' not found, skipping schema."
fi

# --- Install system_stats extension ---
echo ""
echo "--- Installing system_stats PostgreSQL extension ---"

BUILD_TEMP_DIR=$(mktemp -d)
SYSTEM_STATS_URL="https://github.com/EnterpriseDB/system_stats/archive/refs/tags/v3.2.tar.gz"

echo "Downloading system_stats source..."
wget --timeout=30 --tries=3 -O "$BUILD_TEMP_DIR/system_stats.tar.gz" "$SYSTEM_STATS_URL" || {
    echo "Error: Failed to download system_stats." >&2
    exit 1
}

echo "Extracting..."
tar -zxf "$BUILD_TEMP_DIR/system_stats.tar.gz" -C "$BUILD_TEMP_DIR" --strip-components=1

PG_CONFIG_BIN_DIR="/usr/lib/postgresql/$PG_VERSION/bin"
if [ ! -x "$PG_CONFIG_BIN_DIR/pg_config" ]; then
    echo "Error: pg_config not found at $PG_CONFIG_BIN_DIR/pg_config" >&2
    exit 1
fi

echo "Compiling system_stats..."
(cd "$BUILD_TEMP_DIR" && PATH="$PG_CONFIG_BIN_DIR:$PATH" make USE_PGXS=1) || {
    echo "Error: Failed to compile system_stats." >&2
    exit 1
}

echo "Installing system_stats..."
(cd "$BUILD_TEMP_DIR" && PATH="$PG_CONFIG_BIN_DIR:$PATH" make install USE_PGXS=1) || {
    echo "Error: Failed to install system_stats." >&2
    exit 1
}

echo "Creating extension in database..."
su - postgres -c "psql -v ON_ERROR_STOP=1 --dbname \"$PG_DB_NAME\" -c \"CREATE EXTENSION IF NOT EXISTS system_stats;\""

echo "Granting permissions..."
su - postgres -c "psql -v ON_ERROR_STOP=1 --dbname \"$PG_DB_NAME\" -c \"GRANT monitor_system_stats TO \\\"$PG_DB_USER\\\";\""
su - postgres -c "psql -v ON_ERROR_STOP=1 --dbname \"$PG_DB_NAME\" -c \"GRANT EXECUTE ON FUNCTION pg_catalog.pg_stat_file(text) TO \\\"$PG_DB_USER\\\";\""
su - postgres -c "psql -v ON_ERROR_STOP=1 --dbname \"$PG_DB_NAME\" -c \"GRANT EXECUTE ON FUNCTION pg_catalog.pg_current_logfile() TO \\\"$PG_DB_USER\\\";\""

echo "system_stats installed and permissions granted."
rm -rf "$BUILD_TEMP_DIR"

# --- Write .env file ---
echo "Writing .env file..."
mkdir -p "$ENV_DIR"

OVERLORD_DB_URL="postgresql://${PG_DB_USER}:${PG_DB_USER_PASSWORD}@localhost:5432/${PG_DB_NAME}"

cat > "$ENV_FILE" << ENVEOF
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
OVERLORD_DB_URL=$OVERLORD_DB_URL
ENVEOF

chmod 600 "$ENV_FILE"

echo ""
echo "✅ Database setup complete"
echo "   Database: $PG_DB_NAME"
echo "   User: $PG_DB_USER"
echo "   .env written to: $ENV_FILE"
echo "   Contents:"
cat "$ENV_FILE"
echo ""
