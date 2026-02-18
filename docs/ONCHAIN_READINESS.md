# Neon Sentinel — On-Chain Readiness

This document maps the **frontend game** (React + Phaser, currently localStorage-only) to the **Dojo contracts** in this repo. It identifies what is already on-chain, what is partial, and what is missing so the frontend can rely on the chain for economy, runs, leaderboards, inventory, settings, and avatars.

**Design principle:** Movement, bullets, and real-time gameplay stay **off-chain**. The chain records: run lifecycle (start/end), final scores, economy (coins, STRK purchases), inventory (mini-mes, sessions), leaderboards, user stats, avatars unlocked/active, and user settings.

---

## 1. What You Want On-Chain (Summary)

| Area | Frontend source | On-chain? |
|------|------------------|-----------|
| **Economy** | Coins, STRK → coins, inventory, mini-me purchases & sessions | Coins + STRK ✅; inventory + mini-me ❌ |
| **Leaderboards** | Weekly scores, categories | ✅ |
| **User stats** | Lifetime score, kills, runs, best run, etc. | ✅ (in PlayerProfile) |
| **Avatars unlocked** | Purchased list, active avatar | Unlocks ✅ (bitfield); active ❌ |
| **User settings** | Difficulty, accessibility, visual | ❌ |
| **Start of run** | init_game with kernel + upgrades | ✅ |
| **End of run** | final score, kills, layer (validated) | ✅ (client-submitted) |
| **Updating scores** | After game over | ✅ (end_run + submit_leaderboard) |

---

## 2. Current Contract Support (What’s Already There)

### 2.1 Economy

- **Coins**
  - **claim_coins()** — Daily claim (3 coins per 7200 blocks). ✅
  - **spend_coins(amount, reason)** — Generic spend; used by init_game for pregame upgrades and can be used for other reasons. ✅
  - **buy_coins(amount_strk, max_coins_expected)** — STRK → in-game coins; shop must be initialized; owner can pause/update rate. ✅
- **Coin state** — Stored in **PlayerProfile** (coins, last_coin_claim_block, coin_transaction_log_hash, coin_transaction_count). ✅
- **STRK shop** — CoinShopGlobal, TokenPurchaseConfig, CoinPurchaseRecord, CoinPurchaseHistory, WithdrawalRequest; initialize_coin_shop, update_exchange_rate, pause_unpause_purchasing. ✅

### 2.2 Runs and Scores

- **Start run** — **init_game(kernel, pregame_upgrades_mask, expected_cost)**. Generates a **run_id** (run hash) from block + caller; creates Player + RunState, deducts coins for upgrades. Kernel 0 is free; kernels 1..5 must be unlocked via **purchase_cosmetic**. If the player already had an active run, that run is abandoned (no consolidation); a new run_id is created. ✅
- **End run** — **end_run(run_id, final_score, total_kills, final_layer)**. Validates run_id matches current Player.run_id; updates RunState (is_finished, final_*), Player (inactive), PlayerProfile (total_runs, lifetime_*, best_run_score, current_layer, +10 coins if score ≥ 1000). Mints **RankNFT** when the player reaches a new rank tier (prestige×6 + layer−1). ✅
- **Leaderboard** — **submit_leaderboard(run_id, week)**. Creates immutable LeaderboardEntry; week = block_number / 50400. General game state for ranking = LeaderboardEntry queries by week; user metrics = PlayerProfile. ✅

### 2.3 User Stats (PlayerProfile)

PlayerProfile already has:

- current_prestige, current_layer, highest_prestige_reached, is_prime_sentinel  
- total_runs, lifetime_score, lifetime_playtime_blocks, lifetime_enemies_defeated  
- best_combo_multiplier, best_run_score, best_corruption_reached  
- coins, last_coin_claim_block, coin_transaction_*, selected_kernel, kernel_unlocks  
- **avatar_unlocks**, **cosmetic_unlocks** (u64 bitfields)  
- last_profile_update_block, profile_hash  

So: **user stats and “avatars unlocked” (as a bitfield) are on-chain.** What’s missing is a **selected/active avatar** field and a way to update it.

**purchase_cosmetic** and **Rank NFTs:** **purchase_cosmetic(item_type, item_id)** spends coins and sets bits in kernel_unlocks, avatar_unlocks, or cosmetic_unlocks; init_game validates the selected kernel is unlocked. **Rank NFTs** are minted on end_run when the player reaches a new rank tier; query RankNFT by owner for display.

### 2.4 What Is Intentionally Off-Chain

- Player position, bullets, enemy positions, hits, mid-run score, combo, abilities (overclock, shock bomb, god mode) — all client-side. No execute_tick or hit_registration on-chain. ✅ Matches your goal.

---

## 3. Gaps (Missing for Full On-Chain Parity)

### 3.1 Inventory (Mini-Mes) and Sessions

**Frontend:**  
- **MiniMeInventory** — Per-type counts: scout, gunner, shield, decoy, collector, stun, healer (each 0–20).  
- **Mini-me sessions** — Stored as a number (sessions remaining or similar).

**Contracts:**  
- No **PlayerInventory** (or similar) model.  
- No system to **purchase mini-me** (spend coins + increment count) or **purchase/refill sessions**.

**Recommendation:**

1. **Model:** Add a **PlayerInventory** (or **MiniMeInventory**) model, keyed by `player_address`, with:
   - One field per mini-me type (e.g. scout, gunner, shield, decoy, collector, stun, healer) as u8 or u32, capped at 20.
   - Optionally a `mini_me_sessions` (or `sessions_remaining`) field (u32) if “sessions” are a single consumable pool.
2. **Systems:**
   - **purchase_mini_me** (or **spend_coins_for_mini_me**): Accept (e.g.) `mini_me_type: u8`, `count: u8`. Look up cost from config or constant, call same coin-deduction + log pattern as spend_coins, then increment the corresponding count in PlayerInventory (cap at 20).
   - **purchase_mini_me_sessions** (if needed): Same idea — fixed coin cost, deduct coins, increment `mini_me_sessions` in the same (or same) model.

Use **dojo-model** for the new model and **dojo-system** for the purchase system(s). Register the new system as a writer in dojo_dev.toml, dojo_sepolia.toml, dojo_release.toml.

### 3.2 Active Avatar

**Frontend:**  
- **activeAvatarId** — Single selected avatar (e.g. default_sentinel, transcendent_form).

**Contracts:**  
- **avatar_unlocks** (u64) exists on PlayerProfile; no field for “currently selected avatar”.

**Recommendation:**

1. Add **active_avatar_id** to **PlayerProfile** (e.g. u8 index or felt252; if you have a small fixed set, u8 is enough).
2. Add a system **set_active_avatar(avatar_id)** that:
   - Ensures caller owns the profile row.
   - Optionally checks that `avatar_id` is unlocked (e.g. bit in avatar_unlocks or an allowlist).
   - Sets `profile.active_avatar_id = avatar_id` and writes the profile.

Small change; can be done in the same contract as another small system or a tiny new one.

### 3.3 User Settings

**Frontend:**  
- **GameplaySettings** — difficulty (normal/easy/hard), accessibility (colorBlindMode, highContrast, dyslexiaFont, reduceMotion, reduceFlash), visual (uiScale, uiOpacity, screenShakeIntensity, gridIntensity).

**Contracts:**  
- No model or system for per-player settings.

**Recommendation:**

1. **Model:** **PlayerSettings**, keyed by `player_address`, with packed fields, e.g.:
   - difficulty: u8 (0=normal, 1=easy, 2=hard)
   - color_blind_mode, high_contrast, dyslexia_font, reduce_motion, reduce_flash: bool (or u8 0/1)
   - ui_scale, ui_opacity, screen_shake_intensity, grid_intensity: u8 or u16 (scale to 0–100 or 0–255)
2. **System:** **update_settings(...)** that:
   - Takes the same fields (or a packed struct).
   - Reads PlayerSettings(caller), updates fields, writes back. Only caller can write their row.

Frontend then reads PlayerSettings from Torii/GraphQL and applies values at boot (same as today with localStorage, but source of truth is chain).

### 3.4 Profile Creation (Seeding)

**Frontend:**  
- New players have no profile until they do something that creates it.

**Contracts:**  
- **claim_coins**, **buy_coins**, and **init_game** all **read** PlayerProfile (caller). In Dojo, a missing row typically returns default (zeros). So:
  - First **claim_coins** or **buy_coins** will write a new profile (0 + coins, etc.) — **profile is created on first claim or first STRK purchase.** ✅
  - **init_game** with expected_cost 0 works with default profile (0 coins); with cost > 0 the assert would fail until they have claimed or bought coins. So new players should **claim_coins** (or buy_coins) before starting a paid run. No separate “create profile” system is strictly required; document this flow for the frontend.

---

## 4. Implementation Checklist (Recommended Order)

| # | Item | Type | Notes |
|---|------|------|--------|
| 1 | **PlayerInventory** (mini-me counts + optional sessions) | Model | Key: player_address; 7× counts (u8), optional sessions (u32). |
| 2 | **purchase_mini_me** (and optionally **purchase_mini_me_sessions**) | System | Deduct coins (same pattern as spend_coins), update inventory; enforce caps. |
| 3 | **active_avatar_id** on PlayerProfile + **set_active_avatar** | Model + System | Small profile field + one system. |
| 4 | **PlayerSettings** + **update_settings** | Model + System | Packed settings; caller-only write. |
| 5 | Dojo config | Config | Add new systems to writers in dojo_dev.toml, dojo_sepolia.toml, dojo_release.toml. |
| 6 | Torii / frontend | Integration | Index new models; frontend reads inventory, settings, active_avatar from chain instead of (or in addition to) localStorage. |

---

## 5. Skills to Use

- **dojo-model** — When adding PlayerInventory and PlayerSettings (keys, types, trait derivations).
- **dojo-system** — When adding purchase_mini_me, purchase_mini_me_sessions, set_active_avatar, update_settings (interfaces, world access, validation, events).
- **dojo-review** — After adding models/systems, run a quick review for traits, keys, and security.
- **dojo-config** — When adding new system contracts to writers in dojo_*.toml.

---

## 6. Summary

- **Already on-chain and aligned with “no movements/bullets on-chain”:** economy (coins, STRK purchases), run start/end, client-submitted final state, leaderboards, user stats and avatar/cosmetic unlock bitfields in PlayerProfile.
- **Missing for your list:**  
  - **Inventory:** Mini-me counts and sessions + purchase flow (model + system(s)).  
  - **Active avatar:** Profile field + set_active_avatar system.  
  - **User settings:** PlayerSettings model + update_settings system.  
- **Profile creation:** Handled by first claim_coins or buy_coins; document for frontend.

Once the missing model and systems above are implemented and wired into the Dojo config and Torii, the frontend can treat the chain as the source of truth for economy, inventory, leaderboards, user stats, avatars, and settings, while keeping all movement and bullets off-chain.
