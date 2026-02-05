# Neon Sentinel — Frontend Integration Bible

This guide is for frontend and integration developers: how to call the world, read state, subscribe to events, and implement the main user flows.

---

## 1. Stack Overview

| Component | Role |
|-----------|------|
| **Katana** | Local Starknet RPC (or use testnet/mainnet) |
| **Sozo** | Build and migrate the Dojo world; execute system calls |
| **Torii** | Indexer + GraphQL API for querying world state and events |
| **World contract** | Dojo world; systems are separate contracts registered in the world |

The frontend typically:

1. **Reads state** — Via Torii GraphQL (recommended) or direct RPC calls to the world.
2. **Writes (transactions)** — Invoke system contracts through the world (Dojo’s `execute` flow) or via your Starknet SDK (starknet.js, etc.) by calling the system’s entrypoints.

---

## 2. World and System Addresses

After `sozo migrate`, you get a **world address**. System contracts are registered under that world.

- Get the world address from the migrate output or from your deployment config.
- Resolve system contract addresses via the world’s DNS/registry (e.g. `world.get_contract_address("neon_sentinel", "init_game")` or your SDK’s equivalent). In Sozo, system names are like `neon_sentinel-init_game`, `neon_sentinel-execute_tick`, etc.

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

### 3.2 execute_tick

Process one game tick.

- **Contract:** `neon_sentinel-execute_tick`
- **Method:** `execute_tick(run_id, player_input, sig_r, sig_s, enemy_ids)`
- **Parameters:**
  - `run_id`: u256 — From current Player.run_id
  - `player_input`: u8 — Low 3 bits: direction (0=idle, 1=left, 2=right, 3=up, 4=down); high bits: action (e.g. 0=none, 1=shoot, 2=overclock, …)
  - `sig_r`, `sig_s`: u256 — Signature (placeholder for future auth)
  - `enemy_ids`: Array<u256> — Enemies to process this tick (e.g. visible/active IDs)
- **Preconditions:** Run active; run not finished; next tick sequential; block_number > last_tick_block
- **Effect:** Updates Player (position, lives, meters), RunState, Enemies; writes GameTick

### 3.3 hit_registration

Register a bullet hit on an enemy.

- **Contract:** `neon_sentinel-hit_registration`
- **Method:** `hit_registration(run_id, enemy_id, damage, player_x, player_y, hit_proof)`
- **Parameters:**
  - `run_id`: u256
  - `enemy_id`: u256
  - `damage`: u32 — Base damage (kernel/upgrades applied on-chain)
  - `player_x`, `player_y`: u32 — Must match current Player position (anti-spoof)
  - `hit_proof`: u256 — Reserved for future proof
- **Preconditions:** Run active; enemy exists, active, same run/player; distance ≤ 50; position matches
- **Effect:** Reduces enemy health; on kill: score, combo, events (hit, powerup, layer)

### 3.4 end_run

Finish the current run.

- **Contract:** `neon_sentinel-end_run`
- **Method:** `end_run(run_id)`
- **Parameters:** `run_id`: u256
- **Preconditions:** Caller has active run with that run_id; run not already finished
- **Effect:** Sets is_finished, final_score, final_layer; player inactive; game_end event

### 3.5 submit_leaderboard

Submit a finished run to the weekly leaderboard.

- **Contract:** `neon_sentinel-submit_leaderboard`
- **Method:** `submit_leaderboard(run_id, week)`
- **Parameters:**
  - `run_id`: u256
  - `week`: u32 — Must equal current week: `floor(block_number / 50400)`
- **Preconditions:** Run finished; not already submitted; week matches current block-based week
- **Effect:** Creates LeaderboardEntry (immutable); sets submitted_to_leaderboard

### 3.6 claim_coins

Daily coin claim.

- **Contract:** `neon_sentinel-claim_coins`
- **Method:** `claim_coins()`
- **Parameters:** None (caller = player)
- **Preconditions:** At least 7200 blocks since last claim (or first claim)
- **Effect:** +3 coins; updates last_coin_claim_block and coin history; emits CoinClaimed

### 3.7 spend_coins

Spend coins (generic; init_game does its own spend for upgrades).

- **Contract:** `neon_sentinel-spend_coins`
- **Method:** `spend_coins(amount, reason) -> bool`
- **Parameters:** `amount`: u32, `reason`: felt252 (e.g. string)
- **Preconditions:** amount > 0; sufficient balance
- **Effect:** Deducts coins; updates history; emits CoinSpent; returns true

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

## 5. Events (Dojo / Starknet)

Systems emit events for indexing and UI:

- **CoinClaimed** — player, amount (3), block_number (claim_coins)
- **CoinSpent** — player, amount, reason, block_number (init_game pregame spend, spend_coins)
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

### 7.2 Start a run

1. Ensure no active run (Player.is_active == false).
2. Optionally call **claim_coins** if 24h passed (check last_coin_claim_block + 7200 ≤ current block).
3. Compute upgrade cost (e.g. popcount of upgrade mask × 1); ensure profile.coins >= cost.
4. Call **init_game**(kernel, pregame_upgrades_mask, expected_cost).
5. Refresh Player and RunState; show run UI.

### 7.3 Game loop (each tick)

1. Get current block (from RPC or Torii).
2. Build `player_input` (direction + action), `enemy_ids` (enemies to process).
3. Call **execute_tick**(run_id, player_input, 0, 0, enemy_ids) (sig 0,0 for placeholder).
4. Wait for tx; then refresh Player, RunState, Enemies (and optional GameTick/GameEvent).

### 7.4 Register a hit

When your client detects a hit (within range):

1. Call **hit_registration**(run_id, enemy_id, damage, player_x, player_y, 0) with current Player (x, y).
2. Refresh RunState and Enemy; optionally subscribe to GameEvent for hit/powerup/layer.

### 7.5 End run and submit to leaderboard

1. Call **end_run**(run_id). Refresh Player (is_active false) and RunState (is_finished, final_score).
2. Compute current week: `week = floor(block_number / 50400)`.
3. Call **submit_leaderboard**(run_id, week). Refresh RunState (submitted_to_leaderboard) and LeaderboardEntry list.

### 7.6 Leaderboard view

1. Query **LeaderboardEntry** filtered by week (and optionally order by final_score).
2. Display entry_id, player_address, final_score, deepest_layer, survival_blocks, verified, etc.

---

## 8. Errors and Validation

- **Invalid kernel** — kernel must be 0..5.
- **Insufficient coins** — Profile.coins < expected_cost or spend amount.
- **Active run exists** — Cannot init_game while Player.is_active.
- **Run not active** / **Run id mismatch** — execute_tick / hit_registration / end_run with wrong or inactive run.
- **Run finished** — execute_tick or hit_registration after end_run.
- **Block must increase** — Replay: same or older block for execute_tick.
- **Tick not sequential** — execute_tick called out of order.
- **Position mismatch** — hit_registration player_x/player_y ≠ on-chain Player position.
- **Out of range** — hit_registration distance > 50.
- **Already submitted** — submit_leaderboard called twice for same run.
- **Week mismatch** — submit_leaderboard week ≠ current_leaderboard_week(block).
- **Too soon to claim** — claim_coins before 7200 blocks since last claim.

Map these to user-facing messages and disable/validate UI (e.g. “Wait X blocks to claim”, “Finish current run first”).

---

## 9. Numbers Quick Reference

| Concept | Value |
|--------|--------|
| Coins per daily claim | 3 |
| Blocks per day (claim cooldown) | 7200 |
| Blocks per week (leaderboard) | 50400 |
| Max hit distance | 50 (squared 2500) |
| Kernel range | 0..5 |
| Starting lives / max lives | 3 / 20 |
| Combo 1.0x | 1000 (basis) |
| Max layer | 6 |

---

## 10. Checklist for Integration

- [ ] Resolve world and system addresses (from migrate or config).
- [ ] Use Torii GraphQL (or RPC) to load Player, RunState, PlayerProfile, Enemies, LeaderboardEntry.
- [ ] Implement init_game, execute_tick, hit_registration, end_run, submit_leaderboard, claim_coins (and spend_coins if needed).
- [ ] Use block number for cooldowns and week; do not rely on client time for game rules.
- [ ] Handle revert reasons and show clear errors.
- [ ] Subscribe to events or poll state after transactions for a responsive UI.
- [ ] For leaderboard, query by week and sort by final_score; show verified/replay_verifiable if desired.

This integration bible should be updated when new systems, entities, or events are added.
