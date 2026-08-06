#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration / Input Variables
# -----------------------------------------------------------------------------
INPUT_PRIVATE_KEY="${INPUT_PRIVATE_KEY:-${1:-}}"                  # REQUIRED
INPUT_FILES="${INPUT_FILES:-}"                                    # REQUIRED
INPUT_PASSPHRASE="${INPUT_PASSPHRASE:-}"                          # Optional
INPUT_NAMESPACE="${INPUT_NAMESPACE:-file}"                        # Optional (Default: file)
INPUT_PRINCIPAL="${INPUT_PRINCIPAL:-}"                            # Required if GENERATE_ALLOWED_SIGNERS=true
INPUT_GENERATE_ALLOWED_SIGNERS="${INPUT_GENERATE_ALLOWED_SIGNERS:-false}" # Optional
INPUT_SIG_DIR="${INPUT_SIG_DIR:-}"                                # Optional
INPUT_ALLOWED_SIGNERS_DIR="${INPUT_ALLOWED_SIGNERS_DIR:-}"        # Optional

# Helper function to append outputs safely to GitHub Actions step context
set_output() {
  local name="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    # Create a random EOF delimiter to prevent delimiter collision
    local delimiter
    delimiter="EOF_$(dd if=/dev/urandom bs=15 count=1 status=none | base64 | tr -dc 'a-zA-Z0-9')"
    {
      echo "${name}<<${delimiter}"
      echo "${value}"
      echo "${delimiter}"
    } >> "$GITHUB_OUTPUT"
  fi
}

# -----------------------------------------------------------------------------
# 1. Fail-Fast Input Validation
# -----------------------------------------------------------------------------
if [[ -z "$INPUT_PRIVATE_KEY" ]]; then
  echo "❌ Missing required input 'private-key'." >&2
  exit 1
fi

if [[ -z "$INPUT_FILES" ]]; then
  echo "❌ Missing required input 'files'." >&2
  exit 1
fi

if [[ "$INPUT_GENERATE_ALLOWED_SIGNERS" == "true" && -z "$INPUT_PRINCIPAL" ]]; then
  echo "❌ Input 'principal' is required when 'generate-allowed-signers' is set to true." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Setup ssh-agent Context
# -----------------------------------------------------------------------------
SPAWNED_AGENT=false
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  eval "$(ssh-agent -s)" >/dev/null
  SPAWNED_AGENT=true
fi

# -----------------------------------------------------------------------------
# 3. Prepare Temporary Files & Cleanup Trap
# -----------------------------------------------------------------------------
KEY_FILE=$(mktemp)
chmod 600 "$KEY_FILE"

PUB_KEY_FILE=""
ASKPASS_SCRIPT=""
COUNTER_FILE=""
SSH_ADD_ERR=""

cleanup() {
  # Disable tracing during cleanup to prevent accidental variable leaking
  { set +x; } 2>/dev/null

  if [[ "$SPAWNED_AGENT" == "true" ]]; then
    eval "$(ssh-agent -k)" >/dev/null 2>&1 || true
  elif [[ -n "${PUB_KEY_FILE:-}" && -f "$PUB_KEY_FILE" ]]; then
    ssh-add -d "$PUB_KEY_FILE" >/dev/null 2>&1 || true
  fi

  rm -f "${KEY_FILE:-}" "${PUB_KEY_FILE:-}" "${ASKPASS_SCRIPT:-}" "${COUNTER_FILE:-}" "${SSH_ADD_ERR:-}"
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# 4. Extract Public Key & Load into Agent
# -----------------------------------------------------------------------------
SSH_ADD_ERR=$(mktemp)
PUB_KEY_FILE=$(mktemp)

# Turn off command tracing explicitly to protect private key and passphrase from logs
{ set +x; } 2>/dev/null

if [[ -f "$INPUT_PRIVATE_KEY" ]]; then
  cat "$INPUT_PRIVATE_KEY" > "$KEY_FILE"
else
  printf '%s\n' "$INPUT_PRIVATE_KEY" > "$KEY_FILE"
fi

if [[ -n "$INPUT_PASSPHRASE" ]]; then
  ASKPASS_SCRIPT=$(mktemp)
  COUNTER_FILE=$(mktemp)

  cat << EOF > "$ASKPASS_SCRIPT"
#!/usr/bin/env bash
if [[ -f "$COUNTER_FILE" ]]; then
  exit 1
fi
touch "$COUNTER_FILE"
echo "$INPUT_PASSPHRASE"
EOF
  chmod +x "$ASKPASS_SCRIPT"

  rm -f "$COUNTER_FILE"
  SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$ASKPASS_SCRIPT" ssh-keygen -y -f "$KEY_FILE" < /dev/null > "$PUB_KEY_FILE"

  rm -f "$COUNTER_FILE"
  SSH_ASKPASS_REQUIRE=force SSH_ASKPASS="$ASKPASS_SCRIPT" ssh-add "$KEY_FILE" < /dev/null 2> "$SSH_ADD_ERR"
  STATUS=$?
else
  ssh-keygen -y -f "$KEY_FILE" > "$PUB_KEY_FILE"

  ssh-add "$KEY_FILE" < /dev/null 2> "$SSH_ADD_ERR"
  STATUS=$?
fi

# Re-enable strict execution rules after secret operations complete
set -euo pipefail

if [[ $STATUS -ne 0 ]]; then
  ERR_MSG=$(cat "$SSH_ADD_ERR" 2>/dev/null || true)
  echo "❌ Failed to add SSH key to agent." >&2
  if [[ -n "$ERR_MSG" ]]; then
    echo "Details: $ERR_MSG" >&2
  else
    echo "Details: Key loading failed (exit code $STATUS). Please verify your passphrase or key format." >&2
  fi
  exit 1
fi

PUB_KEY_CONTENT=$(cat "$PUB_KEY_FILE")
KEY_TYPE_AND_DATA=$(echo "$PUB_KEY_CONTENT" | cut -d' ' -f1,2)

# -----------------------------------------------------------------------------
# 5. Sign Target Files
# -----------------------------------------------------------------------------
if [[ -n "$INPUT_SIG_DIR" ]]; then
  mkdir -p "$INPUT_SIG_DIR"
fi

SIGNED_FILES=""
SIG_FILES=""
SIGNED_COUNT=0

for file in $INPUT_FILES; do
  if [[ -f "$file" ]]; then
    ssh-keygen -Y sign -f "$PUB_KEY_FILE" -n "$INPUT_NAMESPACE" "$file"

    filename=$(basename "$file")
    if [[ -n "$INPUT_SIG_DIR" ]]; then
      target_sig="${INPUT_SIG_DIR}/${filename}.sig"
      mv "${file}.sig" "$target_sig"
    else
      target_sig="${file}.sig"
    fi

    SIGNED_FILES="${SIGNED_FILES:+$SIGNED_FILES }$file"
    SIG_FILES="${SIG_FILES:+$SIG_FILES }$target_sig"
    SIGNED_COUNT=$((SIGNED_COUNT + 1))
  else
    echo "⚠️ File '$file' not found, skipping." >&2
  fi
done

if [[ "$SIGNED_COUNT" -eq 0 ]]; then
  echo "❌ No valid target files were found to sign." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 6. Optional: Output allowed_signers File
# -----------------------------------------------------------------------------
ALLOWED_SIGNERS_PATH=""
if [[ "$INPUT_GENERATE_ALLOWED_SIGNERS" == "true" ]]; then
  target_dir="${INPUT_ALLOWED_SIGNERS_DIR:-.}"
  mkdir -p "$target_dir"

  ALLOWED_SIGNERS_PATH="${target_dir}/allowed_signers"
  echo "$INPUT_PRINCIPAL $KEY_TYPE_AND_DATA" > "$ALLOWED_SIGNERS_PATH"
  echo "🔑 Generated allowed_signers file at: $ALLOWED_SIGNERS_PATH" >&2
fi

# -----------------------------------------------------------------------------
# 7. Write Action Step Outputs
# -----------------------------------------------------------------------------
set_output "signed-files" "$SIGNED_FILES"
set_output "sig-files" "$SIG_FILES"
set_output "allowed-signers-path" "$ALLOWED_SIGNERS_PATH"
set_output "public-key" "$PUB_KEY_CONTENT"

echo "✅ Successfully signed $SIGNED_COUNT file(s)." >&2