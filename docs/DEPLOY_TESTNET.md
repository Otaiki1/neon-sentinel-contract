# Deploying Neon Sentinel to Sepolia Testnet

Step-by-step guide to deploy the Neon Sentinel Dojo world to **Starknet Sepolia** testnet. For Mainnet, use the same steps and swap chain name/ID where noted.

---

## Redeploy vs fresh deploy

| Scenario | `world_address` in `dojo_sepolia.toml` | What happens |
|----------|----------------------------------------|---------------|
| **Fresh deploy** | Set to `"0"` | Sozo deploys a new world and all systems. After migrate, set `world_address` to the printed address. |
| **Redeploy (upgrade)** | Set to the **existing world address** (e.g. current Sepolia world) | Sozo migrates/upgrades the existing world: declares new/changed classes, updates world state. Same world address; new code. |

For the **redeploy** we do after code changes (e.g. rank system, leaderboard week, new systems): keep `world_address` as the existing world so migrate upgrades it. Do not set it to `"0"` or you will deploy a second world.

---

## 1. Prerequisites

- [Dojo / Sozo](https://book.dojoengine.org/getting-started/installation) installed.
- A **Starknet RPC provider** for the target chain (e.g. [Cartridge RPC](https://www.starknet.io/fullnodes-rpc-services/)):
  - Sepolia: `https://api.cartridge.gg/x/starknet/sepolia`
  - Mainnet: `https://api.cartridge.gg/x/starknet/mainnet`
- A **deployed Starknet account** with some **ETH** on Sepolia (e.g. from [Starknet Faucet](https://starknet-faucet.vercel.app); 0.001 ETH is enough).

---

## 2. Verify RPC and Chain ID

Check that your RPC URL is correct and returns the expected chain ID:

```bash
curl --location '<RPC_PROVIDER_URL>' \
  --header 'Content-Type: application/json' \
  --data '{"id": 0,"jsonrpc": "2.0","method": "starknet_chainId","params": {}}'
```

You should see something like:

```json
{"jsonrpc":"2.0","result":"0x534e5f5345504f4c4941","id":0}
```

Decode the hex to confirm the chain name:

```bash
echo 0x534e5f5345504f4c4941 | xxd -r -p
```

Output must be **SN_SEPOLIA** (or **SN_MAIN** for mainnet).

---

## 3. Project Configuration (Already Done)

The repo is already set up for Sepolia:

- **Scarb:** `[profile.sepolia]` is declared in `Scarb.toml`.
- **Dojo:** `dojo_sepolia.toml` exists with the same world/namespace/writers as dev; only `[env]` differs (RPC, account, and key come from environment).
  - **Fresh deploy:** Set `world_address = "0"` in `[env]`. After the first successful migrate, set it to the printed world address.
  - **Redeploy (upgrade):** Set `world_address` to the **existing** world address so Sozo upgrades that world instead of creating a new one.

If you deploy a **new** world from scratch (e.g. your own fork), change the `seed` in `dojo_sepolia.toml` so the world address is unique, and keep `world_address = "0"`.

---

## 4. Environment Variables

Create `.env.sepolia` in the project root (do not commit it). Use `.env.sepolia.example` as a template:

```bash
cp .env.sepolia.example .env.sepolia
```

Edit `.env.sepolia` and set:

```bash
# Usage: source .env.sepolia  (then run sozo -P sepolia migrate)
export STARKNET_RPC_URL=https://api.cartridge.gg/x/starknet/sepolia
export DOJO_ACCOUNT_ADDRESS=0x_your_deployed_account_address
export DOJO_PRIVATE_KEY=0x_your_private_key
```

- **STARKNET_RPC_URL** — Your Sepolia RPC URL.
- **DOJO_ACCOUNT_ADDRESS** — Your Starknet account (deployer) address.
- **DOJO_PRIVATE_KEY** — That account’s private key. Keep this secret; `.env.sepolia` is gitignored.

Ensure the account is **deployed** on Sepolia and has ETH for gas.

**Note:** If your Sozo version expects `rpc_url`, `account_address`, and `private_key` in the config file, uncomment those lines in `dojo_sepolia.toml` and set them (e.g. from your env). Do not commit real secrets; keep them in `.env.sepolia` only.

---

## 5. Deploy the World

### Option A: Using the deployment script (recommended)

The script loads `.env.sepolia`, cleans and builds with the Sepolia profile, runs migration, and (if configured) initializes or updates the coin shop. Clears env vars on exit.

**Before running:**
- **Redeploy:** Ensure `world_address` in `dojo_sepolia.toml` is the **existing** world address (so migrate upgrades it).
- **Fresh deploy:** Set `world_address = "0"`, then after success set it to the printed address.

```bash
chmod +x scripts/deploy_sepolia.sh
./scripts/deploy_sepolia.sh
```

### Option B: Manual commands

```bash
source .env.sepolia
sozo -P sepolia build
sozo -P sepolia migrate --use-blake2s-casm-class-hash
```

**Note:** Sepolia requires the blake2s CASM class hash. Without `--use-blake2s-casm-class-hash` you may see "Mismatch compiled class hash" (Actual vs Expected). The deploy script passes this flag automatically.

Sozo will print something like:

```
 profile | chain_id   | rpc_url
---------+------------+------------------------
 sepolia | SN_SEPOLIA | <RPC_PROVIDER_URL>

🌍 World deployed at block <DEPLOYED_BLOCK> with txn hash: <DEPLOYMENT_TXN_HASH>
⛩️  Migration successful with world at address <WORLD_ADDRESS>
```

Copy the **world address** and (optionally) the **block number** for the next step.

**If you see `failed to create Felt from string: invalid dec string`:** ensure `world_address` in `dojo_sepolia.toml` is `"0"` for a fresh deploy (not an empty string `""`).

**If you see "world address ... refers to a deployed world":** Sozo is upgrading that world. For a **new** world instead, change `seed` in `dojo_sepolia.toml` and set `world_address = "0"`.

**If you see "Mismatch compiled class hash":** (1) Ensure `sierra-replace-ids = false` in `Scarb.toml` under `[cairo]`. (2) For redeploy, ensure `world_address` is the existing world and run migrate again. (3) If the existing world was built with different tooling, deploy a new world (new `seed`, `world_address = "0"`).

---

## 6. Update Config After First Deploy (fresh deploy only)

After the **first** successful deploy (new world), set the world address (and optionally the block) in `dojo_sepolia.toml` so later commands and Torii use the correct world:

```toml
[env]
# ...
world_address = "0x_your_world_address_from_migrate_output"
world_block = 123456   # optional: block where world was deployed
```

For **redeploys**, leave `world_address` as the existing world; no change needed unless you deployed a new world with a new seed.

---

## 7. Torii Indexer (Optional, for clients)

If you are building a client that queries world state or events, run a **Torii** indexer for your world.

1. **Install or update [Slot](https://docs.cartridge.gg/slot/getting-started):**
   ```bash
   slotup
   ```

2. **Log in:**
   ```bash
   slot auth login
   ```

3. **Create a Torii deployment** — either use the script (reads world and RPC from config) or run the command manually.

   **Option A: Script (recommended)**  
   Ensure `world_address` is set in `dojo_sepolia.toml` after a successful migrate, then:
   ```bash
   chmod +x scripts/setup_torii_sepolia.sh
   ./scripts/setup_torii_sepolia.sh
   ```
   Optional: pass a custom service name: `./scripts/setup_torii_sepolia.sh my-torii-name`.

   **Option B: Manual command** — Slot requires a Torii TOML config file. Create e.g. `torii_sepolia.toml` with:
   ```toml
   world_address = "0x_your_world_address"
   rpc = "https://your-sepolia-rpc-url"
   ```
   Then run:
   ```bash
   slot deployments create neon-sentinel-sepolia torii --config torii_sepolia.toml --version v1.8.0
   ```

4. Save the endpoints Slot prints; your client will use them for GraphQL/subscriptions.

5. **After a redeploy:** If you upgraded the world (new models or schema), recreate the Torii deployment so the indexer uses the new schema:
   ```bash
   slot deployments delete <SERVICE_NAME> torii
   ./scripts/setup_torii_sepolia.sh [SERVICE_NAME]
   ```
   If the schema did not change, the existing Torii may continue to work (it indexes from chain).

---

## 8. Client / Frontend

- Use the **world address** and **Torii URL** (if you created one) in your client.
- Set the chain ID in your app env (e.g. for Vite):
  ```bash
  VITE_PUBLIC_CHAIN_ID=SN_SEPOLIA
  ```
  For mainnet: `VITE_PUBLIC_CHAIN_ID=SN_MAIN`.

- If your client uses manifests generated by Sozo, each chain has its own manifest under the profile (e.g. generated for `sepolia`); point the client at the correct one.

---

## 9. Post-Deploy: Initialize Coin Shop (Neon Sentinel)

If you use the STRK → in-game coins flow:

1. Get the **STRK token contract address** for Sepolia.
2. As the **owner** (the account that will own the coin shop), call:
   ```bash
   sozo -P sepolia execute neon_sentinel-initialize_coin_shop initialize_coin_shop <STRK_TOKEN_ADDRESS> <EXCHANGE_RATE>
   ```
   Exchange rate must be between **3 and 100** (coins per STRK; e.g. 10 = 10 coins per 1 STRK).

3. After that, players can `approve` STRK to the `buy_coins` contract and call `buy_coins(amount_strk)` (coins = amount_strk × exchange_rate).

The deploy script can initialize the shop automatically if `STRK_TOKEN_ADDRESS` is set in `.env.sepolia`; otherwise it only calls `update_exchange_rate` if the shop already exists.

See [MANUAL_TESTING_STRK.md](MANUAL_TESTING_STRK.md) for a full checklist.

---

## 10. Debugging with Walnut

Use [Walnut](https://walnut.dev) to inspect transactions on Sepolia (or Mainnet).

1. **Verify contracts** (optional, for full debugging):
   ```bash
   sozo walnut verify
   ```

2. **Debug a transaction:**
   - Open [app.walnut.dev](https://app.walnut.dev).
   - Enter your transaction hash.
   - For Slot deployments, configure the Slot RPC as a [custom network](https://docs.walnut.dev/custom-networks) in Walnut first.

---

## Quick Checklist

**Every deploy (fresh or redeploy):**
- [ ] RPC URL and chain ID verified (SN_SEPOLIA).
- [ ] Account deployed on Sepolia with ETH.
- [ ] `.env.sepolia` created from `.env.sepolia.example` and filled.
- [ ] **Redeploy:** `world_address` in `dojo_sepolia.toml` is the **existing** world address.
- [ ] **Fresh deploy:** `world_address = "0"` in `dojo_sepolia.toml`; after migrate, set it to the printed address.
- [ ] Run `./scripts/deploy_sepolia.sh` (or manual `sozo -P sepolia build` and `sozo -P sepolia migrate --use-blake2s-casm-class-hash`).
- [ ] (Optional) Coin shop: set `STRK_TOKEN_ADDRESS` in `.env.sepolia` for auto-init, or call `initialize_coin_shop` / `update_exchange_rate` manually.

**After redeploy (if models/schema changed):**
- [ ] Recreate Torii: `slot deployments delete <SERVICE_NAME> torii` then `./scripts/setup_torii_sepolia.sh`.
- [ ] Update frontend/client with new manifest or world address if needed.

**Optional (first-time or when adding indexer):**
- [ ] Torii indexer: `./scripts/setup_torii_sepolia.sh` (after Slot install + `slot auth login`).

For Mainnet, repeat with a mainnet RPC, mainnet account, and profile/mainnet config (e.g. `dojo_mainnet.toml` and a mainnet deploy script).
