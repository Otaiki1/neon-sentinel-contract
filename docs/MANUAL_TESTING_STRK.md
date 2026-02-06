# Manual Testing Guide: STRK Coin Purchase System

Use this checklist to verify the STRK → in-game coins flow on a deployed world (e.g. Katana).

---

## SETUP

- [ ] Deploy contracts to Katana (or target network)
- [ ] Run migration: `sozo migrate`
- [ ] Initialize coin shop: call `initialize_coin_shop(strk_token_address, 5)` (owner/deployer)
- [ ] Confirm exchange rate is 5 (coins per STRK)
- [ ] Max purchase per transaction is 1000 STRK (enforced in contract)

---

## BASIC FUNCTIONALITY

- [ ] User approves STRK token to the buy_coins contract (ERC20 `approve`)
- [ ] User calls `buy_coins(amount_strk, max_coins_expected)` with `max_coins_expected = amount_strk * 5`
- [ ] Verify player received `amount_strk * 5` coins (e.g. 10 STRK → 50 coins)
- [ ] Check purchase record exists (CoinPurchaseRecord) in Torii / world state
- [ ] Check CoinPurchaseHistory updated for the player

---

## BALANCE VERIFICATION

- [ ] Contract STRK balance increased by `amount_strk`
- [ ] Call `get_treasury_balance()` — matches expected collected amount
- [ ] Call `get_treasury_info()` — (collected, withdrawn, available, pending) correct
- [ ] Player STRK balance decreased by `amount_strk`
- [ ] Player profile coins increased by `amount_strk * rate`

---

## EVENT VERIFICATION

- [ ] `CoinsPurchased` event emitted on buy
- [ ] Event fields: player, strk_amount, coins_minted, purchase_id, block_number
- [ ] Torii / indexer has indexed the event

---

## OWNER FUNCTIONS

- [ ] Owner calls `request_withdrawal(amount_strk, notes)` (e.g. 5 STRK)
- [ ] WithdrawalRequest created with status = pending
- [ ] Wait ≥ 100 blocks (or use `execute_withdrawal(withdrawal_id)` after delay)
- [ ] Owner calls `execute_withdrawal(withdrawal_id)`
- [ ] STRK transferred to owner
- [ ] Treasury balance (get_treasury_balance / get_treasury_info) updated
- [ ] Alternative: owner uses immediate `withdraw_strk(amount_strk, notes)` (no delay)

---

## PAUSE / UNPAUSE

- [ ] Owner calls `pause_unpause_purchasing()` → purchasing paused
- [ ] User tries to buy coins → fails with "Purchasing paused"
- [ ] Owner calls `pause_unpause_purchasing()` again → purchasing unpaused
- [ ] User buys coins again → succeeds

---

## ERROR CASES

- [ ] Buy with insufficient approval → fails with "Approve STRK first" (or allowance error)
- [ ] Buy with insufficient STRK balance → fails with "Insufficient STRK balance"
- [ ] Non-owner calls `withdraw_strk` → fails with "Not owner"
- [ ] Non-owner calls `pause_unpause_purchasing` → fails with "Not owner"
- [ ] Buy with `amount_strk = 0` → fails with "Invalid STRK amount"
- [ ] Buy with `amount_strk > 1000` → fails with "Invalid STRK amount" / max
- [ ] Buy with wrong `max_coins_expected` (e.g. 99 instead of 50 for 10 STRK) → fails with "Expected coins mismatch"
- [ ] Owner withdraws more than available → fails with "Exceeds available" or "STRK transfer failed"

---

## PERFORMANCE

- [ ] First purchase completes in &lt; 2 seconds (target)
- [ ] Withdrawal completes in &lt; 2 seconds (target)
- [ ] Multiple purchases in sequence succeed
- [ ] No apparent memory / state corruption after many operations

---

## TORII / INDEXING

- [ ] GraphQL (or Torii) query returns all purchases
- [ ] Can filter by player address
- [ ] Can filter by block range
- [ ] World Explorer (or UI) shows purchase records and history

---

## TWO-PHASE WITHDRAWAL (OPTIONAL)

- [ ] Owner calls `request_withdrawal(amount, notes)` → RequestCreated event
- [ ] Wait 100+ blocks
- [ ] Owner calls `execute_withdrawal(withdrawal_id)` → WithdrawalExecuted + StrkWithdrawn
- [ ] STRK received by owner; treasury updated

---

## SECURITY SANITY CHECKS

- [ ] Only owner can withdraw, pause, update rate
- [ ] Coin amount is always `amount_strk * rate` (server-calculated; client cannot inflate)
- [ ] Withdrawal cannot exceed `total_strk_collected - total_strk_withdrawn`
- [ ] Records (CoinPurchaseRecord, WithdrawalRequest) are immutable after creation
