# Neon Sentinel — Frontend Integration Bible

This guide is for frontend developers integrating the Neon Sentinel **Dojo contracts** with the game client using **Cartridge** (Controller wallet, RPC, Torii). It is the single reference for: Cartridge + React setup, contract addresses from `manifest_sepolia.json`, system entrypoints and calldata, reading state via Torii GraphQL, and end-to-end flows. Keep addresses and URLs in sync with the deployed world and manifest.

---

## 1. Stack Overview

| Component | Role |
| --------- | ----- |
| **Cartridge Controller** | Smart contract wallet (passkeys, session keys, Paymaster). Users connect via `ControllerConnector` in React. |
| **Cartridge RPC** | Starknet RPC for Sepolia; used by the app and Controller to send transactions. |
| **Torii (Slot/Cartridge)** | Indexer + GraphQL API for querying world state (Player, RunState, PlayerProfile, LeaderboardEntry, RankNFT, etc.). **Use Dojo v1.7.0** for production stability on Sepolia. |
| **World contract** | Dojo world on Starknet; **systems are separate contracts**. You invoke each system by its **contract address** and **entrypoint** with calldata. |

**Integration flow:**

1. **Read state** — Torii GraphQL (queries and subscriptions) for entities and events.
2. **Writes (transactions)** — Starknet provider (via Cartridge RPC) + player’s account (Controller); call system contracts by **contract address** and **entrypoint** with calldata.

### 1.1 Two integration approaches

| Approach | Use when | Main pieces |
|----------|----------|-------------|
| **Raw Starknet + Torii** | You want full control over calls and GraphQL. | `@starknet-react/core`, `@cartridge/connector`, `@cartridge/controller`, `account.execute()`, Torii GraphQL client. |
| **Dojo SDK (optional)** | You want typed bindings and React hooks for entities. | `@dojoengine/core`, `@dojoengine/sdk`, `@dojoengine/torii-client`, manifest → `createDojoConfig`, `sozo build --typescript` for bindings. Controller still via starknet-react. |

This bible documents the **raw approach** in detail (addresses, calldata, GraphQL). If you use the Dojo SDK, set `worldAddress` and `toriiUrl` from §2.1, load system addresses from the manifest (see §2.2), and use the same calldata and entity shapes described here.

---

## 2. Live Sepolia Deployment

All values below come from **`manifest_sepolia.json`** in this repo. Use them for production Sepolia integration.

### 2.1 Network and World

| Item | Value |
|------|--------|
| **Chain** | Starknet Sepolia |
| **Chain ID** | `SN_SEPOLIA` (e.g. `0x534e5f5345504f4c4941` or your SDK’s constant) |
| **World address** | `0x07bcbeb6104a77c6c90d7285ba06c2623454a38b501554c0d1645013fe610fc1` |
| **RPC URL (Cartridge)** | `https://api.cartridge.gg/x/starknet/sepolia` |
| **Torii base URL** | `https://api.cartridge.gg/x/neon-sentinel-test/torii` |
| **GraphQL endpoint** | `https://api.cartridge.gg/x/neon-sentinel-test/torii/graphql` |

**Note:** Torii is deployed via Slot (`v1.7.0` is recommended/used for stability). To stream indexer logs: `slot deployments logs neon-sentinel-test torii -f`. After a fresh deploy, recreate Torii if needed (delete first: `slot deployments delete neon-sentinel-test torii`).

### 2.2 System Contract Addresses (manifest_sepolia.json)

Use these **contract addresses** when calling system entrypoints (e.g. with `account.execute()` or your SDK’s equivalent). Below are the current values from **manifest_sepolia.json** (world seed `neon_sentinel_sepolia_bal_v3`).

| Tag | Contract address |
|-----|-------------------|
| `neon_sentinel-actions` | `0x11501c9707e5d8e11be1ea2382593aca835680687a589b56a8b737aea62e11d` |
| `neon_sentinel-init_game` | `0x7bfc2d91139c0cf95a9b9aeb45be1be5b7da241c2018751b8a4b1b6b4f75a12` |
| `neon_sentinel-end_run` | `0x75e9efe4e27dcfd10c92d30971b6fddc67ee5778a6af6917bf0f7f3f864d601` |
| `neon_sentinel-submit_leaderboard` | `0x7511c7a0575ad7533a1f93c46039ac1956a538223828b49928a3da567d81dc1` |
| `neon_sentinel-claim_coins` | `0x2210b7fe00d1366551f5cb70b0c8a5605a631a08f3a152838be22b288769afa` |
| `neon_sentinel-spend_coins` | `0x393939f3fb43e93c2f3af3a0c7a0c0a1d76677d6c66afd8437afe246870f05f` |
| `neon_sentinel-spend_revive` | `0xf9043a3cdd3ceb402fe33b459efe0566008a5680ef2e96fa74414b8063556b` |
| `neon_sentinel-purchase_cosmetic` | `0x1eea8a9d7fce403f9ecf491e0cc0682b6b3617f23edb98f746bf996e43b0949` |
| `neon_sentinel-buy_coins` | `0x23fcb5bfa687c332a012898cb916559e54b4e56e83ccfd3c7f5aa1d83614b25` |
| `neon_sentinel-initialize_coin_shop` | `0x277f33969e42034733631eff574b58e6c30937436b143eaf9b5f0c6539e593e` |
| `neon_sentinel-update_exchange_rate` | `0x7d447b7cfd026b8f52f42197d9c0f6a1de286c05d10f423a36ab82e9f6c679` |
| `neon_sentinel-pause_unpause_purchasing` | `0x67b851cb77204d51d819d90a305f0de074cb0842dd23e6c9faa95484c69de8` |
| `neon_sentinel-purchase_mini_me_unit` | `0x23f7c4b3be610071961e3b78e49d79bab439e36952fad9ef3eda72ff4254ded` |
| `neon_sentinel-purchase_mini_me_sessions` | `0x6d51b77216ea946c0d33cba1667fe7b23130c12387c01429324a79bc1aee8c0` |

**Source of truth:** `manifest_sepolia.json` in this repo. After a redeploy, run `sozo -P sepolia build` and refresh addresses. You can load them in the frontend by parsing the manifest:

```ts
// Load from public/manifest_sepolia.json or fetch from your app config
import manifest from "./manifest_sepolia.json";

const systemAddress = (tag: string) =>
  manifest.contracts.find((c: { tag: string }) => c.tag === tag)?.address;

const INIT_GAME = systemAddress("neon_sentinel-init_game");
const END_RUN = systemAddress("neon_sentinel-end_run");
// ... etc
```

### 2.3 Frontend config summary

| Config key | Value |
|------------|--------|
| Chain ID | `SN_SEPOLIA` |
| World address | §2.1 table |
| Torii GraphQL | `https://api.cartridge.gg/x/neon-sentinel-test/torii/graphql` |
| RPC URL | `https://api.cartridge.gg/x/starknet/sepolia` |
| System addresses | §2.2 or load from `manifest_sepolia.json` (contracts with tag `neon_sentinel-*`) |

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

### 3.5 Optional: Session policies (gasless / pre-approved txs)

To allow gasless or session-based calls to game systems, define **SessionPolicies** and pass them into `ControllerConnector`. Use the system contract addresses from §2.2 (or load from manifest). Each contract entry lists the entrypoints that the session is allowed to call.

```ts
import { SessionPolicies } from "@cartridge/controller";

// Use addresses from §2.2 or from manifest_sepolia.json
const INIT_GAME = "0x7bfc2d91139c0cf95a9b9aeb45be1be5b7da241c2018751b8a4b1b6b4f75a12";
const END_RUN = "0x75e9efe4e27dcfd10c92d30971b6fddc67ee5778a6af6917bf0f7f3f864d601";
const SUBMIT_LEADERBOARD = "0x7511c7a0575ad7533a1f93c46039ac1956a538223828b49928a3da567d81dc1";
const CLAIM_COINS = "0x2210b7fe00d1366551f5cb70b0c8a5605a631a08f3a152838be22b288769afa";
const SPEND_COINS = "0x393939f3fb43e93c2f3af3a0c7a0c0a1d76677d6c66afd8437afe246870f05f";
const SPEND_REVIVE = "0xf9043a3cdd3ceb402fe33b459efe0566008a5680ef2e96fa74414b8063556b";
const PURCHASE_COSMETIC = "0x1eea8a9d7fce403f9ecf491e0cc0682b6b3617f23edb98f746bf996e43b0949";
const BUY_COINS = "0x23fcb5bfa687c332a012898cb916559e54b4e56e83ccfd3c7f5aa1d83614b25";
const PURCHASE_MINI_ME_UNIT = "0x23f7c4b3be610071961e3b78e49d79bab439e36952fad9ef3eda72ff4254ded";
const PURCHASE_MINI_ME_SESSIONS = "0x6d51b77216ea946c0d33cba1667fe7b23130c12387c01429324a79bc1aee8c0";

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
    [SUBMIT_LEADERBOARD]: {
      name: "Neon Sentinel – Submit Leaderboard",
      description: "Submit run to weekly leaderboard",
      methods: [{ name: "submit_leaderboard", entrypoint: "submit_leaderboard" }],
    },
    [CLAIM_COINS]: {
      name: "Neon Sentinel – Claim Coins",
      description: "Daily coin claim",
      methods: [{ name: "claim_coins", entrypoint: "claim_coins" }],
    },
    [SPEND_COINS]: {
      name: "Neon Sentinel – Spend Coins",
      description: "Spend in-game coins",
      methods: [{ name: "spend_coins", entrypoint: "spend_coins" }],
    },
    [SPEND_REVIVE]: {
      name: "Neon Sentinel – Revive",
      description: "In-run revive (cost scales)",
      methods: [{ name: "spend_revive", entrypoint: "spend_revive" }],
    },
    [PURCHASE_COSMETIC]: {
      name: "Neon Sentinel – Purchase Cosmetic",
      description: "Unlock kernel, avatar, or skin",
      methods: [{ name: "purchase_cosmetic", entrypoint: "purchase_cosmetic" }],
    },
    [BUY_COINS]: {
      name: "Neon Sentinel – Buy Coins",
      description: "Purchase in-game coins with STRK",
      methods: [{ name: "buy_coins", entrypoint: "buy_coins" }],
    },
    [PURCHASE_MINI_ME_UNIT]: {
      name: "Neon Sentinel – Purchase Mini-Me Unit",
      description: "Add unit to Mini-Me inventory",
      methods: [{ name: "purchase_mini_me_unit", entrypoint: "purchase_mini_me_unit" }],
    },
    [PURCHASE_MINI_ME_SESSIONS]: {
      name: "Neon Sentinel – Purchase Mini-Me Sessions",
      description: "Add +3 sessions pack",
      methods: [{ name: "purchase_mini_me_sessions", entrypoint: "purchase_mini_me_sessions" }],
    },
  },
};

const connector = new ControllerConnector({ policies: gamePolicies });
```

### 3.6 Dojo SDK (optional)

If you use the **Dojo SDK** for typed entities and hooks (e.g. `useEntityQuery`), keep Cartridge Controller for account/session and wire the SDK to the same world and Torii:

1. **Config:** `createDojoConfig({ manifest })` with `manifest_sepolia.json`; use `worldAddress` and `toriiUrl` from §2.1 (Torii base: `https://api.cartridge.gg/x/neon-sentinel-test/torii`).
2. **Bindings:** Run `sozo -P sepolia build --typescript` (or `DOJO_MANIFEST_PATH=... sozo build --typescript`) and use the generated types for entities and system addresses.
3. **Controller:** Keep using `ControllerConnector` and starknet-react for wallet/session; use the SDK only for **reads** (Torii queries/subscriptions) and optional typed wrappers; **writes** still go through `account.execute()` with addresses and calldata from §4.

---

## 4. System Calls (Entrypoints and Calldata)

All calls are from the **player’s account** (Controller). Use `account.execute([...])` (e.g. from `useAccount()`). Calldata follows Starknet ABI: **u256** = two felts `[low, high]`, **felt252** = short string (e.g. `starknetShortString()` or numeric encoding).

### 4.1 Address constants (from manifest)

Use the addresses from §2.2 or load from `manifest_sepolia.json`. Example constant object (update after redeploys):

```ts
export const NEON_SENTINEL = {
  WORLD: "0x07bcbeb6104a77c6c90d7285ba06c2623454a38b501554c0d1645013fe610fc1",
  INIT_GAME: "0x7bfc2d91139c0cf95a9b9aeb45be1be5b7da241c2018751b8a4b1b6b4f75a12",
  END_RUN: "0x75e9efe4e27dcfd10c92d30971b6fddc67ee5778a6af6917bf0f7f3f864d601",
  SUBMIT_LEADERBOARD: "0x7511c7a0575ad7533a1f93c46039ac1956a538223828b49928a3da567d81dc1",
  CLAIM_COINS: "0x2210b7fe00d1366551f5cb70b0c8a5605a631a08f3a152838be22b288769afa",
  SPEND_COINS: "0x393939f3fb43e93c2f3af3a0c7a0c0a1d76677d6c66afd8437afe246870f05f",
  SPEND_REVIVE: "0xf9043a3cdd3ceb402fe33b459efe0566008a5680ef2e96fa74414b8063556b",
  PURCHASE_COSMETIC: "0x1eea8a9d7fce403f9ecf491e0cc0682b6b3617f23edb98f746bf996e43b0949",
  BUY_COINS: "0x23fcb5bfa687c332a012898cb916559e54b4e56e83ccfd3c7f5aa1d83614b25",
  PURCHASE_MINI_ME_UNIT: "0x23f7c4b3be610071961e3b78e49d79bab439e36952fad9ef3eda72ff4254ded",
  PURCHASE_MINI_ME_SESSIONS: "0x6d51b77216ea946c0d33cba1667fe7b23130c12387c01429324a79bc1aee8c0",
} as const;
```

**Calldata encoding:** u256 = two felts `[low, high]`. felt252 for short strings: use your SDK’s `encodeShortString()` or equivalent. All system calls are from the **player’s account** (Controller); use `account.execute({ contractAddress, entrypoint, calldata })` from `useAccount()`.

### 4.2 init_game (start run)

- **Contract address:** `NEON_SENTINEL.INIT_GAME`
- **Entrypoint:** `init_game`
- **Calldata:** `[kernel: u8, pregame_upgrades_mask_low: u128, pregame_upgrades_mask_high: u128, expected_cost: u32]`
  - **kernel:** 0..10. Kernel 0 is free and always allowed; kernels 1..10 must be unlocked via **purchase_cosmetic** and require `PlayerProfile.current_prestige` ≥ prestige for that kernel; kernel 10 also requires `is_prime_sentinel`.
  - **pregame_upgrades_mask:** u256 as two felts (low, high). Bits 0..6 = pregame upgrades (Extra Heart, Double Heart, Reinforced Core, Overcharged Gun, Rapid Fire, Extended Boost, Agility Pack). Set bit = purchase that upgrade for this run.
  - **expected_cost:** Must equal the sum of pregame prices for each set bit. Prices: 25, 50, 40, 45, 40, 35, 30 (bits 0..6). Contract asserts `expected_cost` matches; compute on the client and pass it.
- **run_id:** The contract generates a deterministic **run_id** from block + timestamp + caller. Read **Player.run_id** (and **RunState**) from Torii after the tx; pass this run_id to **end_run** and **submit_leaderboard**. Calling **init_game** again without ending the previous run abandons it (new run_id).

```ts
// Pregame cost: sum of PRICE_PREGAME[bit] for each set bit (25,50,40,45,40,35,30)
function computePregameCost(maskLow: bigint, maskHigh: bigint): number {
  const prices = [25, 50, 40, 45, 40, 35, 30];
  let cost = 0;
  for (let i = 0; i < 7; i++) {
    const bit = (maskLow >> BigInt(i)) & 1n; // if mask is small, only low matters
    if (bit) cost += prices[i];
  }
  return cost;
}

// Example: kernel 0, no upgrades, cost 0
await account.execute({
  contractAddress: NEON_SENTINEL.INIT_GAME,
  entrypoint: "init_game",
  calldata: [0, "0x0", "0x0", 0],
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
  - **Week (timestamp-based):** `week = floor(blockTimestamp / 604800)` (604800 = 7 days in seconds). Get the current block’s **timestamp** from RPC, then compute week. Contract asserts the passed week matches the block’s week.

```ts
const SECONDS_PER_WEEK = 604800;

async function getLeaderboardWeek(provider: any): Promise<number> {
  const block = await provider.getBlock("latest");
  const timestamp = block.timestamp; // Unix seconds
  return Math.floor(Number(timestamp) / SECONDS_PER_WEEK);
}

// When submitting:
const week = await getLeaderboardWeek(provider);
await account.execute({
  contractAddress: NEON_SENTINEL.SUBMIT_LEADERBOARD,
  entrypoint: "submit_leaderboard",
  calldata: [runId.low, runId.high, week],
});
```

### 4.5 claim_coins

- **Contract address:** `NEON_SENTINEL.CLAIM_COINS`
- **Entrypoint:** `claim_coins`
- **Calldata:** none
- **Cooldown:** 7200 blocks between claims. Contract reverts if `block_number - last_coin_claim_block < 7200` (first claim has no cooldown).

**Helper: blocks until next claim**

```ts
const COIN_CLAIM_COOLDOWN_BLOCKS = 7200;

function blocksUntilNextClaim(lastClaimBlock: number, currentBlock: number): number {
  if (lastClaimBlock === 0) return 0;
  const elapsed = currentBlock - lastClaimBlock;
  if (elapsed >= COIN_CLAIM_COOLDOWN_BLOCKS) return 0;
  return COIN_CLAIM_COOLDOWN_BLOCKS - elapsed;
}

// Usage: get last_coin_claim_block from PlayerProfile (Torii), then:
// const current = await provider.getBlock("latest"); const blocksLeft = blocksUntilNextClaim(profile.last_coin_claim_block, current.block_number);
```

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

- **URL:** `https://api.cartridge.gg/x/neon-sentinel-test/torii/graphql`

Torii exposes a schema for Dojo entities (models). Model names in the schema are typically **namespace-prefixed** (e.g. `neon_sentinel-Player`, `neon_sentinel-PlayerProfile`). Keys and fields may appear as snake_case (e.g. `player_address`, `run_id_low`, `run_id_high`) or camelCase depending on the Torii version. Use **introspection** (e.g. GraphQL `__schema` query) or the Torii schema API to get exact field and filter names for your deployment.

### 5.1 Example: PlayerProfile by address

**Displayed rank:** Use `highest_rank_id` (0 = none, 1..18 = highest rank achieved). The frontend maps rank_id to rank name and tier via the same 18-rank catalog (e.g. RANK_CONFIG); tier 1 = entry, 2 = intermediate, 3 = advanced, 4 = elite, 5 = legendary.

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
    highest_rank_id
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

On-chain leaderboard week is **timestamp-based**: `current_week = floor(block_timestamp / 604800)`. Torii still filters by `week`; use the same formula when querying for the "current" week (get latest block's timestamp from RPC, then `week = Math.floor(timestamp / 604800)`).

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

**Leaderboard ranking** (general game state): query **LeaderboardEntry** by week (timestamp-based index: `week = floor(block_timestamp / 604800)`), order by `final_score` desc (see §5.3). **User metrics**: query **PlayerProfile** by `player_address` for lifetime_score, best_run_score, current_layer, etc.

### 5.5 Rank NFTs and badges

Rank NFTs are minted in **end_run** when the player reaches one of the **18 named rank milestones** (prestige, layer). Each player has at most one NFT per rank (rank_id 1..18).

- **Displayed rank:** Query **PlayerProfile.highest_rank_id** (1..18). Map to rank name and tier (1=entry, 2=intermediate, 3=advanced, 4=elite, 5=legendary) using the same catalog as the chain (e.g. RANK_CONFIG).
- **Rank history / badges:** Query **RankNFT** by `owner`. Key is composite `(owner, rank_id)`; each row is one minted rank badge. Example: `rankNFTs(where: { owner: $owner }) { rank_id, rank_tier, prestige, layer, achieved_at_block, run_id_low, run_id_high }`. Use `rank_id` to pick badge assets (e.g. badge_1 … badge_18).

### 5.6 Subscriptions

Use GraphQL subscriptions on the same endpoint to react to entity updates (e.g. after `end_run` or `claim_coins`) without polling.

---

## 6. Entities (Models) Quick Reference

| Entity | Key(s) | Use |
|--------|--------|-----|
| **Player** | player_address | Active run: run_id, is_active, lives, position, kernel. |
| **RunState** | player_address, run_id | Score, layer, is_finished, final_score, enemies_defeated, final_layer, submitted_to_leaderboard, revive_count, current_prestige, pregame_upgrades_mask. |
| **PlayerProfile** | player_address | Coins, last_coin_claim_block, current_prestige, is_prime_sentinel, total_runs, lifetime_score, best_run_score, current_layer, **highest_rank_id** (0 or 1..18), kernel_unlocks, selected_kernel, last_prime_sentinel_claim_block, mini_me_sessions_purchased, etc. |
| **MiniMeInventory** | player_address, unit_type | count (0..20 per type). |
| **LeaderboardEntry** | entry_id | Leaderboard rows; filter by week, sort by final_score. |
| **GameEvent** | event_id | game_start (6), game_end (7); filter by run_id / player_address. |
| **TokenPurchaseConfig** | owner | coin_exchange_rate, strk_token_address (for buy_coins UI). Rate can be set later via update_exchange_rate. |
| **CoinShopGlobal** | global_key (0) | Shop owner; paused state may be on TokenPurchaseConfig. |
| **RankNFT** | owner, rank_id | One NFT per player per rank (rank_id 1..18). Fields: rank_id, rank_tier (1..5), prestige, layer, achieved_at_block, run_id, token_id (optional). Query by owner for badge_1..badge_18. |

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
2. After confirmation, get the current block's **timestamp** from RPC, compute `week = Math.floor(blockTimestamp / 604800)`, and call **submit_leaderboard**(run_id, week).
3. Refresh Player, RunState, PlayerProfile, and leaderboard from Torii.

### 7.6 Leaderboard view

Query **LeaderboardEntry** by week, order by final_score; display in your Hall of Fame UI.

#### Leaderboard and week sync (contract vs frontend)

- **Chain week:** `week = floor(block_timestamp / 604800)` (Unix seconds; 604800 = 7 days). One on-chain board per week index. Each period is exactly 7 real days regardless of block production.
- **Submission:** Get the latest block's `timestamp` from RPC → compute `week = Math.floor(blockTimestamp / 604800)` → call `submit_leaderboard(run_id, week)`.
- **Local vs on-chain:** The frontend can keep ISO week for local display and featured categories; the on-chain leaderboard is keyed by this timestamp-based week index. When showing "current chain leaderboard", use the same week formula for the query.

---

## 8. Errors and Validation

Map contract reverts to user-facing messages:

| Revert / condition | Message / handling |
|--------------------|--------------------|
| Invalid kernel | "Kernel must be 0–10." |
| Kernel not unlocked | "Purchase this kernel with coins first (purchase_cosmetic)." |
| Insufficient coins | "Not enough coins." |
| Run not active / Run id mismatch | "No active run or wrong run. Use current Player.run_id." |
| Already finished | "Run already ended." |
| Already submitted | "Already submitted to leaderboard." |
| Week mismatch | "Submit in the correct leaderboard week." |
| Too soon to claim | "Next claim in X blocks." |
| Purchasing paused | "Coin shop is paused." |
| STRK / approval / amount | "Check STRK approval and amount; shop may be paused." |

Use block number for claim cooldowns; use **block timestamp** for leaderboard week (see §4.4). Do not rely on client time for game rules.

---

## 9. Numbers Quick Reference

| Concept | Value |
|--------|--------|
| Coins per daily claim | 3 |
| Blocks per day (claim cooldown) | 7200 |
| Seconds per week (leaderboard) | 604800 |
| Kernel range | 0..10 |
| Pregame upgrades (bits 0..6) | 7; prices 25, 50, 40, 45, 40, 35, 30 |
| Starting lives / max lives | 3 / 20 |
| Combo 1.0x (basis) | 1000 |
| Max layer | 6 |
| Bonus coins when final_score ≥ 1000 | 10 |

---

## 10. Integration Checklist

- [ ] **Cartridge + React:** Install `@cartridge/connector`, `@cartridge/controller`, `@starknet-react/core`, `@starknet-react/chains`, `starknet`. Create connector and `StarknetConfig` with Cartridge Sepolia RPC and ControllerConnector.
- [ ] **Chain:** Use Starknet Sepolia; default chain = Sepolia in StarknetConfig.
- [ ] **Addresses:** Use contract addresses from §2.2 (or import from `manifest_sepolia.json`). World address §2.1 for any world-level reads.
- [ ] **Torii:** Set GraphQL URL to `https://api.cartridge.gg/x/neon-sentinel-test/torii/graphql`. Use for Player, RunState, PlayerProfile, LeaderboardEntry, TokenPurchaseConfig.
- [ ] **System calls:** Implement init_game (start_run), end_run, submit_leaderboard, claim_coins, spend_coins, purchase_cosmetic, buy_coins, spend_revive, purchase_mini_me_unit, purchase_mini_me_sessions with calldata as in §4. Use u256 as [low, high] where applicable.
- [ ] **Session policies (optional):** Add game system contracts to Controller session policies for gasless / pre-approved txs.
- [ ] **Block timestamp / number:** Use provider: block **timestamp** for leaderboard week (`week = floor(timestamp / 604800)`); block **number** for claim cooldown.
- [ ] **Errors:** Map revert reasons to UI messages; validate kernel, coins, and run state before calling.
- [ ] **Refresh after tx:** After each write, refetch or subscribe to Torii so UI shows updated state.

When the deployment or manifest changes, update §2 (addresses and URLs) and your frontend config accordingly.
