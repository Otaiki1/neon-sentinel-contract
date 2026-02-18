//! purchase_mini_me_unit: spend coins to add one Mini-Me unit to inventory (type 0..6).
//! Max 20 per type. Prices from coin_shop_config.

use core::integer::u256;

#[starknet::interface]
pub trait IPurchaseMiniMeUnit<T> {
    fn purchase_mini_me_unit(ref self: T, unit_type: u8);
}

#[dojo::contract]
pub mod purchase_mini_me_unit {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::IPurchaseMiniMeUnit;
    use neon_sentinel::coin_shop_config::{
        MAX_MINI_ME_TYPE, MAX_MINI_ME_UNITS_PER_TYPE,
        PRICE_MINI_ME_0, PRICE_MINI_ME_1, PRICE_MINI_ME_2, PRICE_MINI_ME_3,
        PRICE_MINI_ME_4, PRICE_MINI_ME_5, PRICE_MINI_ME_6,
    };
    use neon_sentinel::models::{MiniMeInventory, PlayerProfile};

    fn unit_price(unit_type: u8) -> u32 {
        if unit_type == 0 {
            PRICE_MINI_ME_0
        } else if unit_type == 1 {
            PRICE_MINI_ME_1
        } else if unit_type == 2 {
            PRICE_MINI_ME_2
        } else if unit_type == 3 {
            PRICE_MINI_ME_3
        } else if unit_type == 4 {
            PRICE_MINI_ME_4
        } else if unit_type == 5 {
            PRICE_MINI_ME_5
        } else {
            PRICE_MINI_ME_6
        }
    }

    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 { low: prev.low + bl + am, high: prev.high + 1 }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct MiniMeUnitPurchased {
        #[key]
        pub player: ContractAddress,
        pub unit_type: u8,
        pub count_after: u8,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl PurchaseMiniMeUnitImpl of IPurchaseMiniMeUnit<ContractState> {
        fn purchase_mini_me_unit(ref self: ContractState, unit_type: u8) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            assert(unit_type <= MAX_MINI_ME_TYPE, 'Invalid unit type');

            let price = unit_price(unit_type);
            let mut profile: PlayerProfile = world.read_model(caller);
            assert(profile.coins >= price, 'Insufficient coins');

            let mut inv: MiniMeInventory = world.read_model((caller, unit_type));
            assert(inv.count < MAX_MINI_ME_UNITS_PER_TYPE, 'Max units per type');
            inv.player_address = caller;
            inv.unit_type = unit_type;
            inv.count += 1;

            profile.coins -= price;
            profile.coin_transaction_log_hash =
                next_coin_log_hash(profile.coin_transaction_log_hash, block_number, price);
            profile.coin_transaction_count += 1;

            world.write_model(@profile);
            world.write_model(@inv);

            world.emit_event(@MiniMeUnitPurchased {
                player: caller,
                unit_type,
                count_after: inv.count,
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
