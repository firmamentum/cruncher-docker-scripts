#!/usr/bin/env bash
# =============================================================================
# token-watcher.sh — Watches for GitHub Token, Triggers Repo Setup
# =============================================================================
# Runs as a daemon after the container starts on Vast.ai. Waits for a GitHub
# token to arrive via either:
#   1. File: /root/.github_token (SCP'd by vast-ctrl)
#   2. HTTP POST to port 9191 (alternative)
#
# Once the token arrives, exports GITHUB_TOKEN and runs repo-setup.sh.
# =============================================================================
set -euo pipefail

TOKEN_FILE="/root/.github_token"
STATUS_FILE="/root/.setup_status"
LOG_DIR="/root/logs"
LOG_FILE="$LOG_DIR/token-watcher.log"
DEPLOY_DIR="$(dirname "$(realpath "$0")")"
HTTP_PORT=9191

mkdir -p "$LOG_DIR"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

set_status() {
    echo "$1" > "$STATUS_FILE"
    log "Status: $1"
}

# --- If already completed, skip ---
if [ -f "$STATUS_FILE" ] && grep -q "done" "$STATUS_FILE" 2>/dev/null; then
    log "Setup already completed. Exiting."
    exit 0
fi

set_status "waiting"

# --- Start HTTP listener in background ---
start_http_listener() {
    log "Starting HTTP listener on port $HTTP_PORT..."
    while true; do
        # Use bash TCP redirect to accept a single connection
        # ncat/nc might not be available, so we use a simple approach
        if command -v ncat &>/dev/null; then
            LISTENER_CMD="ncat"
        elif command -v nc &>/dev/null; then
            LISTENER_CMD="nc"
        else
            log "Warning: Neither ncat nor nc found. HTTP listener disabled."
            return
        fi

        # Listen for one connection, extract token from POST body
        REQUEST=$($LISTENER_CMD -l -p "$HTTP_PORT" -q 1 2>/dev/null || true)

        if [ -n "$REQUEST" ]; then
            # Extract the body (everything after the blank line in HTTP request)
            TOKEN=$(echo "$REQUEST" | sed -n '/^$/,$ p' | tr -d '[:space:]')
            if [ -n "$TOKEN" ]; then
                log "Token received via HTTP POST"
                echo "$TOKEN" > "$TOKEN_FILE"
            fi
        fi
    done
}

# Start HTTP listener in background (best-effort)
start_http_listener &
HTTP_PID=$!

log "Watching for token at $TOKEN_FILE (polling every 2s)..."
log "HTTP listener on port $HTTP_PORT (PID: $HTTP_PID)"

# --- Poll for token file ---
while true; do
    if [ -f "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')

        if [ -z "$TOKEN" ]; then
            log "Token file found but empty. Waiting..."
            sleep 2
            continue
        fi

        # Validate token format (should start with ghp_ or github_pat_)
        if [[ "$TOKEN" =~ ^(ghp_|github_pat_|gho_) ]]; then
            log "Valid GitHub token detected (${TOKEN:0:4}...)"
        else
            log "Warning: Token doesn't match known GitHub token formats. Proceeding anyway."
        fi

        # Export and trigger setup
        export GITHUB_TOKEN="$TOKEN"
        set_status "running"

        log "Launching repo-setup.sh..."
        if "$DEPLOY_DIR/repo-setup.sh" 2>&1 | tee -a "$LOG_FILE"; then
            set_status "done"
            log "🎉 Setup completed successfully!"
        else
            set_status "failed"
            log "❌ Setup failed. Check $LOG_DIR/repo-setup.log for details."
        fi

        # Clean up HTTP listener
        kill "$HTTP_PID" 2>/dev/null || true

        # Remove token file — SSH key handles all future git auth
        rm -f "$TOKEN_FILE"
        log "Token file removed (SSH key now handles git auth)."

        # Clean up any HTTPS credential artifacts
        rm -f /root/.git-credentials
        git config --global --unset credential.helper 2>/dev/null || true

        exit 0
    fi

    sleep 2
done
