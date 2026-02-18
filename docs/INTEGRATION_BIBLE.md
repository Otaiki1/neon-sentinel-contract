# Neon Sentinel — Frontend Integration Bible

This guide is for frontend developers integrating the Neon Sentinel **Dojo contracts** with the game client using **Cartridge** (Controller wallet, RPC, Torii). It covers: Cartridge + React setup, deployed contract addresses from `manifest_sepolia.json`, system calls (calldata), reading state via Torii GraphQL, and end-to-end flows.

---

## 1. Stack Overview

| Component | Role |
| --------- | ----- |
| **Cartridge Controller** | Smart contract wallet (passkeys, session keys, Paymaster). Users connect via `ControllerConnector` in React. |
| **Cartridge RPC** | Starknet RPC for Sepolia; used by the app and Controller to send transactions. |
| **Torii (Cartridge-hosted)** | Indexer + GraphQL API for querying world state (Player, RunState, PlayerProfile, LeaderboardEntry, etc.). |
| **World contract** | Dojo world on Starknet; systems are separate contracts. You call system **contract addresses** directly. |

**Integration flow:**

1. **Read state** — Torii GraphQL (queries and subscriptions) for entities and events.
2. **Writes (transactions)** — Starknet provider (via Cartridge RPC) + player’s account (Controller); invoke system contracts by **contract address** and **entrypoint** with calldata.

---

## 2. Live Sepolia Deployment

All values below come from **`manifest_sepolia.json`** in this repo. Use them for production Sepolia integration.

### 2.1 Network and World

| Item | Value |
|------|--------|
| **Chain** | Starknet Sepolia |
| **Chain ID** | `SN_SEPOLIA` (e.g. `0x534e5f5345504f4c4941` or your SDK’s constant) |
| **World address** | `0x4fa7aba1a6f464a1bd73728e1d1c14f60d8099c606ac993d6af27c0ce82e0c1` |
| **RPC URL (Cartridge)** | `https://api.cartridge.gg/x/starknet/sepolia` |
| **Torii base URL** | `https://api.cartridge.gg/x/neon-sentinel-sepolia/torii` |
| **GraphQL endpoint** | `https://api.cartridge.gg/x/neon-sentinel-sepolia/torii/graphql` |

### 2.2 System Contract Addresses (manifest_sepolia.json)

Use these **contract addresses** when calling system entrypoints (e.g. with `account.execute()` or your SDK’s equivalent).

| Tag | Contract address |
|-----|-------------------|
| `neon_sentinel-init_game` | `0x23ce7035b962d84a899d463eadddfdee28bf05b9a35fb331b6afc436aab0f6` |
| `neon_sentinel-end_run` | `0x1fa4bbc70303e98fa88dbcb147571387fd139ca949a126fbf95d57b7e82def7` |
| `neon_sentinel-submit_leaderboard` | `0x60c1412d8b151fb0e048ecbb9fe6ef098b1d342ea6b5337d1ad159c769c26c2` |
| `neon_sentinel-claim_coins` | `0x77b6c7ba126988a1109cb0b6188d978a419bd77adcb3278f4b6934f4ae32b7a` |
| `neon_sentinel-spend_coins` | `0x72f707e406978dbbeb046004325002156afc04a8787ee23d85dc37cffe7e333` |
| `neon_sentinel-buy_coins` | `0x66c2f66463c5d92b43f6c204e6f3a9cc9b52f411d6cc20d9f2566eb5af27207` |
| `neon_sentinel-initialize_coin_shop` | `0x2c9a4672b4b373983b261c0cf3bbcd51ef81557ba6f9a6589f9608699f6a2f1` |
| `neon_sentinel-update_exchange_rate` | `0x76e70704f6cb3ce06e528e1393b6a3407d47ec5502543d453aba2937a12f851` |
| `neon_sentinel-pause_unpause_purchasing` | `0x159731ccb1308dc67def4d2e61cc47cf926f31a87bd6505f1bf0b80f8095ce4` |
| `neon_sentinel-purchase_cosmetic` | (see manifest after deploy) |
| `neon_sentinel-spend_revive` | (see manifest after deploy) |
| `neon_sentinel-purchase_mini_me_unit` | (see manifest after deploy) |
| `neon_sentinel-purchase_mini_me_sessions` | (see manifest after deploy) |
| `neon_sentinel-actions` | `0xe00343a1465ce60216103c8c24a1428aed9ccb6874c2bcfc6226042b050831` |

**Source of truth:** `manifest_sepolia.json` in this repo. Use `contracts[].address` and `contracts[].tag` for each system. After a redeploy, run `sozo -P sepolia build` and use the new manifest; update this table or generate a frontend config from the manifest.

---

## 3. Cartridge + React Setup

### 3.1 Packages

```bash
pnpm add @cartridge/connector @cartridge/controller @starknet-react/core @starknet-react/chains starknet
# or
npm i @cartridge/connector @cartridge/controller @starknet-react/core @starknet-react/chains starknet
```

### 3.2 Chain and RPC

Use **Sepolia** and Cartridge’s Sepolia RPC so that transactions and Controller use the same chain as the deployed world.

```ts
import { sepolia } from "@starknet-react/chains";
import { StarknetConfig, jsonRpcProvider } from "@starknet-react/core";
import { ControllerConnector } from "@cartridge/connector";
```

### 3.3 Provider and StarknetConfig

Create the connector **outside** React components (e.g. in a module or root file). Point the RPC to Cartridge Sepolia.

```ts
// e.g. src/starknet.ts or providers/StarknetProvider.tsx
import { sepolia } from "@starknet-react/chains";
import { StarknetConfig, jsonRpcProvider, cartridge } from "@starknet-react/core";
import { ControllerConnector } from "@cartridge/connector";

const connector = new ControllerConnector({
  // policies: gamePolicies,  // optional: session policies for gasless txs
});

const provider = jsonRpcProvider({
  rpc: (chain) => {
    if (chain.id === sepolia.id) {
      return { nodeUrl: "https://api.cartridge.gg/x/starknet/sepolia" };
    }
    return { nodeUrl: "https://api.cartridge.gg/x/starknet/sepolia" }; // or your default
  },
});

export function StarknetProvider({ children }: { children: React.ReactNode }) {
  return (
    <StarknetConfig
      chains={[sepolia]}
      defaultChainId={sepolia.id}
      provider={provider}
      connectors={[connector]}
      explorer={cartridge}
      autoConnect
    >
      {children}
    </StarknetConfig>
  );
}
```

Wrap your app with `StarknetProvider` (e.g. in `main.tsx` or `App.tsx`).

### 3.4 Connect Wallet (useAccount / useConnect)

```ts
import { useAccount, useConnect, useDisconnect } from "@starknet-react/core";
import { ControllerConnector } from "@cartridge/connector";

function ConnectButton() {
  const { address } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const controller = connectors[0] as ControllerConnector;

  if (address) {
    return (
      <div>
        <span>Account: {address}</span>
        <button onClick={() => disconnect()}>Disconnect</button>
      </div>
    );
  }

  return (
    <button onClick={() => connect({ connector: controller })}>
      Connect with Cartridge
    </button>
  );
}
```

### 3.5 Optional: Session Policies (gasless / pre-approved txs)

To allow gasless or session-based calls to game systems, define policies and pass them into `ControllerConnector`. Use the **system contract addresses** from §2.2.

```ts
import { SessionPolicies } from "@cartridge/controller";

const INIT_GAME = "0x23ce7035b962d84a899d463eadddfdee28bf05b9a35fb331b6afc436aab0f6";
const END_RUN = "0x1fa4bbc70303e98fa88dbcb147571387fd139ca949a126fbf95d57b7e82def7";
const CLAIM_COINS = "0x77b6c7ba126988a1109cb0b6188d978a419bd77adcb3278f4b6934f4ae32b7a";
const SUBMIT_LEADERBOARD = "0x60c1412d8b151fb0e048ecbb9fe6ef098b1d342ea6b5337d1ad159c769c26c2";
const SPEND_COINS = "0x72f707e406978dbbeb046004325002156afc04a8787ee23d85dc37cffe7e333";
const BUY_COINS = "0x66c2f66463c5d92b43f6c204e6f3a9cc9b52f411d6cc20d9f2566eb5af27207";

const gamePolicies: SessionPolicies = {
  contracts: {
    [INIT_GAME]: {
      name: "Neon Sentinel – Start Run",
      description: "Start a new game run",
      methods: [{ name: "init_game", entrypoint: "init_game" }],
    },
    [END_RUN]: {
      name: "Neon Sentinel – End Run",
      description: "Finish run and submit final score",
      methods: [{ name: "end_run", entrypoint: "end_run" }],
    },
    [CLAIM_COINS]: {
      name: "Neon Sentinel – Claim Coins",
      description: "Daily coin claim",
      methods: [{ name: "claim_coins", entrypoint: "claim_coins" }],
    },
    [SUBMIT_LEADERBOARD]: {
      name: "Neon Sentinel – Submit Leaderboard",
      description: "Submit run to weekly leaderboard",
      methods: [{ name: "submit_leaderboard", entrypoint: "submit_leaderboard" }],
    },
    [SPEND_COINS]: {
      name: "Neon Sentinel – Spend Coins",
      description: "Spend in-game coins",
      methods: [{ name: "spend_coins", entrypoint: "spend_coins" }],
    },
    [BUY_COINS]: {
      name: "Neon Sentinel – Buy Coins",
      description: "Purchase in-game coins with STRK",
      methods: [{ name: "buy_coins", entrypoint: "buy_coins" }],
    },
  },
};

const connector = new ControllerConnector({ policies: gamePolicies });
```

---

## 4. System Calls (Entrypoints and Calldata)

All calls are from the **player’s account** (Controller). Use `account.execute([...])` (e.g. from `useAccount()`). Calldata follows Starknet ABI: **u256** = two felts `[low, high]`, **felt252** = short string (e.g. `starknetShortString()` or numeric encoding).

### 4.1 Address constants (from manifest)

```ts
export const NEON_SENTINEL = {
  WORLD: "0x4fa7aba1a6f464a1bd73728e1d1c14f60d8099c606ac993d6af27c0ce82e0c1",
  INIT_GAME: "0x23ce7035b962d84a899d463eadddfdee28bf05b9a35fb331b6afc436aab0f6",
  END_RUN: "0x1fa4bbc70303e98fa88dbcb147571387fd139ca949a126fbf95d57b7e82def7",
  SUBMIT_LEADERBOARD: "0x60c1412d8b151fb0e048ecbb9fe6ef098b1d342ea6b5337d1ad159c769c26c2",
  CLAIM_COINS: "0x77b6c7ba126988a1109cb0b6188d978a419bd77adcb3278f4b6934f4ae32b7a",
  SPEND_COINS: "0x72f707e406978dbbeb046004325002156afc04a8787ee23d85dc37cffe7e333",
  BUY_COINS: "0x66c2f66463c5d92b43f6c204e6f3a9cc9b52f411d6cc20d9f2566eb5af27207",
} as const;
```

### 4.2 init_game (start_run)

- **Contract address:** `NEON_SENTINEL.INIT_GAME`
- **Entrypoint:** `init_game`
- **Calldata:** `[kernel: u8, pregame_upgrades_mask_low: u128, pregame_upgrades_mask_high: u128, expected_cost: u32]`
  - `kernel`: 0..5; kernel 0 is always allowed; kernels 1..5 must be unlocked (purchased via **purchase_cosmetic**).
  - `pregame_upgrades_mask`: u256 as two felts (low, high)
  - `expected_cost`: must equal popcount(mask) × 1 (coin per upgrade)
- **Run hash (run_id):** The contract generates a deterministic **run_id** (run hash) from block + timestamp + caller. Store it from **Player.run_id** after calling init_game; you must pass this same run_id to **end_run** to consolidate that run. If you call **init_game** again without ending the previous run, the previous run is abandoned (no consolidation); the new run gets a new run_id.

```ts
// Example: kernel 0, no upgrades, cost 0
await account.execute({
  contractAddress: NEON_SENTINEL.INIT_GAME,
  entrypoint: "init_game",
  calldata: [
    0,   // kernel
    "0x0", "0x0",  // pregame_upgrades_mask low, high
    0,   // expected_cost
  ],
});
```

### 4.3 end_run (BALANCED)

- **Contract address:** `NEON_SENTINEL.END_RUN`
- **Entrypoint:** `end_run`
- **Calldata:** `[run_id_low, run_id_high, final_score: u64, total_kills: u32, final_layer: u8]`
  - `run_id`: run hash from current `Player.run_id` (u256 = low + high); must match the run you started so the chain can consolidate that run.
  - `final_score`, `total_kills`, `final_layer`: client-computed from your game. `final_layer` must be 1..6.

```ts
await account.execute({
  contractAddress: NEON_SENTINEL.END_RUN,
  entrypoint: "end_run",
  calldata: [
    runId.low, runId.high,
    finalScore,
    totalKills,
    finalLayer,
  ],
});
```

### 4.4 submit_leaderboard

- **Contract address:** `NEON_SENTINEL.SUBMIT_LEADERBOARD`
- **Entrypoint:** `submit_leaderboard`
- **Calldata:** `[run_id_low, run_id_high, week: u32]`
  - `week = floor(block_number / 50400)`; get current block from provider and compute, or query from chain.

```ts
await account.execute({
  contractAddress: NEON_SENTINEL.SUBMIT_LEADERBOARD,
  entrypoint: "submit_leaderboard",
  calldata: [runId.low, runId.high, currentWeek],
});
```

### 4.5 claim_coins

- **Contract address:** `NEON_SENTINEL.CLAIM_COINS`
- **Entrypoint:** `claim_coins`
- **Calldata:** none

```ts
await account.execute({
  contractAddress: NEON_SENTINEL.CLAIM_COINS,
  entrypoint: "claim_coins",
  calldata: [],
});
```

### 4.6 spend_coins

- **Contract address:** `NEON_SENTINEL.SPEND_COINS`
- **Entrypoint:** `spend_coins`
- **Calldata:** `[amount: u32, reason: felt252]`
  - `reason`: e.g. short string; encode as felt (or numeric) per your ABI.

```ts
await account.execute({
  contractAddress: NEON_SENTINEL.SPEND_COINS,
  entrypoint: "spend_coins",
  calldata: [amount, encodeShortString("pregame_upgrades")], // example
});
```

### 4.7 purchase_cosmetic

- **Contract address:** `NEON_SENTINEL.PURCHASE_COSMETIC` (from manifest after deploy)
- **Entrypoint:** `purchase_cosmetic`
- **Calldata:** `[item_type: u8, item_id: u8]`
  - `item_type`: 0 = kernel, 1 = avatar, 2 = skin
  - `item_id`: for kernel 0..10 (kernel 0 free; 1..10 have price and prestige requirement; kernel 10 also requires Prime Sentinel). See catalog below. Avatar/skin: bit index 0..63, 1 coin each.
- Deducts coins and sets the corresponding bit in `PlayerProfile.kernel_unlocks`, `avatar_unlocks`, or `cosmetic_unlocks`. For kernel, also sets `selected_kernel`.

### 4.8 spend_revive (in-run revive)

- **Contract address:** `NEON_SENTINEL.SPEND_REVIVE`
- **Entrypoint:** `spend_revive`
- **Calldata:** `[run_id_low, run_id_high]`
- Caller must have an active run with this `run_id`. Cost = **100 × 2^revive_count** (1st revive 100, 2nd 200, 3rd 400, …). Increments `RunState.revive_count` and deducts coins.

### 4.9 purchase_mini_me_unit (Mini-Me inventory)

- **Contract address:** `NEON_SENTINEL.PURCHASE_MINI_ME_UNIT`
- **Entrypoint:** `purchase_mini_me_unit`
- **Calldata:** `[unit_type]` (u8, 0..6: Scout, Gunner, Shield, Decoy, Collector, Stun, Healer). Prices: 50, 75, 100, 100, 75, 125, 125. Max 20 units per type. Deducts coins and increments `MiniMeInventory(player, unit_type).count`.

### 4.10 purchase_mini_me_sessions (session pack)

- **Contract address:** `NEON_SENTINEL.PURCHASE_MINI_ME_SESSIONS`
- **Entrypoint:** `purchase_mini_me_sessions`
- **Calldata:** `[]`
- Cost 100 coins. Permanently adds +3 sessions (updates `PlayerProfile.mini_me_sessions_purchased`). Session capacity = 3 + mini_me_sessions_purchased × 3; refill on prestige is client-side.

### 4.11 buy_coins (STRK → coins)

- **Contract address:** `NEON_SENTINEL.BUY_COINS`
- **Entrypoint:** `buy_coins`
- **Calldata:** `[amount_strk_low, amount_strk_high]`
  - User must **approve STRK** to the `BUY_COINS` contract first (ERC20 approve).
  - Coins received = amount_strk × exchange_rate (from TokenPurchaseConfig); no slippage parameter.

STRK token address is in **TokenPurchaseConfig** (query via Torii or read from your config if known). The game coin is not a real token; the STRK→coin exchange rate can be set later by the owner via **update_exchange_rate** (rate cap 3..100).

### 4.12 Coins & purchases catalog (frontend reference)

Prices and requirements are fixed in `src/coin_shop_config.cairo`; frontend can mirror for UX.

**Pregame upgrades (bit 0..6):** Extra Heart 25, Double Heart 50, Reinforced Core 40, Overcharged Gun 45, Rapid Fire 40, Extended Boost 35, Agility Pack 30. `expected_cost` in init_game = sum of prices for set bits in mask.

**Kernels (0..10):** 0 free/P0; 1–2: 500/P1; 3–4: 1500/P2; 5: 2000/P3; 6–7: 3000–3500/P4; 8: 4000/P5; 9: 5000/P6; 10: 7500/P8 + Prime Sentinel. Query `PlayerProfile.current_prestige`, `is_prime_sentinel` for eligibility.

**Revive:** cost = 100 × 2^revive_count. Query `RunState.revive_count` for active run.

**Earning:** Daily 3 coins (claim_coins, 7200 blocks); Prime Sentinel 3 coins once per 7200 blocks (claim_coins when is_prime_sentinel); prestige 2×2^prestige when clearing layer 6 (end_run); STRK rate from TokenPurchaseConfig (e.g. 1 STRK = 100 coins).

---

## 5. Reading State: Torii GraphQL

Use the **GraphQL endpoint** for all read state and subscriptions:

- **URL:** `https://api.cartridge.gg/x/neon-sentinel-sepolia/torii/graphql`

Torii exposes a schema for Dojo entities (models). Entity names and keys follow the deployed schema (often derived from model names, e.g. `Player`, `RunState`, `PlayerProfile`). Inspect the schema (e.g. via introspection or Torii docs) for exact field and filter names.

### 5.1 Example: PlayerProfile by address

```graphql
query GetPlayerProfile($address: String!) {
  playerProfile(where: { player_address: $address }) {
    player_address
    coins
    last_coin_claim_block
    total_runs
    lifetime_score
    best_run_score
    current_layer
    selected_kernel
    avatar_unlocks
  }
}
```

Variables: `{ "address": "0x..." }`

### 5.2 Example: Player (active run) and RunState

```graphql
query GetPlayerAndRun($address: String!) {
  player(where: { player_address: $address }) {
    player_address
    run_id_low
    run_id_high
    is_active
    x
    y
    lives
    kernel
  }
  runStates(where: { player_address: $address }) {
    run_id_low
    run_id_high
    is_finished
    final_score
    enemies_defeated
    final_layer
    submitted_to_leaderboard
  }
}
```

Use `run_id_low` / `run_id_high` from Player to match the correct RunState row. If your schema uses different key names (e.g. `run_id` as composite), adjust the filter.

### 5.3 Example: Leaderboard by week

```graphql
query GetLeaderboard($week: Int!) {
  leaderboardEntries(where: { week: $week }, order: { final_score: "desc" }, limit: 100) {
    entry_id_low
    entry_id_high
    player_address
    final_score
    deepest_layer
    prestige_level
    survival_blocks
    enemies_defeated
  }
}
```

Exact field names (e.g. `entry_id_low` vs `entry_id`) depend on the generated Torii schema; use introspection or your deployment’s schema.

### 5.4 Leaderboard ranking and user metrics

**Leaderboard ranking** (general game state): query **LeaderboardEntry** by week, order by `final_score` desc (see §5.3). **User metrics**: query **PlayerProfile** by `player_address` for lifetime_score, best_run_score, current_layer, etc.

### 5.5 Rank NFTs

Query **RankNFT** by `owner` to list a player's rank achievement NFTs (minted at end_run when they reach a new tier): `rankNFTs(where: { owner: $owner }) { token_id_low, token_id_high, rank_tier, prestige, layer, achieved_at_block }`.

### 5.6 Subscriptions

Use GraphQL subscriptions on the same endpoint to react to entity updates (e.g. after `end_run` or `claim_coins`) without polling.

---

## 6. Entities (Models) Quick Reference

| Entity | Key(s) | Use |
|--------|--------|-----|
| **Player** | player_address | Active run: run_id, is_active, lives, position, kernel. |
| **RunState** | player_address, run_id | Score, layer, is_finished, final_score, enemies_defeated, final_layer, submitted_to_leaderboard, revive_count, current_prestige, pregame_upgrades_mask. |
| **PlayerProfile** | player_address | Coins, last_coin_claim_block, current_prestige, is_prime_sentinel, total_runs, lifetime_score, best_run_score, current_layer, kernel_unlocks, selected_kernel, last_prime_sentinel_claim_block, mini_me_sessions_purchased, etc. |
| **MiniMeInventory** | player_address, unit_type | count (0..20 per type). |
| **LeaderboardEntry** | entry_id | Leaderboard rows; filter by week, sort by final_score. |
| **GameEvent** | event_id | game_start (6), game_end (7); filter by run_id / player_address. |
| **TokenPurchaseConfig** | owner | coin_exchange_rate, strk_token_address (for buy_coins UI). Rate can be set later via update_exchange_rate. |
| **CoinShopGlobal** | global_key (0) | Shop owner; paused state may be on TokenPurchaseConfig. |
| **RankNFT** | token_id | Rank achievement NFTs (owner, rank_tier, prestige, layer, achieved_at_block, run_id). |

Torii model tags in the manifest follow `neon_sentinel-<ModelName>` (e.g. `neon_sentinel-PlayerProfile`). The GraphQL schema may expose them as camelCase or with different key names; always check the live schema.

---

## 7. Recommended Frontend Flows

The integration tests in **`src/tests/test_systems_integration.cairo`** mirror these flows and serve as a contract-level guide: see `test_user_journey_*` for full journey (claim coins → purchase cosmetic → start run → end run → submit leaderboard), and single-flow tests for each step.

### 7.1 Load player state

1. Ensure chain is Sepolia and user is connected (Controller).
2. Query Torii: **PlayerProfile** and **Player** by `player_address`.
3. If **Player.is_active**, query **RunState** for that `run_id` (use run_id from Player).

### 7.2 Claim or buy coins

- **Claim:** If `block_number - last_coin_claim_block >= 7200` (or first claim), call **claim_coins** (no calldata). Get block number from provider.
- **Buy with STRK:** Approve STRK to `NEON_SENTINEL.BUY_COINS`, then call **buy_coins**(amount_strk). Coins = amount_strk × exchange_rate from **TokenPurchaseConfig**.

### 7.3 Start a run (init_game)

1. Ensure **PlayerProfile.coins** ≥ upgrade cost; **kernel** must be 0 or an unlocked kernel (see **purchase_cosmetic**).
2. Call **init_game**(kernel, pregame_upgrades_mask, expected_cost). If the player already had an active run, that run is abandoned (no consolidation); a new run_id is generated.
3. Read **Player.run_id** (run hash) and **RunState** from Torii; use this run_id when calling **end_run**.
4. Refresh Player and RunState from Torii.

### 7.4 Gameplay (client-side)

Simulate run locally; on game over compute `final_score`, `total_kills`, `final_layer`.

### 7.5 End run and submit to leaderboard

1. Call **end_run**(run_id, final_score, total_kills, final_layer).
2. After confirmation, compute `week = floor(block_number / 50400)` and call **submit_leaderboard**(run_id, week).
3. Refresh Player, RunState, PlayerProfile, and leaderboard from Torii.

### 7.6 Leaderboard view

Query **LeaderboardEntry** by week, order by final_score; display in your Hall of Fame UI.

---

## 8. Errors and Validation

Map contract reverts to user-facing messages:

| Revert / condition | Message / handling |
|--------------------|--------------------|
| Invalid kernel | "Kernel must be 0–5." |
| Kernel not unlocked | "Purchase this kernel with coins first (purchase_cosmetic)." |
| Insufficient coins | "Not enough coins." |
| Run not active / Run id mismatch | "No active run or wrong run. Use current Player.run_id." |
| Already finished | "Run already ended." |
| Already submitted | "Already submitted to leaderboard." |
| Week mismatch | "Submit in the correct leaderboard week." |
| Too soon to claim | "Next claim in X blocks." |
| Purchasing paused | "Coin shop is paused." |
| STRK / approval / amount | "Check STRK approval and amount; shop may be paused." |

Use block number for cooldowns and week; do not rely on client time for game rules.

---

## 9. Numbers Quick Reference

| Concept | Value |
|--------|--------|
| Coins per daily claim | 3 |
| Blocks per day (claim cooldown) | 7200 |
| Blocks per week (leaderboard) | 50400 |
| Kernel range | 0..5 |
| Starting lives / max lives | 3 / 20 |
| Combo 1.0x (basis) | 1000 |
| Max layer | 6 |
| Bonus coins when final_score ≥ 1000 | 10 |

---

## 10. Integration Checklist

- [ ] **Cartridge + React:** Install `@cartridge/connector`, `@cartridge/controller`, `@starknet-react/core`, `@starknet-react/chains`, `starknet`. Create connector and `StarknetConfig` with Cartridge Sepolia RPC and ControllerConnector.
- [ ] **Chain:** Use Starknet Sepolia; default chain = Sepolia in StarknetConfig.
- [ ] **Addresses:** Use contract addresses from §2.2 (or import from `manifest_sepolia.json`). World address §2.1 for any world-level reads.
- [ ] **Torii:** Set GraphQL URL to `https://api.cartridge.gg/x/neon-sentinel-sepolia/torii/graphql`. Use for Player, RunState, PlayerProfile, LeaderboardEntry, TokenPurchaseConfig.
- [ ] **System calls:** Implement init_game (start_run), end_run, submit_leaderboard, claim_coins, spend_coins, purchase_cosmetic, buy_coins, spend_revive, purchase_mini_me_unit, purchase_mini_me_sessions with calldata as in §4. Use u256 as [low, high] where applicable.
- [ ] **Session policies (optional):** Add game system contracts to Controller session policies for gasless / pre-approved txs.
- [ ] **Block number:** Use provider for current block when computing week and claim cooldown.
- [ ] **Errors:** Map revert reasons to UI messages; validate kernel, coins, and run state before calling.
- [ ] **Refresh after tx:** After each write, refetch or subscribe to Torii so UI shows updated state.

When the deployment or manifest changes, update §2 (addresses and URLs) and your frontend config accordingly.
