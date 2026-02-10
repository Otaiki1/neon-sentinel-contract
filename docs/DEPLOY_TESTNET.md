# Deploying Neon Sentinel to Sepolia Testnet

Step-by-step guide to deploy the Neon Sentinel Dojo world to **Starknet Sepolia** testnet. For Mainnet, use the same steps and swap chain name/ID where noted.

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
- **Dojo:** `dojo_sepolia.toml` exists with the same world/namespace/writers as dev; only `[env]` differs (RPC, account, and key come from environment). For the **first deploy**, `world_address` must be `"0"` (not empty); after migrate, set it to the printed world address.

If you deploy a **different** world (e.g. your own fork), change the `seed` in `dojo_sepolia.toml` so the world address is unique.

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

The script loads `.env.sepolia`, builds with the Sepolia profile, runs migration, and clears env vars on exit:

```bash
chmod +x scripts/deploy_sepolia.sh
./scripts/deploy_sepolia.sh
```

### Option B: Manual commands

```bash
source .env.sepolia
sozo -P sepolia build
sozo -P sepolia migrate
```

Sozo will print something like:

```
 profile | chain_id   | rpc_url
---------+------------+------------------------
 sepolia | SN_SEPOLIA | <RPC_PROVIDER_URL>

🌍 World deployed at block <DEPLOYED_BLOCK> with txn hash: <DEPLOYMENT_TXN_HASH>
⛩️  Migration successful with world at address <WORLD_ADDRESS>
```

Copy the **world address** and (optionally) the **block number** for the next step.

**If you see `failed to create Felt from string: invalid dec string`:** ensure `world_address` in `dojo_sepolia.toml` is `"0"` for the first deploy (not an empty string `""`).

**If you see "world address ... refers to a deployed world":** the seed already has a world on this chain. Either **upgrade it** by setting `world_address` in `dojo_sepolia.toml` to the address Sozo prints, or **deploy a new world** by changing `seed` to something unique and keeping `world_address = "0"`.

**If you see "Mismatch compiled class hash":** (1) Ensure `sierra-replace-ids = false` in `Scarb.toml` under `[cairo]` so class hashes are deterministic. (2) If the world was already deployed but "Declare N classes" failed, set `world_address` in `dojo_sepolia.toml` to the printed world address and run migrate again. (3) If the existing world was built with different code/tooling, deploy a new world with a unique seed and `world_address = "0"`.

---

## 6. Update Config After First Deploy

After the first successful deploy, set the world address (and optionally the block) in `dojo_sepolia.toml` so later commands and Torii use the correct world:

```toml
[env]
# ...
world_address = "0x_your_world_address_from_migrate_output"
world_block = 123456   # optional: block where world was deployed
```

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

3. **Create a Torii deployment** (replace placeholders):
   - `<SERVICE_NAME>` — e.g. `neon-sentinel-sepolia` (you own this name once created).
   - `<DOJO_VERSION>` — Your Dojo version (e.g. `v1.8.0`).
   - `<WORLD_ADDRESS>` — From `dojo_sepolia.toml` or the migrate output.
   - `<RPC_URL>` — Your Sepolia RPC URL.

   ```bash
   slot deployments create <SERVICE_NAME> torii --version <DOJO_VERSION> --world <WORLD_ADDRESS> --rpc <RPC_URL>
   ```

   Example:
   ```bash
   slot deployments create neon-sentinel-sepolia torii --version v1.8.0 --world 0x... --rpc https://api.cartridge.gg/x/starknet/sepolia
   ```

4. Save the endpoints Slot prints; your client will use them for GraphQL/subscriptions.

5. To recreate Torii later (safe; data is on-chain):
   ```bash
   slot deployments delete <SERVICE_NAME> torii
   slot deployments create <SERVICE_NAME> torii ...
   ```

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
   Exchange rate must be between 3 and 10 (e.g. 5 = 5 coins per STRK).

3. After that, players can `approve` STRK to the `buy_coins` contract and call `buy_coins(amount_strk, max_coins_expected)`.

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

- [ ] RPC URL and chain ID verified (SN_SEPOLIA).
- [ ] Account deployed on Sepolia with ETH.
- [ ] `.env.sepolia` created from `.env.sepolia.example` and filled.
- [ ] `sozo -P sepolia build` and `sozo -P sepolia migrate` run (or `./scripts/deploy_sepolia.sh`).
- [ ] `world_address` (and optionally `world_block`) set in `dojo_sepolia.toml`.
- [ ] (Optional) Torii created via Slot for client.
- [ ] (Optional) Coin shop initialized if using STRK purchases.

For Mainnet, repeat with a mainnet RPC, mainnet account, and profile/mainnet config (e.g. `dojo_mainnet.toml` and a mainnet deploy script).
