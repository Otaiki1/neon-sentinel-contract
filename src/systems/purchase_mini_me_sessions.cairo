//! purchase_mini_me_sessions: spend 100 coins to add +3 sessions (permanent).
//! Updates PlayerProfile.mini_me_sessions_purchased.

use core::integer::u256;

#[starknet::interface]
pub trait IPurchaseMiniMeSessions<T> {
    fn purchase_mini_me_sessions(ref self: T);
}

#[dojo::contract]
pub mod purchase_mini_me_sessions {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::IPurchaseMiniMeSessions;
    use neon_sentinel::coin_shop_config::PRICE_MINI_ME_SESSIONS_PACK;
    use neon_sentinel::models::PlayerProfile;

    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 { low: prev.low + bl + am, high: prev.high + 1 }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct MiniMeSessionsPurchased {
        #[key]
        pub player: ContractAddress,
        pub sessions_purchased_after: u32,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl PurchaseMiniMeSessionsImpl of IPurchaseMiniMeSessions<ContractState> {
        fn purchase_mini_me_sessions(ref self: ContractState) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            let mut profile: PlayerProfile = world.read_model(caller);
            assert(profile.coins >= PRICE_MINI_ME_SESSIONS_PACK, 'Insufficient coins');

            profile.coins -= PRICE_MINI_ME_SESSIONS_PACK;
            profile.mini_me_sessions_purchased += 1;
            profile.coin_transaction_log_hash = next_coin_log_hash(
                profile.coin_transaction_log_hash,
                block_number,
                PRICE_MINI_ME_SESSIONS_PACK,
            );
            profile.coin_transaction_count += 1;

            world.write_model(@profile);

            world.emit_event(@MiniMeSessionsPurchased {
                player: caller,
                sessions_purchased_after: profile.mini_me_sessions_purchased,
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
