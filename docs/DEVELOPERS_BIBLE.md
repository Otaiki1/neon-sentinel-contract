# Neon Sentinel — Developer's Bible

This document explains the codebase: architecture, models, systems, constants, security, and testing.

---

## 1. Architecture Overview

Neon Sentinel is a **Dojo Autonomous World**. All authoritative state lives in the world; systems are contracts that read and write Dojo models under the namespace `neon_sentinel`.

- **Models** — Stored entities (Player, RunState, Enemy, GameTick, GameEvent, LeaderboardEntry, PlayerProfile, plus starter models).
- **Systems** — Starknet contracts that implement the game and economy logic. They use `world.read_model` / `world.write_model` and (where applicable) `world.emit_event`.
- **Timing** — All timing is block-based (`get_execution_info().block_info.block_number`). No client timestamps for game rules.
- **Writers** — Only the registered system contracts can write to the namespace (see `dojo_dev.toml` / `dojo_release.toml`).

---

## 2. Source Layout

```
src/
├── lib.cairo              # pub mod systems; pub mod models; pub mod tests;
├── models.cairo           # All Dojo models + shared types (Vec2, Direction)
└── systems/
    ├── actions.cairo      # Starter: spawn, move (Position, Moves)
    ├── init_game.cairo    # Start run: Player, RunState, coin deduction
    ├── execute_tick.cairo # Main loop: movement, collision, GameTick
    ├── hit_registration.cairo # Bullet hit: damage, score, combo, events
    ├── end_run.cairo      # Finalize run: is_finished, final_score/layer
    ├── submit_leaderboard.cairo # Immutable leaderboard entry
    ├── claim_coins.cairo  # Daily coin claim (24h cooldown)
    └── spend_coins.cairo  # Spend coins (e.g. upgrades); used conceptually by init_game
```

---

## 3. Models (Data Structures)

All are `#[dojo::model]` with `#[key]` fields for identity.

### 3.1 Player

- **Keys:** `player_address` (ContractAddress)
- **Meaning:** One active run per player. When a run is active, this row is the live in-run state.
- **Important fields:**
  - `run_id`, `is_active`, `x`, `y`, `lives`, `max_lives`, `kernel`
  - `invincible_until_block`, `tick_counter`, `last_tick_block` — anti-cheat / replay
  - `overclock_meter`, `shock_bomb_meter`, `god_mode_meter`, `overclock_active`, `god_mode_active`
  - `upgrades_verified` — set true at init; no mid-run upgrade changes

### 3.2 RunState

- **Keys:** `(player_address, run_id)`
- **Meaning:** Per-run aggregate state (score, layer, combo, ticks, finished flag, etc.).
- **Important fields:**
  - `current_layer`, `current_prestige`, `score`, `combo_multiplier`, `corruption_level`, `corruption_multiplier`
  - `started_at_block`, `last_tick_block`, `total_ticks_processed`
  - `enemies_defeated`, `shots_fired`, `shots_hit`, `accuracy`
  - `is_finished`, `final_score`, `final_layer`, `submitted_to_leaderboard`

Once `is_finished == true`, the run is immutable.

### 3.3 Enemy

- **Keys:** `enemy_id` (u256)
- **Meaning:** One enemy instance in a run. Position and lifecycle are server/contract-driven.
- **Important fields:** `run_id`, `player_address`, `enemy_type`, `health`, `max_health`, `x`, `y`, `is_active`, `spawn_block`, `destroyed_at_block`, `destruction_verified`

### 3.4 GameTick

- **Keys:** `(player_address, run_id, tick_number)`
- **Meaning:** One deterministic tick record for replay and verification.
- **Important fields:** `block_number`, `timestamp`, `player_input`, `input_sig`, `player_x`, `player_y`, `score_delta`, `enemies_killed`, `damage_taken`, `combo_before`/`combo_after`, `state_hash_before`/`state_hash_after`, `tick_hash`

### 3.5 GameEvent

- **Keys:** `event_id` (u256)
- **Meaning:** Immutable event log (game_start, hit, powerup, layer, game_end).
- **Event types:** 1 = hit, 2 = powerup, 3 = layer, 6 = game_start, 7 = game_end

### 3.6 LeaderboardEntry

- **Keys:** `entry_id` (u256)
- **Meaning:** One submitted run on the weekly leaderboard. Immutable.
- **Proof/verification fields:** `submission_block`, `submission_hash`, `event_log_hash`, `game_seed`, `replay_verifiable`, `verified`

### 3.7 PlayerProfile

- **Keys:** `player_address`
- **Meaning:** Persistent profile (prestige, layer, stats, coins, unlocks).
- **Coin fields:** `coins`, `last_coin_claim_block`, `coin_transaction_log_hash`, `coin_transaction_count`

### 3.8 Starter Models (Legacy)

- **Moves**, **Position**, **DirectionsAvailable**, **PositionCount** — Used by `actions` (spawn/move) and existing tests.

---

## 4. Systems (Contracts)

### 4.1 init_game

- **Interface:** `init_game(ref self, kernel: u8, pregame_upgrades_mask: u256, expected_cost: u32)`
- **Checks:** Kernel in 0..=5, upgrades mask valid, `expected_cost == compute_upgrade_cost(mask)`, profile has enough coins, no active run.
- **Creates:** Player, RunState (layer 1, score 0, combo 1000, not finished), GameEvent (game_start).
- **Updates:** Deducts `expected_cost` from profile; updates `coin_transaction_log_hash`, `coin_transaction_count`; emits CoinSpent-style event (reason: pregame_upgrades).
- **run_id:** Deterministic from `block_number`, `block_timestamp`, caller (no client input).

### 4.2 execute_tick

- **Interface:** `execute_tick(ref self, run_id: u256, player_input: u8, sig_r: u256, sig_s: u256, enemy_ids: Array<u256>)`
- **Checks:** Active run, run not finished, sequential tick (`tick_counter == total_ticks_processed`), `block_number > last_tick_block`.
- **Logic:** Direction from low 3 bits of `player_input` (0=idle, 1=left, 2=right, 3=up, 4=down); action from high bits (shoot, overclock, shock_bomb, god_mode). Updates player position, processes up to `MAX_ENEMIES_PER_TICK` enemies (position update, collision, damage), applies corruption, writes GameTick.
- **Constants:** WORLD_MAX_X/Y 1000, COLLISION_RADIUS 8, DAMAGE_PER_HIT 1, COMBO_ONE 1000, etc.

### 4.3 hit_registration

- **Interface:** `hit_registration(ref self, run_id: u256, enemy_id: u256, damage: u32, player_x: u32, player_y: u32, hit_proof: u256)`
- **Checks:** Run active and not finished; enemy exists, same run, same player, active; `player.x == player_x` and `player.y == player_y` (anti-spoof); distance squared ≤ MAX_HIT_RANGE_SQ (2500).
- **Logic:** Applies kernel/upgrade damage, reduces enemy health; on kill: score, combo step, GameEvent (hit, optional powerup, optional layer advance). Layer thresholds: 1000, 5000, 15000, 40000, 100000 for layers 2..6.

### 4.4 end_run

- **Interface:** `end_run(ref self, run_id: u256)`
- **Checks:** Caller has active run with that run_id; run not already finished.
- **Logic:** Sets `is_finished = true`, `last_tick_block = block_number`, `final_score = score`, `final_layer = current_layer`, `submitted_to_leaderboard = false`; marks player inactive; emits GameEvent (game_end).

### 4.5 submit_leaderboard

- **Interface:** `submit_leaderboard(ref self, run_id: u256, week: u32)`
- **Checks:** Run finished; not already submitted; `week == current_leaderboard_week(block_number)` (week = block / 50400); if `total_ticks_processed > 0`, last GameTick must exist (replay chain).
- **Logic:** Builds LeaderboardEntry (all proof fields, `verified = true`, `replay_verifiable` as per chain); writes entry; sets `submitted_to_leaderboard = true`.

### 4.6 claim_coins

- **Interface:** `claim_coins(ref self)`
- **Checks:** At least 7200 blocks since `last_coin_claim_block` (or first claim when it is 0).
- **Logic:** Adds 3 coins, updates `last_coin_claim_block`, appends to `coin_transaction_log_hash`, increments `coin_transaction_count`, emits CoinClaimed.

### 4.7 spend_coins

- **Interface:** `spend_coins(ref self, amount: u32, reason: felt252) -> bool`
- **Checks:** `amount > 0`, profile has enough coins.
- **Logic:** Deducts amount, updates log hash and count, emits CoinSpent, returns true. Used conceptually for any spend (init_game does its own deduction + same accounting for pregame upgrades).

### 4.8 actions (Starter)

- **Interface:** `spawn(ref self)`, `move(ref self, direction: Direction)`
- **Purpose:** Demo move/spawn on Position and Moves; kept for compatibility.

---

## 5. Key Constants

| Constant | Value | Where | Meaning |
|----------|--------|------|---------|
| MAX_KERNEL | 5 | init_game | Kernel index 0..5 |
| COIN_PER_UPGRADE | 1 | init_game | Coins per upgrade bit |
| START_X, START_Y | 0, 0 | init_game | Initial position |
| START_LIVES, MAX_LIVES | 3, 20 | init_game | Lives |
| COMBO_ONE | 1000 | init_game, execute_tick, hit_registration | 1.0x combo (basis points style) |
| BLOCKS_PER_DAY | 7200 | claim_coins | 24h cooldown for claim |
| COINS_PER_CLAIM | 3 | claim_coins | Coins per daily claim |
| BLOCKS_PER_WEEK | 50400 | submit_leaderboard | Week = block / 50400 |
| MAX_HIT_RANGE_SQ | 2500 | hit_registration | Hit allowed if distance_sq ≤ 2500 |
| COMBO_STEP, COMBO_MAX | 50, 5000 | hit_registration | Combo step and cap |
| MAX_LAYER | 6 | hit_registration | Layers 1..6 |
| EVENT_TYPE_* | 1,2,3,6,7 | hit_registration, end_run, init_game | Hit, powerup, layer, game_start, game_end |

---

## 6. Security and Invariants

- **Block time only** — No client timestamps for cooldowns or tick order; block number and (where used) block timestamp only.
- **Replay** — execute_tick requires `block_number > last_tick_block` and sequential `tick_counter`; same tick cannot be replayed.
- **Position spoofing** — hit_registration requires on-chain `player.x/y` to match provided `player_x`/`player_y` and distance ≤ MAX_HIT_RANGE.
- **Score** — Score only changes in execute_tick (collision kills) and hit_registration (kills); no client-supplied score delta.
- **Run immutability** — After `end_run`, run state is not updated by any system; submit_leaderboard only reads and writes the leaderboard entry and the `submitted_to_leaderboard` flag.
- **Upgrades** — Set at init; `upgrades_verified = true`; no mid-run upgrade change.
- **Coins** — Deduction and history (log hash, count, events) are consistent between init_game and spend_coins-style accounting.

---

## 7. Testing

- **Unit tests** — In `models.cairo` (`#[cfg(test)] mod tests`): Player, RunState, Enemy, GameTick, LeaderboardEntry creation and invariants.
- **Integration tests** — In `src/tests/test_systems_integration.cairo`: full flow (init → tick → hit → end_run → submit_leaderboard), claim_coins, and error/security cases. Use `dojo_cairo_test::spawn_test_world`, namespace/contract defs, and `starknet::testing::set_block_number` for block advancement.
- **Error / security tests** — Many expect a revert (e.g. invalid kernel, insufficient coins, out of range, replay, double submit). They use `#[should_panic(expected: (...))]` and are marked `#[ignore]` under `scarb test` (contract-call panics not treated as success); run with snforge to verify.

Commands:

```bash
scarb build
scarb test
```

---

## 8. Dependencies and Versions

- **Scarb.toml:** `dojo = "1.8.0"`, `starknet = "2.13.1"`, `dojo_cairo_test = "1.8.0"`, `cairo_test = "2.13.1"`.
- **World:** Dojo 1.8; namespace `neon_sentinel`; writers list in `dojo_dev.toml` / `dojo_release.toml`.

---

## 9. Extending the Codebase

- **New model:** Add in `models.cairo` with `#[dojo::model]` and keys; register in world if needed.
- **New system:** Add a new contract under `systems/`, implement interface, use `self.world(@"neon_sentinel")`; add to `lib.cairo` and to writers in dojo config; add resources to integration test namespace if tests touch it.
- **New event:** Define `#[dojo::event]` in the system; register `TestResource::Event(...)` in test namespace when testing that system.

This bible should be updated when new models, systems, or constants are added.
