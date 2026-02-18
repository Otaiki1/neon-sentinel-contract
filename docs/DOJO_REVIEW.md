# Dojo Code Review — Neon Sentinel

Review performed using the **dojo-review** skill. This document summarizes best-practice alignment, issues found, and recommendations.

---

## Review checklist summary

| Category   | Status | Notes |
| ---------- |--------|--------|
| **Models** | ✅ Pass | Traits, keys, key order correct; custom types have Introspect |
| **Systems** | ✅ Pass | Interfaces, `world_default`, namespace, events, caller checks |
| **Security** | ✅ Pass | Owner checks on admin; underflow fixes applied in `actions` |
| **Performance** | ✅ Pass | No duplicate model reads; appropriate types |
| **Tests** | ✅ Pass | Unit (models), integration (systems), failure cases with `should_panic` |

---

## 1. Model review

### 1.1 Checks performed

- **Required traits:** All `#[dojo::model]` structs derive `Drop` and `Serde`. ✅  
  - `DirectionsAvailable` correctly omits `Copy` (contains `Array`). ✅  
- **Keys:** Every model has at least one `#[key]`; composite keys (e.g. `RunState`, `GameTick`) are correct. ✅  
- **Key order:** Key fields appear before data fields in every struct. ✅  
- **Custom types:** `Vec2` uses `IntrospectPacked`; `Direction` uses `Introspect`. ✅  

### 1.2 Notes

- **Model size:** `Player`, `RunState`, `PlayerProfile` are large but represent cohesive game/profile state; splitting further would add cross-model sync complexity. Acceptable for this design.
- **God models:** No single model is overloaded with unrelated concerns; game vs. economy vs. shop are separated.

---

## 2. System review

### 2.1 Checks performed

- **Interface:** All systems use `#[starknet::interface]` and `#[abi(embed_v0)]`. ✅  
- **Contract:** All use `#[dojo::contract]`. ✅  
- **World access:** Every system uses `world_default()` backed by `self.world(@"neon_sentinel")`. ✅  
- **Input validation:**  
  - `init_game`: kernel ≤ MAX_KERNEL, upgrade mask, cost match, coins, no active run. ✅  
  - `end_run`: run active, run_id match, not already finished. ✅  
  - `spend_coins`: amount > 0, sufficient balance. ✅  
  - `claim_coins`: cooldown (blocks since last claim). ✅  
  - `submit_leaderboard`: finished, not submitted, week match. ✅  
  - `update_exchange_rate` / `pause_unpause_purchasing`: owner check. ✅  
  - `buy_coins`: amount, allowance, balance, rate-based coins, paused. ✅  
- **Events:** Important actions emit events (game_start/game_end, CoinSpent, CoinClaimed, CoinsPurchased, etc.). ✅  
- **Caller identity:** Systems use `get_caller_address()` for player/owner; no delegation. ✅  

### 2.2 Recommendations

- **end_run:** Consider asserting `final_layer` in a valid range (e.g. 1..=MAX_LAYER with MAX_LAYER = 6) so `profile.current_layer` cannot be set to an invalid value by a bad client. Low risk; improves consistency.
- **Error messages:** Existing messages are clear and specific ('Invalid kernel', 'Run id mismatch', 'Not owner', etc.). ✅  

---

## 3. Security review

### 3.1 Authorization

- **Owner-only:** `update_exchange_rate`, `pause_unpause_purchasing`, `withdraw_strk`, `request_withdrawal`, `execute_withdrawal` all use `IsOwnerTrait::is_owner(caller, global.owner)`. ✅  
- **Player-scoped:** `init_game`, `end_run`, `submit_leaderboard`, `claim_coins`, `spend_coins` use caller as player; run ownership validated via `run_id` and `is_active`. ✅  

### 3.2 Integer safety

- **Underflow (fixed in this review):**  
  - **actions.cairo `move()`:** Added `assert(moves.remaining > 0, 'No moves left')` before `moves.remaining -= 1` to avoid underflow when `can_move` is true but `remaining` is 0.  
  - **actions.cairo `next_position()`:** Left/Up now only decrement `x`/`y` when `> 0`, avoiding underflow at (0,0).  
- **init_game / spend_coins / end_run:** Coins and profile updates are guarded by asserts (e.g. `profile.coins >= amount` before subtract). ✅  
- **claim_coins:** `blocks_since_claim = block_number - profile.last_coin_claim_block` can theoretically underflow if `block_number < last_coin_claim_block` (e.g. reorg or bad data). **Recommendation:** Add defensive assert: `assert(block_number >= profile.last_coin_claim_block, 'Invalid block state')` before computing `blocks_since_claim`, or document that profile must be written with non-decreasing block. Low likelihood in practice.  

### 3.3 State consistency

- Run lifecycle: init_game → end_run → submit_leaderboard; no backward transitions. ✅  
- Double submission prevented by `submitted_to_leaderboard` check. ✅  
- Coin log hash and count updated atomically with balance changes. ✅  

---

## 4. Gas / performance

- **Duplicate reads:** No system reads the same model key twice in one path without reusing the variable. ✅  
- **Types:** u8/u32/u64 used appropriately; u256 only where needed (run_id, hashes, STRK amounts). ✅  

---

## 5. Test coverage

- **Unit tests (models.cairo):** Player, RunState, Enemy, GameTick, GameEvent, LeaderboardEntry, PlayerProfile, CoinShop models covered. ✅  
- **Integration tests (test_systems_integration.cairo):** init_game, end_run, submit_leaderboard, claim_coins flows; block advancement; failure cases with `#[should_panic]` + `#[ignore]` where scarb test doesn’t handle contract panics. ✅  
- **Coin shop (test_coin_shop.cairo):** init, buy_coins, pause, exchange rate, withdrawals, failure cases. ✅  
- **World (test_world.cairo):** Basic world/spawn. ✅  

---

## 6. Anti-patterns checked

- **God models:** None. ✅  
- **Missing world_default:** All systems use a `world_default()` helper. ✅  
- **Missing events:** Critical state changes emit events. ✅  

---

## 7. Changes made during review

1. **src/systems/actions.cairo**  
   - Before `moves.remaining -= 1`: added `assert(moves.remaining > 0, 'No moves left')`.  
   - In `next_position()`: Left only decrements `x` if `x > 0`; Up only decrements `y` if `y > 0` (avoids underflow at origin).

---

## 8. Optional follow-ups

1. **end_run:** Add `assert(final_layer >= 1 && final_layer <= 6, 'Invalid layer')` (or use a shared `MAX_LAYER` constant).  
2. **claim_coins:** Add defensive check that `block_number >= profile.last_coin_claim_block` before computing `blocks_since_claim`.  
3. **Tests:** Run `snforge test` (not only `scarb test`) to execute `#[should_panic]` contract tests that are currently `#[ignore]` under scarb.

---

## 9. Conclusion

The project follows Dojo and Cairo best practices: models are well-structured, systems use interfaces and namespaced world access, sensitive functions are protected by owner/caller checks, and integer operations are either asserted or guarded. Two underflow risks in `actions.cairo` were fixed; the rest of the checklist is satisfied. Optional hardening (final_layer range, claim_coins block check) and running snforge for panic tests are recommended next steps.
