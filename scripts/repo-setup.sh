#!/usr/bin/env bash
# =============================================================================
# repo-setup.sh — Orchestrator for Post-Deploy Setup (Steps 08–12)
# =============================================================================
# Called by token-watcher.sh after the GitHub token arrives.
# Runs each deploy-time script sequentially with idempotent marker tracking.
# =============================================================================
set -euo pipefail

DEPLOY_DIR="$(dirname "$(realpath "$0")")"
LOG_DIR="/root/logs"
LOG_FILE="$LOG_DIR/repo-setup.log"
MARKER_DIR="/root"

mkdir -p "$LOG_DIR"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$LOG_FILE"
}

run_step() {
    local step_num="$1"
    local script_name="$2"
    local marker_file="$MARKER_DIR/.setup_done_${step_num}"
    local script_path="$DEPLOY_DIR/$script_name"

    if [ -f "$marker_file" ]; then
        log "Step $step_num ($script_name) — already done, skipping."
        return 0
    fi

    if [ ! -x "$script_path" ]; then
        log "Error: $script_path not found or not executable" >&2
        return 1
    fi

    log "Step $step_num ($script_name) — starting..."
    local start_time
    start_time=$(date +%s)

    # Source environment files so deploy-time scripts have access to CUDA/Go/etc
    for env_file in /etc/profile.d/cuda-env.sh /etc/profile.d/go-env.sh; do
        if [ -f "$env_file" ]; then
            # shellcheck source=/dev/null
            source "$env_file"
        fi
    done

    if "$script_path" 2>&1 | tee -a "$LOG_FILE"; then
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        log "Step $step_num ($script_name) — done in ${elapsed}s ✓"
        touch "$marker_file"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        log "Step $step_num ($script_name) — FAILED after ${elapsed}s ✗"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

log "========================================"
log "  repo-setup.sh — Post-Deploy Setup"
log "========================================"
log ""

TOTAL_START=$(date +%s)

# Verify GITHUB_TOKEN is set
if [ -z "${GITHUB_TOKEN:-}" ]; then
    log "Error: GITHUB_TOKEN is not set." >&2
    exit 1
fi

# Run all deploy-time steps
run_step "08" "08-clone-repos.sh"
run_step "09" "09-build-deps.sh"
run_step "10" "10-build-cruncher.sh"
run_step "11" "11-setup-databases.sh"
run_step "12" "12-setup-services.sh"

TOTAL_END=$(date +%s)
TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))

log ""
log "========================================"
log "  All steps complete! Total: ${TOTAL_ELAPSED}s"
log "========================================"
