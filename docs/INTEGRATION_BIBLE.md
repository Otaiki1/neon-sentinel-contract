# Neon Sentinel — Frontend Integration Bible

This guide is for frontend and integration developers: how to call the world, read state, subscribe to events, and implement the main user flows.

---

## 1. Stack Overview

| Component          | Role                                                               |
| ------------------ | ------------------------------------------------------------------ |
| **Katana**         | Local Starknet RPC (or use testnet/mainnet)                        |
| **Sozo**           | Build and migrate the Dojo world; execute system calls             |
| **Torii**          | Indexer + GraphQL API for querying world state and events          |
| **World contract** | Dojo world; systems are separate contracts registered in the world |

The frontend typically:

1. **Reads state** — Via Torii GraphQL (recommended) or direct RPC calls to the world.
2. **Writes (transactions)** — Invoke system contracts through the world (Dojo’s `execute` flow) or via your Starknet SDK (starknet.js, etc.) by calling the system’s entrypoints.

---

## 2. World and System Addresses

After `sozo migrate`, you get a **world address**. System contracts are registered under that world.

- Get the world address from the migrate output or from your deployment config.
- Resolve system contract addresses via the world’s DNS/registry (e.g. `world.get_contract_address("neon_sentinel", "init_game")` or your SDK’s equivalent). In Sozo, system names are like `neon_sentinel-init_game`, `neon_sentinel-end_run`, etc. (BALANCED: no execute_tick or hit_registration on-chain.)

For local dev, `dojo_dev.toml` and Torii config use the same world.

---

## 3. System Calls (Entrypoints)

All calls are from the **player’s account** (caller = player address). Names below are logical; your SDK will use the contract ABI and the system’s deployed address.

### 3.1 init_game

Start a new run.

- **Contract:** `neon_sentinel-init_game`
- **Method:** `init_game(kernel, pregame_upgrades_mask, expected_cost)`
- **Parameters:**
    - `kernel`: u8 — Kernel index 0..5
    - `pregame_upgrades_mask`: u256 — Bitmask of upgrades (low/high 128-bit)
    - `expected_cost`: u32 — Must equal coin cost of the mask (e.g. popcount × 1 coin per upgrade)
- **Preconditions:** No active run; sufficient coins if `expected_cost > 0`
- **Effect:** Creates Player and RunState; deducts coins; emits game_start and (if cost > 0) coin-spend event

### 3.2 end_run (BALANCED)

Finish the current run with **client-submitted** final state. Client simulates gameplay locally; chain accepts final score, total kills, and final layer.

- **Contract:** `neon_sentinel-end_run`
- **Method:** `end_run(run_id, final_score, total_kills, final_layer)`
- **Parameters:**
    - `run_id`: u256 — From current Player.run_id
    - `final_score`: u64 — Client-submitted run score
    - `total_kills`: u32 — Client-submitted enemy kill count
    - `final_layer`: u8 — Client-submitted deepest layer reached
- **Preconditions:** Caller has active run with that run_id; run not already finished
- **Effect:** Sets is_finished, final_score, enemies_defeated, final_layer; updates PlayerProfile (total_runs, lifetime_enemies_defeated, lifetime_score, best_run_score, current_layer); awards +10 coins if final_score >= 1000; player inactive; game_end event

### 3.3 submit_leaderboard

Submit a finished run to the weekly leaderboard.

- **Contract:** `neon_sentinel-submit_leaderboard`
- **Method:** `submit_leaderboard(run_id, week)`
- **Parameters:**
    - `run_id`: u256
    - `week`: u32 — Must equal current week: `floor(block_number / 50400)`
- **Preconditions:** Run finished; not already submitted; week matches current block-based week
- **Effect:** Creates LeaderboardEntry (immutable); sets submitted_to_leaderboard

### 3.4 claim_coins

Daily coin claim.

- **Contract:** `neon_sentinel-claim_coins`
- **Method:** `claim_coins()`
- **Parameters:** None (caller = player)
- **Preconditions:** At least 7200 blocks since last claim (or first claim)
- **Effect:** +3 coins; updates last_coin_claim_block and coin history; emits CoinClaimed

### 3.5 spend_coins

Spend coins (generic; init_game does its own spend for upgrades).

- **Contract:** `neon_sentinel-spend_coins`
- **Method:** `spend_coins(amount, reason) -> bool`
- **Parameters:** `amount`: u32, `reason`: felt252 (e.g. string)
- **Preconditions:** amount > 0; sufficient balance
- **Effect:** Deducts coins; updates history; emits CoinSpent; returns true

### 3.8 buy_coins (STRK → in-game coins)

Purchase in-game coins with STRK. The coin shop must be initialized (owner calls `initialize_coin_shop`) and the user must approve STRK to the buy_coins contract first.

- **Contract:** `neon_sentinel-buy_coins`
- **Method:** `buy_coins(amount_strk, max_coins_expected) -> u256` (returns coins received)
- **Parameters:**
    - `amount_strk`: u256 — STRK amount (max 1000 per tx)
    - `max_coins_expected`: u256 — Must equal `amount_strk * exchange_rate` (slippage check); rate is set at init (e.g. 5 coins per STRK)
- **Preconditions:** Coin shop initialized; not paused; user has approved STRK; sufficient STRK balance; `max_coins_expected == amount_strk * rate`
- **Effect:** Transfers STRK from caller to contract; adds coins to PlayerProfile; updates coin log hash/count; writes CoinPurchaseRecord, CoinPurchaseHistory; emits CoinsPurchased

**Owner-only (same contract):** `withdraw_strk(amount_strk, notes)`, `request_withdrawal(amount_strk, notes)`, `execute_withdrawal(withdrawal_id)`, `get_treasury_balance()`, `get_treasury_info()`. Other contracts: `neon_sentinel-initialize_coin_shop` (one-time), `neon_sentinel-update_exchange_rate`, `neon_sentinel-pause_unpause_purchasing` (owner only).

---

## 4. Entities (Models) for Reading State

Use Torii GraphQL to query these. Entity names and keys follow Dojo conventions (e.g. `neon_sentinel::models::Player` or the names exposed by your Torii schema).

### 4.1 Player

- **Key:** `player_address`
- **Use:** Current run state (position, lives, run_id, is_active, tick_counter, meters). One row per player; if is_active, this is the active run.

### 4.2 RunState

- **Keys:** `player_address`, `run_id`
- **Use:** Score, layer, combo, ticks, is_finished, final_score, submitted_to_leaderboard. Query by (player, run_id).

### 4.3 Enemy

- **Key:** `enemy_id`
- **Use:** Position, health, is_active, run_id, player_address. Filter by run_id or player for “my run’s enemies”.

### 4.4 GameTick

- **Keys:** `player_address`, `run_id`, `tick_number`
- **Use:** Replay, verification; optional for UI (e.g. “tick N” debug).

### 4.5 GameEvent

- **Key:** `event_id`
- **Use:** Feed of hits, powerups, layer advances, game_start, game_end. Filter by run_id or player_address and optionally event_type (1=hit, 2=powerup, 3=layer, 6=game_start, 7=game_end).

### 4.6 LeaderboardEntry

- **Key:** `entry_id`
- **Use:** Leaderboard list. entry_id is deterministic (e.g. run_id + week). Filter by week or player_address.

### 4.7 PlayerProfile

- **Key:** `player_address`
- **Use:** Coins, last_coin_claim_block (for “next claim in X blocks”), stats, unlocks.

---

### 4.8 Coin Shop Entities

- **CoinShopGlobal** — Singleton (key 0). Use: purchasing_paused, total_strk_collected, total_strk_withdrawn (for treasury info).
- **TokenPurchaseConfig** — Key: owner. Use: strk_token_address, coin_exchange_rate (for UI: "X coins per STRK").
- **CoinPurchaseRecord** — Key: purchase_id. Use: per-purchase history (player, strk_amount, coins_minted, block).
- **CoinPurchaseHistory** — Key: player_address. Use: purchase_count, last_purchase_block per player.
- **WithdrawalRequest** — Key: withdrawal_id. Use: owner withdrawals (amount, status, blocks).

---

## 5. Events (Dojo / Starknet)

Systems emit events for indexing and UI:

- **CoinClaimed** — player, amount (3), block_number (claim_coins)
- **CoinSpent** — player, amount, reason, block_number (init_game pregame spend, spend_coins)
- **CoinsPurchased** — player, strk_amount, coins_minted, purchase_id, block_number (buy_coins)
- **StrkWithdrawn**, **WithdrawalRequestCreated**, **WithdrawalExecuted** — coin shop owner actions
- **CoinShopInitialized**, **PurchasingPauseToggled**, **ExchangeRateUpdated** — shop config
- **Moved** — player, direction (starter actions)
- **GameEvent** — Written as a model (event_id, run_id, event_type, …); subscribe via Torii to model updates or to event_type.

Use Torii subscriptions or event filters to update the UI when a run advances, a hit is registered, or coins change.

---

## 6. Torii and GraphQL

- **Endpoint:** After `torii --world <WORLD_ADDRESS> ...`, Torii exposes HTTP and (if enabled) WebSocket. Default port and routes are in [Torii docs](https://book.dojoengine.org/toolchain/torii/overview).
- **GraphQL:** Use the generated schema to query entities by keys or filters. Example patterns:
    - Player by address: `Player { player_address, run_id, is_active, x, y, lives, ... }` where `player_address = "0x..."`
    - RunState by player and run_id
    - LeaderboardEntry by week or by player_address
    - GameEvent by run_id or player_address
- **Historical / SQL:** Torii can expose SQL for historical data (see `torii_dev.toml`); use for analytics or history views.

---

## 7. Recommended Frontend Flows

### 7.1 Load player state

1. Query **PlayerProfile** by player address (coins, last_coin_claim_block).
2. Query **Player** by player address. If `is_active`, you have an active run: use `run_id`, position, lives, etc.
3. If active, query **RunState** by (player_address, run_id) for score, layer, combo, is_finished.

### 7.2 Get more coins (claim or buy)

- **Claim:** If 24h passed (last_coin_claim_block + 7200 ≤ current block), call **claim_coins**().
- **Buy with STRK:** If coin shop is initialized and not paused: approve STRK to the buy_coins contract, then call **buy_coins**(amount_strk, amount_strk * rate). Rate is from TokenPurchaseConfig (e.g. 5). Max 1000 STRK per tx.

### 7.3 Start a run

1. Ensure no active run (Player.is_active == false).
2. Optionally **claim_coins** or **buy_coins** if the player needs more coins.
3. Compute upgrade cost (e.g. popcount of upgrade mask × 1); ensure profile.coins >= cost.
4. Call **init_game**(kernel, pregame_upgrades_mask, expected_cost).
5. Refresh Player and RunState; show run UI.

### 7.4 Gameplay (client-side, BALANCED)

1. Simulate the run locally: movement, collisions, hits, score, kills, layer.
2. When the run ends (player quits or game over), compute final_score, total_kills, final_layer from your simulation.

### 7.5 End run and submit to leaderboard

1. Call **end_run**(run_id, final_score, total_kills, final_layer) with the client-computed values. Refresh Player (is_active false), RunState (is_finished, final_score, enemies_defeated, final_layer), and PlayerProfile (total_runs, lifetime stats, bonus coins if score >= 1000).
2. Compute current week: `week = floor(block_number / 50400)`.
3. Call **submit_leaderboard**(run_id, week). Refresh RunState (submitted_to_leaderboard) and LeaderboardEntry list.

### 7.7 Leaderboard view

1. Query **LeaderboardEntry** filtered by week (and optionally order by final_score).
2. Display entry_id, player_address, final_score, deepest_layer, survival_blocks, verified, etc.

---

## 8. Errors and Validation

- **Invalid kernel** — kernel must be 0..5.
- **Insufficient coins** — Profile.coins < expected_cost or spend amount.
- **Active run exists** — Cannot init_game while Player.is_active.
- **Run not active** / **Run id mismatch** — end_run with wrong or inactive run.
- **Already finished** — end_run called twice for same run.
- **Already submitted** — submit_leaderboard called twice for same run.
- **Week mismatch** — submit_leaderboard week ≠ current_leaderboard_week(block).
- **Too soon to claim** — claim_coins before 7200 blocks since last claim.
- **Purchasing paused** — buy_coins when shop is paused.
- **Approve STRK first** / **Insufficient STRK balance** / **Expected coins mismatch** — buy_coins validation failures.

Map these to user-facing messages and disable/validate UI (e.g. “Wait X blocks to claim”, “Finish current run first”).

---

## 9. Numbers Quick Reference

| Concept                         | Value             |
| ------------------------------- | ----------------- |
| Coins per daily claim           | 3                 |
| Blocks per day (claim cooldown) | 7200              |
| Blocks per week (leaderboard)   | 50400             |
| Max hit distance                | 50 (squared 2500) |
| Kernel range                    | 0..5              |
| Starting lives / max lives      | 3 / 20            |
| Combo 1.0x                      | 1000 (basis)      |
| Max layer                       | 6                 |

---

## 10. Checklist for Integration

- [ ] Resolve world and system addresses (from migrate or config).
- [ ] Use Torii GraphQL (or RPC) to load Player, RunState, PlayerProfile, Enemies, LeaderboardEntry.
- [ ] Implement init_game, end_run(run_id, final_score, total_kills, final_layer), submit_leaderboard, claim_coins, buy_coins (and spend_coins if needed). Simulate gameplay client-side and call end_run with final state.
- [ ] Use block number for cooldowns and week; do not rely on client time for game rules.
- [ ] Handle revert reasons and show clear errors.
- [ ] Subscribe to events or poll state after transactions for a responsive UI.
- [ ] For leaderboard, query by week and sort by final_score; show verified/replay_verifiable if desired.

This integration bible should be updated when new systems, entities, or events are added.
