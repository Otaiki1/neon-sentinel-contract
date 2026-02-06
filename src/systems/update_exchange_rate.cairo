//! update_exchange_rate: owner updates coins-per-STRK rate (bounded change for safety).

use starknet::ContractAddress;

const MIN_EXCHANGE_RATE: u32 = 3;
const MAX_EXCHANGE_RATE: u32 = 10;
/// Max 20% change per update (rate * 20 / 100).
const MAX_RATE_CHANGE_PERCENT: u32 = 20;
const ZERO_FELT: felt252 = 0;

#[starknet::interface]
pub trait IUpdateExchangeRate<T> {
    fn update_exchange_rate(ref self: T, new_exchange_rate: u32);
}

#[dojo::contract]
pub mod update_exchange_rate {
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::{MAX_EXCHANGE_RATE, MAX_RATE_CHANGE_PERCENT, MIN_EXCHANGE_RATE, ZERO_FELT};
    use super::IUpdateExchangeRate;
    use neon_sentinel::models::{CoinShopGlobal, TokenPurchaseConfig};

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct ExchangeRateUpdated {
        #[key]
        pub owner: ContractAddress,
        pub old_rate: u32,
        pub new_rate: u32,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl UpdateExchangeRateImpl of IUpdateExchangeRate<ContractState> {
        fn update_exchange_rate(ref self: ContractState, new_exchange_rate: u32) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            let global: CoinShopGlobal = world.read_model(ZERO_FELT);
            assert(caller == global.owner, 'Not owner');

            let mut config: TokenPurchaseConfig = world.read_model(global.owner);

            assert(
                new_exchange_rate >= MIN_EXCHANGE_RATE && new_exchange_rate <= MAX_EXCHANGE_RATE,
                'Rate out of range',
            );

            let old_rate = config.coin_exchange_rate;
            if old_rate > 0 {
                let diff = if new_exchange_rate > old_rate {
                    new_exchange_rate - old_rate
                } else {
                    old_rate - new_exchange_rate
                };
                let max_allowed = old_rate * MAX_RATE_CHANGE_PERCENT / 100;
                if max_allowed < 1 {
                    assert(diff <= 1, 'Rate change too large');
                } else {
                    assert(diff <= max_allowed, 'Rate change too large');
                }
            }

            config.coin_exchange_rate = new_exchange_rate;
            config.last_updated = block_number;
            world.write_model(@config);

            world.emit_event(@ExchangeRateUpdated {
                owner: caller,
                old_rate,
                new_rate: new_exchange_rate,
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
