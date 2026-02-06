# Security Review Checklist: STRK Coin Purchase System

Reviewer: fill in  
Date: fill in  

---

## 1. ACCESS CONTROL

| Item | Status | Notes |
|------|--------|--------|
| Only owner can withdraw STRK | [x] Passed | `withdraw_strk`, `request_withdrawal`, `execute_withdrawal` all assert `IsOwnerTrait::is_owner(caller, owner)`. |
| Only owner can pause/unpause | [x] Passed | `pause_unpause_purchasing` asserts `IsOwnerTrait::is_owner(caller, global.owner)`. |
| Only owner can initialize | [x] Passed | Initialize is callable once by any address; that caller becomes owner. Re-initialization blocked by `existing.coin_exchange_rate == 0` check. No way to change owner after. |
| Only owner can update rate (if allowed) | [x] Passed | `update_exchange_rate` asserts `IsOwnerTrait::is_owner(caller, global.owner)`. Rate is updateable by owner with 20% cap. |

---

## 2. AMOUNT VALIDATION

| Item | Status | Notes |
|------|--------|--------|
| No zero purchases allowed | [x] Passed | `ValidateStrkAmountTrait::validate_strk_amount` rejects zero; `coins_u32 > 0` asserted. |
| Max purchase enforced | [x] Passed | `validate_strk_amount` enforces `amount <= MAX_STRK_PURCHASE` (1000). |
| No overflow in multiplication | [x] Passed | `u256_overflowing_mul` used in `calculate_coins_from_strk` and in `validate_strk_amount` (rate 5); overflow asserted false. |
| STRK amount validated | [x] Passed | Same validation covers > 0, <= 1000, and overflow check for rate 5. |

---

## 3. TOKEN HANDLING

| Item | Status | Notes |
|------|--------|--------|
| transferFrom used (not transfer) | [x] Passed | `buy_coins` uses `token.transfer_from(caller, this_contract, amount_strk)`. Withdrawals use `transfer` (contract → owner), which is correct. |
| Transfer success verified | [x] Passed | `assert(VerifyTransferSucceededTrait::verify_transfer_succeeded(ok), 'STRK transfer failed')` after `transfer_from`; same pattern for `transfer` in withdraw/execute. |
| Balance checked before transfer | [x] Passed | `CheckStrkBalanceTrait::check_strk_balance(...)` asserted before `transfer_from`. |
| Allowance checked before transfer | [x] Passed | `CheckStrkAllowanceTrait::check_strk_allowance(...)` asserted before `transfer_from`. |

---

## 4. STATE CONSISTENCY

| Item | Status | Notes |
|------|--------|--------|
| Config updated atomically | [x] Passed | Each function does a single `write_model(@config)` (or multiple writes in one logical step); no partial writes. |
| Config never corrupted | [x] Passed | Only owner-guarded paths and `buy_coins` (validated) update config; no arbitrary overwrites. |
| Total collected always accurate | [x] Passed | `total_strk_collected` only incremented in `buy_coins` by `amount_strk` after validation; never decreased. |
| Treasury balance always correct | [x] Passed | `available = total_strk_collected - total_strk_withdrawn`; withdrawals assert `amount <= available` and increment `total_strk_withdrawn`. |

---

## 5. REENTRANCY

| Item | Status | Notes |
|------|--------|--------|
| No external calls in middle of state change | [x] Passed | **withdraw_strk** and **execute_withdrawal** update `total_strk_withdrawn` and write config before calling `token.transfer`. |
| All state updated before ERC20 call | [x] Passed | Treasury state (config) is written before any `transfer` call. |
| Use checks-effects-interactions pattern | [x] Passed | Checks → effects (update and write config) → interaction (transfer). |

---

## 6. IMMUTABILITY

| Item | Status | Notes |
|------|--------|--------|
| Owner can't be changed | [x] Passed | Owner set only in `initialize_coin_shop`; no function updates `CoinShopGlobal.owner` or config owner. |
| Exchange rate locked (after init) | [ ] N/A (by design) | Rate is **not** locked: `update_exchange_rate` allows owner to change it (3–10, max 20% per update). If product requirement is “immutable rate”, remove or disable that path. |
| Purchase records immutable | [x] Passed | `CoinPurchaseRecord` and `CoinPurchaseHistory` are only written once per purchase; no update/delete. |
| Treasury history preserved | [x] Passed | `total_strk_collected` never decreased; `total_strk_withdrawn` only increased; `WithdrawalRequest` written and status updated, not overwritten. |

---

## 7. AUDIT TRAIL

| Item | Status | Notes |
|------|--------|--------|
| All purchases recorded | [x] Passed | `CoinPurchaseRecord` and `CoinPurchaseHistory` written for every `buy_coins`. |
| All withdrawals recorded | [x] Passed | `WithdrawalRequest` created for immediate withdraw and for request/execute flow; status and amounts stored. |
| Events emitted for all actions | [x] Passed | `CoinsPurchased`, `StrkWithdrawn`, `WithdrawalRequestCreated`, `WithdrawalExecuted`, `CoinShopInitialized`, `PurchasingPauseToggled`, `ExchangeRateUpdated`. |
| Timestamps recorded | [x] Passed | `purchase_block`, `purchase_timestamp`, `requested_block`, `executed_block`, `last_updated` used where relevant. |

---

## 8. OVERFLOW/UNDERFLOW

| Item | Status | Notes |
|------|--------|--------|
| Use checked_mul for strk * rate | [x] Passed | `u256_overflowing_mul` used; overflow asserted false. |
| Use checked_sub for withdrawals | [x] Passed | `available = total_strk_collected - total_strk_withdrawn`; Cairo u256 subtraction is checked (reverts on underflow). Amount ≤ available is asserted before any transfer. |
| All arithmetic checked | [x] Passed | No unchecked add/sub/mul in the STRK paths; u32 increments (e.g. `collected_strk_version`, `purchase_count`) are bounded by usage. |
| No silent overflows | [x] Passed | Overflow in coin calculation causes revert; coins capped to u32 for profile. |

---

## Summary

- **Passed:** Access control, amount validation, token handling, state consistency, reentrancy (checks-effects-interactions), immutability (owner and records), audit trail, overflow/underflow.
- **N/A / design choice:** Exchange rate is intentionally updateable by owner (with 20% cap); lock it if the design should be “rate immutable after init”.
