//! initialize_coin_shop: one-time setup of token purchase config (owner only).

use starknet::ContractAddress;

const MIN_EXCHANGE_RATE: u32 = 3;
const MAX_EXCHANGE_RATE: u32 = 100;
const ZERO_FELT: felt252 = 0;

#[starknet::interface]
pub trait IInitializeCoinShop<T> {
    fn initialize_coin_shop(
        ref self: T,
        strk_token_address: ContractAddress,
        exchange_rate: u32,
    );
}

#[dojo::contract]
pub mod initialize_coin_shop {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::{MAX_EXCHANGE_RATE, MIN_EXCHANGE_RATE, ZERO_FELT};
    use super::IInitializeCoinShop;
    use neon_sentinel::models::{CoinShopGlobal, TokenPurchaseConfig};

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CoinShopInitialized {
        #[key]
        pub owner: ContractAddress,
        pub strk_token_address: ContractAddress,
        pub exchange_rate: u32,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl InitializeCoinShopImpl of IInitializeCoinShop<ContractState> {
        fn initialize_coin_shop(
            ref self: ContractState,
            strk_token_address: ContractAddress,
            exchange_rate: u32,
        ) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1. Not already initialized: read global; if owner set, config must not be inited
            let global: CoinShopGlobal = world.read_model(ZERO_FELT);
            let existing_owner = global.owner;
            if existing_owner != 0.try_into().unwrap() {
                let existing: TokenPurchaseConfig = world.read_model(existing_owner);
                assert(existing.coin_exchange_rate == 0, 'Already initialized');
            }
            // 2. Validate STRK token address is valid (non-zero)
            assert(strk_token_address != 0.try_into().unwrap(), 'Invalid token address');

            // 3. Validate exchange rate is reasonable (3-10 coins per STRK)
            assert(
                exchange_rate >= MIN_EXCHANGE_RATE && exchange_rate <= MAX_EXCHANGE_RATE,
                'Exchange rate out of range',
            );

            // 4. Create global pointer so systems can resolve config
            let coin_shop_global = CoinShopGlobal {
                global_key: ZERO_FELT,
                owner: caller,
            };
            world.write_model(@coin_shop_global);

            // 5. Create TokenPurchaseConfig (owner immutable; treasury tracking)
            let config = TokenPurchaseConfig {
                owner: caller,
                strk_token_address,
                coin_exchange_rate: exchange_rate,
                total_strk_collected: zero_u256(),
                total_strk_withdrawn: zero_u256(),
                total_coins_sold: zero_u256(),
                is_enabled: true,
                paused: false,
                last_updated: block_number,
                collected_strk_version: 0,
                next_withdrawal_id: zero_u256(),
            };
            world.write_model(@config);

            // 6. Emit event for logging
            world.emit_event(@CoinShopInitialized {
                owner: caller,
                strk_token_address,
                exchange_rate,
                block_number,
            });
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
