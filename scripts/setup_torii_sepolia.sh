#!/usr/bin/env bash
# Create a Torii indexer for the Neon Sentinel world on Sepolia via Slot.
# Prerequisites: Slot installed (slotup), logged in (slot auth login), world already deployed.
# Usage: ./scripts/setup_torii_sepolia.sh [SERVICE_NAME]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$ROOT_DIR/dojo_sepolia.toml"
ENV_FILE="$ROOT_DIR/.env.sepolia"
SERVICE_NAME="${1:-neon-sentinel-sepolia}"
DOJO_VERSION="v1.8.0"

cd "$ROOT_DIR"

# World address from dojo_sepolia.toml (value inside quotes only)
WORLD_ADDRESS=$(grep -E '^world_address\s*=' "$CONFIG" 2>/dev/null | sed -n 's/.*"\(0x[0-9a-fA-F]*\)".*/\1/p' | tr -d ' ')
if [ -z "$WORLD_ADDRESS" ] || [ "$WORLD_ADDRESS" = "0" ]; then
  echo "Error: world_address not set in dojo_sepolia.toml. Deploy the world first (./scripts/deploy_sepolia.sh), then set world_address to the printed address."
  exit 1
fi

# RPC URL: from .env.sepolia or default
RPC_URL=""
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
  RPC_URL="${STARKNET_RPC_URL:-}"
fi
if [ -z "$RPC_URL" ]; then
  RPC_URL="https://api.cartridge.gg/x/starknet/sepolia"
  echo "Using default RPC_URL (set STARKNET_RPC_URL in .env.sepolia to override)."
fi

if ! command -v slot &>/dev/null; then
  echo "Error: Slot not found. Install it with: slotup"
  echo "See https://docs.cartridge.gg/slot/getting-started"
  exit 1
fi

# Slot expects a TOML config file (--config), not --world/--rpc. Write a minimal config.
TORII_CONFIG=$(mktemp)
trap 'rm -f "$TORII_CONFIG"' EXIT
cat > "$TORII_CONFIG" << EOF
world_address = "$WORLD_ADDRESS"
rpc = "$RPC_URL"
EOF

echo "Creating Torii deployment..."
echo "  Service name: $SERVICE_NAME"
echo "  World:        $WORLD_ADDRESS"
echo "  Dojo version: $DOJO_VERSION"
echo "  RPC:          $RPC_URL"
echo ""
echo "If not logged in, run: slot auth login"
echo ""

slot deployments create "$SERVICE_NAME" torii --config "$TORII_CONFIG" --version "$DOJO_VERSION"

echo ""
echo "Save the endpoints Slot printed; your client uses them for GraphQL and subscriptions."
