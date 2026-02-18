//! Token validation helpers for STRK: amount checks, coin calculation, balance/allowance.

use core::integer::u256;
use starknet::ContractAddress;

use neon_sentinel::erc20::IERC20DispatcherTrait;

/// Max STRK per purchase (e.g. 1000 STRK per transaction).
const MAX_STRK_PURCHASE: u256 = u256 { low: 1000, high: 0 };

/// Returns true if a >= b (u256).
fn u256_ge(a: u256, b: u256) -> bool {
    a.high > b.high || (a.high == b.high && a.low >= b.low)
}

/// 1. Validate STRK amount: > 0, <= MAX_STRK_PURCHASE, and no overflow when multiplied by max rate (100).
pub trait ValidateStrkAmountTrait {
    fn validate_strk_amount(amount: u256) -> bool;
}

impl ValidateStrkAmount of ValidateStrkAmountTrait {
    fn validate_strk_amount(amount: u256) -> bool {
        if amount.high == 0 && amount.low == 0 {
            return false;
        }
        if amount.high > MAX_STRK_PURCHASE.high
            || (amount.high == MAX_STRK_PURCHASE.high && amount.low > MAX_STRK_PURCHASE.low)
        {
            return false;
        }
        let rate_max = u256 { low: 100, high: 0 };
        let (_, overflow) = core::integer::u256_overflowing_mul(amount, rate_max);
        !overflow
    }
}

/// 2. Calculate coins from STRK: amount_strk * rate with overflow protection.
/// Returns (coins, overflow).
pub trait CalculateCoinsFromStrkTrait {
    fn calculate_coins_from_strk(amount_strk: u256, rate: u32) -> (u256, bool);
}

impl CalculateCoinsFromStrk of CalculateCoinsFromStrkTrait {
    fn calculate_coins_from_strk(amount_strk: u256, rate: u32) -> (u256, bool) {
        let rate_u128: u128 = rate.try_into().unwrap();
        let rate_u256 = u256 { low: rate_u128, high: 0 };
        core::integer::u256_overflowing_mul(amount_strk, rate_u256)
    }
}

/// 3. Check STRK balance: true if balance_of(player) >= required.
pub trait CheckStrkBalanceTrait {
    fn check_strk_balance(
        strk_token_address: ContractAddress,
        player: ContractAddress,
        required: u256,
    ) -> bool;
}

impl CheckStrkBalance of CheckStrkBalanceTrait {
    fn check_strk_balance(
        strk_token_address: ContractAddress,
        player: ContractAddress,
        required: u256,
    ) -> bool {
        let token = neon_sentinel::erc20::IERC20Dispatcher {
            contract_address: strk_token_address,
        };
        let balance = token.balance_of(player);
        u256_ge(balance, required)
    }
}

/// 4. Check STRK allowance: true if allowance(owner, spender) >= required.
pub trait CheckStrkAllowanceTrait {
    fn check_strk_allowance(
        strk_token_address: ContractAddress,
        owner: ContractAddress,
        spender: ContractAddress,
        required: u256,
    ) -> bool;
}

impl CheckStrkAllowance of CheckStrkAllowanceTrait {
    fn check_strk_allowance(
        strk_token_address: ContractAddress,
        owner: ContractAddress,
        spender: ContractAddress,
        required: u256,
    ) -> bool {
        let token = neon_sentinel::erc20::IERC20Dispatcher {
            contract_address: strk_token_address,
        };
        let allowed = token.allowance(owner, spender);
        u256_ge(allowed, required)
    }
}

/// 5. Verify transfer succeeded (use the bool returned by transfer/transfer_from).
pub trait VerifyTransferSucceededTrait {
    fn verify_transfer_succeeded(success: bool) -> bool;
}

impl VerifyTransferSucceeded of VerifyTransferSucceededTrait {
    fn verify_transfer_succeeded(success: bool) -> bool {
        success
    }
}
