#!/usr/bin/env bash
# =============================================================================
# 08-clone-repos.sh — SSH Key Setup + Clone Private Repositories
# =============================================================================
# Deploy-time. Requires GITHUB_TOKEN env var (set by token-watcher.sh).
#
# Flow:
#   1. Validate token has SSH key permissions (admin:public_key scope)
#   2. Generate ed25519 SSH key pair
#   3. Upload public key to GitHub via API
#   4. Configure SSH for github.com
#   5. Set git global config (user.name, user.email)
#   6. Clone repos via SSH
#   7. Token is no longer needed — SSH handles all future git auth
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  08 — SSH setup + cloning private repositories"
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

# --- Configuration ---
SSH_DIR="/root/.ssh"
KEY_NAME="id_ed25519_cruncher"
KEY_PATH="$SSH_DIR/$KEY_NAME"
PUB_KEY_PATH="${KEY_PATH}.pub"
SSH_CONFIG="$SSH_DIR/config"
GITHUB_API="https://api.github.com"
GIT_USER_NAME="0xhomelander_"
GIT_USER_EMAIL="abc1234@gmail.com"

# Generate a key title with container ID if available
CONTAINER_ID=$(cat /root/.vast_containerlabel 2>/dev/null | tr -d '[:space:]' || hostname)
KEY_TITLE="VAST-${CONTAINER_ID}-$(date +%s)"

# =============================================================================
# Step 1: Validate token has SSH key permissions
# =============================================================================
echo "Validating GitHub token permissions..."

# First check the token is valid at all
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "$GITHUB_API/user")

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "❌ FATAL: GitHub token is invalid (HTTP $HTTP_STATUS)." >&2
    echo "   Please provide a valid token." >&2
    exit 1
fi

# Check SSH key access (admin:public_key scope)
KEYS_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "$GITHUB_API/user/keys")

KEYS_HTTP_STATUS=$(echo "$KEYS_RESPONSE" | tail -1)
KEYS_BODY=$(echo "$KEYS_RESPONSE" | sed '$d')

if [ "$KEYS_HTTP_STATUS" -eq 401 ] || [ "$KEYS_HTTP_STATUS" -eq 403 ]; then
    echo "❌ FATAL: Token does not have SSH key permissions (HTTP $KEYS_HTTP_STATUS)." >&2
    echo "   The token needs 'admin:public_key' scope to upload SSH keys." >&2
    echo "   Generate a new token at: https://github.com/settings/tokens" >&2
    echo "   Required scopes: repo, admin:public_key" >&2
    exit 1
fi

if [ "$KEYS_HTTP_STATUS" -ne 200 ]; then
    echo "❌ FATAL: Unexpected response from GitHub API (HTTP $KEYS_HTTP_STATUS)." >&2
    echo "   Response: $KEYS_BODY" >&2
    exit 1
fi

echo "✓ Token validated — has SSH key permissions."

# =============================================================================
# Step 2: Generate SSH key pair (if not already present)
# =============================================================================
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$KEY_PATH" ] && [ -f "$PUB_KEY_PATH" ] && [ -s "$PUB_KEY_PATH" ]; then
    echo "SSH key pair already exists at $KEY_PATH. Skipping generation."
else
    # Clean up any partial state
    rm -f "$KEY_PATH" "$PUB_KEY_PATH"

    echo "Generating ed25519 SSH key..."
    ssh-keygen -t ed25519 -C "$GIT_USER_EMAIL" -f "$KEY_PATH" -N "" -q
    chmod 600 "$KEY_PATH"
    chmod 644 "$PUB_KEY_PATH"
    echo "✓ SSH key generated."
fi

PUB_KEY_CONTENT=$(cat "$PUB_KEY_PATH")
PUB_KEY_FINGERPRINT=$(echo "$PUB_KEY_CONTENT" | awk '{print $1 " " $2}')

# =============================================================================
# Step 3: Upload public key to GitHub (idempotent)
# =============================================================================
echo "Checking if SSH key is already registered on GitHub..."

# Check if this exact key already exists
EXISTING_KEY_ID=""
if echo "$KEYS_BODY" | jq -e 'type == "array"' >/dev/null 2>&1; then
    EXISTING_KEY_ID=$(echo "$KEYS_BODY" | jq -r \
        --arg fp "$PUB_KEY_FINGERPRINT" \
        '[.[] | select(.key | startswith($fp))][0].id // empty')
fi

if [ -n "$EXISTING_KEY_ID" ]; then
    echo "✓ SSH key already registered on GitHub (Key ID: $EXISTING_KEY_ID). Skipping upload."
else
    echo "Uploading SSH key to GitHub (title: $KEY_TITLE)..."

    UPLOAD_PAYLOAD=$(jq -n \
        --arg title "$KEY_TITLE" \
        --arg key "$PUB_KEY_CONTENT" \
        '{title: $title, key: $key}')

    UPLOAD_RESPONSE_FILE=$(mktemp)
    UPLOAD_STATUS=$(curl -s -w "%{http_code}" -o "$UPLOAD_RESPONSE_FILE" \
        -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -d "$UPLOAD_PAYLOAD" \
        "$GITHUB_API/user/keys")

    UPLOAD_BODY=$(cat "$UPLOAD_RESPONSE_FILE")
    rm -f "$UPLOAD_RESPONSE_FILE"

    if [ "$UPLOAD_STATUS" -eq 201 ]; then
        EXISTING_KEY_ID=$(echo "$UPLOAD_BODY" | jq -r '.id')
        echo "✓ SSH key uploaded to GitHub (Key ID: $EXISTING_KEY_ID)."
    elif [ "$UPLOAD_STATUS" -eq 422 ]; then
        # 422 = key already exists (race condition)
        echo "✓ SSH key already exists on GitHub (HTTP 422)."
    else
        echo "❌ FATAL: Failed to upload SSH key (HTTP $UPLOAD_STATUS)." >&2
        echo "   Response: $UPLOAD_BODY" >&2
        exit 1
    fi
fi

# =============================================================================
# Step 4: Configure SSH for github.com
# =============================================================================
echo "Configuring SSH..."

# Add github.com to known_hosts
ssh-keyscan -H github.com >> "$SSH_DIR/known_hosts" 2>/dev/null
chmod 600 "$SSH_DIR/known_hosts"

# Write SSH config (replace existing github.com block if present)
if [ -f "$SSH_CONFIG" ] && grep -q "^Host github.com" "$SSH_CONFIG" 2>/dev/null; then
    # Remove existing block
    sed -i.bak '/^Host github.com/,/^[[:space:]]*$/d' "$SSH_CONFIG"
    rm -f "${SSH_CONFIG}.bak"
fi

cat >> "$SSH_CONFIG" << EOF

# GitHub SSH config (auto-generated by 08-clone-repos.sh)
Host github.com
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
chmod 600 "$SSH_CONFIG"

# Start ssh-agent and add key
eval "$(ssh-agent -s)" >/dev/null 2>&1
ssh-add "$KEY_PATH" 2>/dev/null || true

echo "✓ SSH configured for github.com."

# =============================================================================
# Step 5: Verify SSH connection
# =============================================================================
echo "Testing SSH connection to GitHub..."
if ssh -T git@github.com 2>&1 | grep -qi "successfully authenticated\|Hi "; then
    echo "✓ SSH connection to GitHub verified."
else
    # ssh -T returns exit code 1 even on success (it's not a shell)
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
    if echo "$SSH_OUTPUT" | grep -qi "successfully authenticated\|Hi "; then
        echo "✓ SSH connection to GitHub verified."
    else
        echo "❌ FATAL: SSH connection to GitHub failed." >&2
        echo "   Output: $SSH_OUTPUT" >&2
        exit 1
    fi
fi

# =============================================================================
# Step 6: Set git global config
# =============================================================================
echo "Setting git global config..."
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
echo "✓ git config set (user.name=$GIT_USER_NAME, user.email=$GIT_USER_EMAIL)."

# Clean up any leftover HTTPS credential config
rm -f /root/.git-credentials
git config --global --unset credential.helper 2>/dev/null || true

# =============================================================================
# Step 7: Clone repositories via SSH
# =============================================================================

# --- Clone cruncher ---
if [ -d "/root/cruncher" ]; then
    echo "cruncher already exists at /root/cruncher, updating remote + pulling..."
    cd /root/cruncher
    git remote set-url origin "git@github.com:firmamentum/cruncher.git" 2>/dev/null || true
    git checkout main
    git pull origin main
else
    echo "Cloning firmamentum/cruncher → /root/cruncher..."
    git clone "git@github.com:firmamentum/cruncher.git" /root/cruncher
    cd /root/cruncher
    git checkout main
fi
echo "cruncher: $(git log --oneline -1)"

# --- Clone yireh ---
if [ -d "/root/yireh" ]; then
    echo "yireh already exists at /root/yireh, updating remote + pulling..."
    cd /root/yireh
    git remote set-url origin "git@github.com:firmamentum/yireh.git" 2>/dev/null || true
    git checkout main
    git pull origin main
else
    echo "Cloning firmamentum/yireh → /root/yireh..."
    git clone "git@github.com:firmamentum/yireh.git" /root/yireh
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
echo "✅ SSH auth configured + repositories cloned"
echo "   SSH key: $KEY_PATH"
echo "   /root/cruncher — DEX aggregation engine"
echo "   /root/yireh    — geth fork"
echo "   All future git operations use SSH (no token needed)."
echo ""
