#!/usr/bin/env bash
# Deploy Neon Sentinel Dojo world to Starknet Sepolia testnet.
# Prerequisites: .env.sepolia with STARKNET_RPC_URL, DOJO_ACCOUNT_ADDRESS, DOJO_PRIVATE_KEY
# Optional: STRK_TOKEN_ADDRESS in .env.sepolia to initialize the coin shop on first deploy (else only update_exchange_rate is called).
# Exchange rate is set to 10 (10 STRK = 100 coins) after migrate.
# For first deploy: set world_address = "0" in dojo_sepolia.toml [env]; after migrate, set it to the printed world address.
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

# #region agent log
# H1: sierra-replace-ids must be false for deterministic class hashes
SIERRA_VAL=$(grep -E 'sierra-replace-ids' Scarb.toml 2>/dev/null | sed 's/.*=\s*//' | tr -d ' ' || echo "missing")
printf '%s\n' "{\"timestamp\":$(date +%s)000,\"location\":\"deploy_sepolia.sh\",\"message\":\"Scarb.toml sierra-replace-ids\",\"data\":{\"sierra_replace_ids\":\"$SIERRA_VAL\"},\"hypothesisId\":\"H1\"}" >> "$DEBUG_LOG"
# #endregion

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
# H3: existing world_address causes migrate to compare against chain state
WORLD_ADDR=$(grep -E '^world_address\s*=' dojo_sepolia.toml 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "unknown")
log_debug "deploy_sepolia start profile=sepolia" "H3" "world_address=$WORLD_ADDR"
# H5: version drift can change compiled class hashes
SCARB_VER=$(scarb --version 2>/dev/null | head -1 || echo "unknown")
SOZO_VER=$(sozo --version 2>/dev/null | head -1 || echo "unknown")
printf '%s\n' "{\"timestamp\":$(date +%s)000,\"location\":\"deploy_sepolia.sh\",\"message\":\"tool versions\",\"data\":{\"scarb\":\"$SCARB_VER\",\"sozo\":\"$SOZO_VER\"},\"hypothesisId\":\"H5\"}" >> "$DEBUG_LOG"
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

# #region agent log
# H2/H4: manifest and target state after build (stale manifest or wrong profile?)
TARGET_EXISTS="false"; [ -d "target" ] && TARGET_EXISTS="true"
MANIFEST_FILES=$(find target -maxdepth 3 -name "*.json" 2>/dev/null | tr '\n' ',' || echo "none")
SAMPLE_HASH="none"
for m in target/manifest_sepolia.json manifest_sepolia.json target/dev/manifest.json; do
  [ -f "$m" ] && SAMPLE_HASH=$(grep -o '"class_hash":\s*"0x[0-9a-f]*"' "$m" 2>/dev/null | head -1 | sed 's/.*"0x/0x/' | sed 's/".*//') && break
done
printf '%s\n' "{\"timestamp\":$(date +%s)000,\"location\":\"deploy_sepolia.sh\",\"message\":\"post-build state\",\"data\":{\"target_exists\":\"$TARGET_EXISTS\",\"manifest_files\":\"$MANIFEST_FILES\",\"sample_class_hash\":\"$SAMPLE_HASH\"},\"hypothesisId\":\"H2\"}" >> "$DEBUG_LOG"
# #endregion

echo "Deploying to Sepolia..."
# #region agent log
log_debug "sozo migrate start" "H3" "\"step\":\"migrate\""
# #endregion
# Sepolia requires blake2s CASM class hash; explicit flag ensures correct hash (avoids Mismatch compiled class hash).
MIGRATE_OUT=$(mktemp)
if ! sozo -P sepolia migrate --use-blake2s-casm-class-hash 2>&1 | tee "$MIGRATE_OUT"; then
  # #region agent log
  ERR_TAIL=$(tail -15 "$MIGRATE_OUT" | tr '\n' ' ' | sed 's/"/QUOTE/g')
  log_debug "sozo migrate failed" "H2" "error_tail=$ERR_TAIL"
  # Parse mismatch hashes for root cause: class_hash_on_chain, actual_compiled, expected
  CHAIN_HASH=$(grep -oE 'class with hash 0x[0-9a-f]+' "$MIGRATE_OUT" 2>/dev/null | sed 's/.*0x/0x/' || echo "none")
  ACTUAL_HASH=$(grep -oE 'Actual: 0x[0-9a-f]+' "$MIGRATE_OUT" 2>/dev/null | sed 's/Actual: //' || echo "none")
  EXPECTED_HASH=$(grep -oE 'Expected: 0x[0-9a-f]+' "$MIGRATE_OUT" 2>/dev/null | sed 's/Expected: //' || echo "none")
  printf '%s\n' "{\"timestamp\":$(date +%s)000,\"location\":\"deploy_sepolia.sh\",\"message\":\"mismatch class hash parsed\",\"data\":{\"class_hash_on_chain\":\"$CHAIN_HASH\",\"actual_compiled\":\"$ACTUAL_HASH\",\"expected\":\"$EXPECTED_HASH\"},\"hypothesisId\":\"H2\"}" >> "$DEBUG_LOG"
  # #endregion
  rm -f "$MIGRATE_OUT"
  exit 1
fi
rm -f "$MIGRATE_OUT"

# Exchange rate: 10 STRK for 100 coins => 10 coins per STRK (contract uses coins per STRK).
COIN_EXCHANGE_RATE=10

if [ -n "${STRK_TOKEN_ADDRESS:-}" ]; then
  echo "Initializing coin shop (STRK_TOKEN_ADDRESS set) with exchange rate $COIN_EXCHANGE_RATE (10 STRK = 100 coins)..."
  if sozo -P sepolia execute neon_sentinel-initialize_coin_shop initialize_coin_shop "$STRK_TOKEN_ADDRESS" "$COIN_EXCHANGE_RATE" --wait 2>&1; then
    echo "Coin shop initialized with rate $COIN_EXCHANGE_RATE."
  else
    echo "Warning: initialize_coin_shop failed (e.g. already initialized). Trying update_exchange_rate..."
    sozo -P sepolia execute neon_sentinel-update_exchange_rate update_exchange_rate "$COIN_EXCHANGE_RATE" --wait 2>&1 || true
  fi
else
  echo "Setting exchange rate to $COIN_EXCHANGE_RATE (10 STRK = 100 coins)..."
  if sozo -P sepolia execute neon_sentinel-update_exchange_rate update_exchange_rate "$COIN_EXCHANGE_RATE" --wait 2>&1; then
    echo "Exchange rate updated to $COIN_EXCHANGE_RATE."
  else
    echo "Warning: update_exchange_rate failed (e.g. shop not initialized). Set STRK_TOKEN_ADDRESS in $ENV_FILE and re-run to initialize, or call initialize_coin_shop manually."
  fi
fi

# #region agent log
log_debug "deploy_sepolia success" "H3" "\"step\":\"done\""
# #endregion
echo "Deployment completed successfully."
echo "Add the world address and optional world_block to dojo_sepolia.toml [env] section."
