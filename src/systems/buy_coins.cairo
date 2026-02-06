//! buy_coins system: users purchase in-game coins with STRK. Main revenue system.

use core::integer::u256;

const ZERO_FELT: felt252 = 0;

const WITHDRAWAL_STATUS_EXECUTED: u8 = 2;

#[starknet::interface]
pub trait IBuyCoins<T> {
    fn buy_coins(ref self: T, amount_strk: u256, max_coins_expected: u256) -> u256;
    fn withdraw_strk(ref self: T, amount_strk: u256, notes: felt252) -> u256;
}

#[dojo::contract]
pub mod buy_coins {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_execution_info};

    use super::{WITHDRAWAL_STATUS_EXECUTED, ZERO_FELT};
    use super::IBuyCoins;
    use neon_sentinel::erc20::IERC20DispatcherTrait;
    use neon_sentinel::models::{
        CoinPurchaseHistory, CoinPurchaseRecord, CoinShopGlobal, TokenPurchaseConfig,
        PlayerProfile, WithdrawalRequest,
    };
    use neon_sentinel::token_validation::{
        CalculateCoinsFromStrkTrait, CheckStrkAllowanceTrait, CheckStrkBalanceTrait,
        ValidateStrkAmountTrait, VerifyTransferSucceededTrait,
    };

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    /// Append to coin log hash chain (same as claim_coins / spend_coins).
    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 { low: prev.low + bl + am, high: prev.high + 1 }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CoinsPurchased {
        #[key]
        pub player: ContractAddress,
        pub strk_amount: u256,
        pub coins_minted: u256,
        pub purchase_id: u256,
        pub block_number: u64,
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct StrkWithdrawn {
        #[key]
        pub owner: ContractAddress,
        pub amount: u256,
        pub withdrawal_id: u256,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl BuyCoinsImpl of IBuyCoins<ContractState> {
        fn buy_coins(ref self: ContractState, amount_strk: u256, max_coins_expected: u256) -> u256 {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;
            let block_timestamp = exec_info.block_info.block_timestamp;
            let this_contract = get_contract_address();

            // 1. Resolve config via global owner pointer
            let global: CoinShopGlobal = world.read_model(ZERO_FELT);
            let owner = global.owner;
            let mut config: TokenPurchaseConfig = world.read_model(owner);

            // 2. Validate purchasing enabled and not paused
            assert(config.is_enabled, 'Purchasing disabled');
            assert(!config.paused, 'Purchasing paused');

            // 3. Validate STRK amount (> 0, <= max, no overflow when * 5)
            assert(ValidateStrkAmountTrait::validate_strk_amount(amount_strk), 'Invalid STRK amount');

            // 4. Calculate coins: amount_strk * exchange_rate (overflow-safe)
            let (coins_to_mint, overflow) =
                CalculateCoinsFromStrkTrait::calculate_coins_from_strk(
                    amount_strk,
                    config.coin_exchange_rate,
                );
            assert(!overflow, 'Exchange overflow');

            // SECURITY: Reject client manipulation — only accept exact calculated amount
            assert(
                max_coins_expected.low == coins_to_mint.low
                    && max_coins_expected.high == coins_to_mint.high,
                'Expected coins mismatch',
            );

            // Coins added to profile are u32 — ensure result fits
            assert(coins_to_mint.high == 0, 'Coins exceed u32');
            let coins_u32: u32 = coins_to_mint.low.try_into().unwrap();
            assert(coins_u32 > 0, 'No coins to mint');

            // 5. Check balance and allowance before transfer
            assert(
                CheckStrkBalanceTrait::check_strk_balance(
                    config.strk_token_address,
                    caller,
                    amount_strk,
                ),
                'Insufficient STRK balance',
            );
            assert(
                CheckStrkAllowanceTrait::check_strk_allowance(
                    config.strk_token_address,
                    caller,
                    this_contract,
                    amount_strk,
                ),
                'Approve STRK first',
            );

            // 6. Transfer STRK from player to this contract
            let token = neon_sentinel::erc20::IERC20Dispatcher {
                contract_address: config.strk_token_address,
            };
            let ok = token.transfer_from(caller, this_contract, amount_strk);
            assert(
                VerifyTransferSucceededTrait::verify_transfer_succeeded(ok),
                'STRK transfer failed',
            );

            // 8. Get or create profile and add coins
            let mut profile: PlayerProfile = world.read_model(caller);
            profile.coins += coins_u32;
            profile.last_coin_claim_block = block_number;
            profile.coin_transaction_log_hash =
                next_coin_log_hash(profile.coin_transaction_log_hash, block_number, coins_u32);
            profile.coin_transaction_count += 1;
            profile.last_profile_update_block = block_number;
            world.write_model(@profile);

            // 9. Update TokenPurchaseConfig treasury and unique purchase id
            let version_u128: u128 = config.collected_strk_version.try_into().unwrap();
            let purchase_id = u256 {
                low: (block_number.try_into().unwrap()) * 0x100000000 + version_u128,
                high: 0,
            };
            config.total_strk_collected = config.total_strk_collected + amount_strk;
            config.total_coins_sold = config.total_coins_sold + coins_to_mint;
            config.last_updated = block_number;
            config.collected_strk_version += 1;
            world.write_model(@config);

            let tx_hash = zero_u256(); // Could be set from get_execution_info if available
            let record = CoinPurchaseRecord {
                purchase_id,
                player_address: caller,
                strk_amount: amount_strk,
                coins_received: coins_to_mint,
                purchase_block: block_number,
                purchase_timestamp: block_timestamp,
                transaction_hash: tx_hash,
                verified: true,
            };
            world.write_model(@record);

            // 11. Update CoinPurchaseHistory for player
            let mut history: CoinPurchaseHistory = world.read_model(caller);
            history.total_strk_spent = history.total_strk_spent + amount_strk;
            history.total_coins_purchased = history.total_coins_purchased + coins_to_mint;
            history.purchase_count += 1;
            if history.first_purchase_block == 0 {
                history.first_purchase_block = block_number;
            }
            history.last_purchase_block = block_number;
            history.last_claimed_coins_block = block_number;
            history.verified_purchases += 1;
            world.write_model(@history);

            // 12. Emit event for Torii indexing
            world.emit_event(@CoinsPurchased {
                player: caller,
                strk_amount: amount_strk,
                coins_minted: coins_to_mint,
                purchase_id,
                block_number,
            });

            coins_to_mint
        }

        fn withdraw_strk(ref self: ContractState, amount_strk: u256, notes: felt252) -> u256 {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            let global: CoinShopGlobal = world.read_model(ZERO_FELT);
            let owner = global.owner;
            assert(caller == owner, 'Not owner');

            let mut config: TokenPurchaseConfig = world.read_model(owner);

            assert(amount_strk.low > 0 || amount_strk.high > 0, 'Amount must be positive');
            let total = config.total_strk_collected;
            assert(
                amount_strk.high < total.high
                    || (amount_strk.high == total.high && amount_strk.low <= total.low),
                'Exceeds collected',
            );

            let token = neon_sentinel::erc20::IERC20Dispatcher {
                contract_address: config.strk_token_address,
            };
            let ok = token.transfer(owner, amount_strk);
            assert(ok, 'STRK transfer failed');

            config.total_strk_collected = config.total_strk_collected - amount_strk;
            config.last_updated = block_number;
            world.write_model(@config);

            let withdrawal_id = u256 {
                low: (block_number.try_into().unwrap()) * 0x100000000
                    + (block_number.try_into().unwrap() % 0x100000000),
                high: 0,
            };
            let request = WithdrawalRequest {
                withdrawal_id,
                owner_address: owner,
                strk_amount: amount_strk,
                requested_block: block_number,
                status: WITHDRAWAL_STATUS_EXECUTED,
                executed_block: block_number,
                executed_at_transaction: zero_u256(),
                notes,
            };
            world.write_model(@request);

            world.emit_event(@StrkWithdrawn {
                owner: caller,
                amount: amount_strk,
                withdrawal_id,
                block_number,
            });

            amount_strk
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
