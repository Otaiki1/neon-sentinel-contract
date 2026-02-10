#!/usr/bin/env bash
# Deploy Neon Sentinel Dojo world to Starknet Sepolia testnet.
# Prerequisites: .env.sepolia with STARKNET_RPC_URL, DOJO_ACCOUNT_ADDRESS, DOJO_PRIVATE_KEY
# Usage: ./scripts/deploy_sepolia.sh

set -e

ENV_FILE=".env.sepolia"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEBUG_LOG="${ROOT_DIR}/.cursor/debug.log"

log_debug() {
  local msg="$1" hyp="${2:-}" extra="${3:-}"
  local ts=$(date +%s)000
  if [ -n "$extra" ]; then
    printf '%s\n' "{\"timestamp\":$ts,\"location\":\"deploy_sepolia.sh\",\"message\":\"$msg\",\"data\":{\"extra\":\"$extra\"},\"hypothesisId\":\"$hyp\"}" >> "$DEBUG_LOG"
  else
    printf '%s\n' "{\"timestamp\":$ts,\"location\":\"deploy_sepolia.sh\",\"message\":\"$msg\",\"hypothesisId\":\"$hyp\"}" >> "$DEBUG_LOG"
  fi
}

cd "$ROOT_DIR"

if [ -f "$ENV_FILE" ]; then
  echo "Loading environment variables from $ENV_FILE..."
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "Environment file $ENV_FILE not found!"
  echo "Copy .env.sepolia.example to .env.sepolia and set STARKNET_RPC_URL, DOJO_ACCOUNT_ADDRESS, DOJO_PRIVATE_KEY"
  exit 1
fi

cleanup_env() {
  echo "Cleaning up environment variables..."
  unset STARKNET_RPC_URL
  unset DOJO_ACCOUNT_ADDRESS
  unset DOJO_PRIVATE_KEY
  echo "Environment variables cleared."
}
trap cleanup_env EXIT

# #region agent log
WORLD_ADDR=$(grep -E '^world_address\s*=' dojo_sepolia.toml 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "unknown")
log_debug "deploy_sepolia start profile=sepolia" "H1" "world_address=$WORLD_ADDR"
# #endregion

echo "Cleaning Sozo manifests and Scarb target (hypothesis H3: clean build)..."
# #region agent log
log_debug "running sozo clean and rm -rf target" "H3" "\"step\":\"clean\""
# #endregion
sozo clean -P sepolia 2>/dev/null || true
rm -rf target

echo "Building the project (profile: sepolia)..."
# #region agent log
log_debug "sozo build start" "H3" "\"step\":\"build\""
# #endregion
sozo -P sepolia build

echo "Deploying to Sepolia..."
# #region agent log
log_debug "sozo migrate start" "H3" "\"step\":\"migrate\""
# #endregion
MIGRATE_OUT=$(mktemp)
if ! sozo -P sepolia migrate 2>&1 | tee "$MIGRATE_OUT"; then
  # #region agent log
  ERR_TAIL=$(tail -15 "$MIGRATE_OUT" | tr '\n' ' ' | sed 's/"/QUOTE/g')
  log_debug "sozo migrate failed" "H2" "error_tail=$ERR_TAIL"
  # #endregion
  rm -f "$MIGRATE_OUT"
  exit 1
fi
rm -f "$MIGRATE_OUT"

# #region agent log
log_debug "deploy_sepolia success" "H3" "\"step\":\"done\""
# #endregion
echo "Deployment completed successfully."
echo "Add the world address and optional world_block to dojo_sepolia.toml [env] section."
