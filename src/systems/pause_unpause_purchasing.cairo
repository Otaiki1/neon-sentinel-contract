//! pause_unpause_purchasing: owner toggles paused flag (fast emergency stop).

use starknet::ContractAddress;

const ZERO_FELT: felt252 = 0;

#[starknet::interface]
pub trait IPauseUnpausePurchasing<T> {
    fn pause_unpause_purchasing(ref self: T) -> bool;
}

#[dojo::contract]
pub mod pause_unpause_purchasing {
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::IPauseUnpausePurchasing;
    use super::ZERO_FELT;
    use neon_sentinel::models::{CoinShopGlobal, TokenPurchaseConfig};
    use neon_sentinel::owner_access::IsOwnerTrait;

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct PurchasingPauseToggled {
        #[key]
        pub owner: ContractAddress,
        pub paused: bool,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl PauseUnpausePurchasingImpl of IPauseUnpausePurchasing<ContractState> {
        fn pause_unpause_purchasing(ref self: ContractState) -> bool {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            let global: CoinShopGlobal = world.read_model(ZERO_FELT);
            assert(IsOwnerTrait::is_owner(caller, global.owner), 'Not owner');

            let mut config: TokenPurchaseConfig = world.read_model(global.owner);
            config.paused = if config.paused { false } else { true };
            config.last_updated = block_number;
            world.write_model(@config);

            world.emit_event(@PurchasingPauseToggled {
                owner: caller,
                paused: config.paused,
                block_number,
            });

            config.paused
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
