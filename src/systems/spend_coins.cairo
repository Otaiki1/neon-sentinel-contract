//! spend_coins system: allows players to spend coins on upgrades (or other reasons).
//! Records transaction in coin history and emits event; used by init_game for pregame upgrades.

#[starknet::interface]
pub trait ISpendCoins<T> {
    fn spend_coins(ref self: T, amount: u32, reason: felt252) -> bool;
}

#[dojo::contract]
pub mod spend_coins {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::ISpendCoins;
    use neon_sentinel::models::PlayerProfile;

    /// Append transaction to log hash chain (deterministic; same as claim_coins).
    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 {
            low: prev.low + bl + am,
            high: prev.high + 1,
        }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CoinSpent {
        #[key]
        pub player: ContractAddress,
        pub amount: u32,
        pub reason: felt252,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl SpendCoinsImpl of ISpendCoins<ContractState> {
        fn spend_coins(ref self: ContractState, amount: u32, reason: felt252) -> bool {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1. Validate amount > 0
            assert(amount > 0, 'Amount must be positive');

            // 2. Get profile and check sufficient coins
            let mut profile: PlayerProfile = world.read_model(caller);
            assert(profile.coins >= amount, 'Insufficient coins');

            // 3. Deduct coins from balance
            profile.coins -= amount;

            // 4. Record transaction in history (log hash chain)
            profile.coin_transaction_log_hash =
                next_coin_log_hash(profile.coin_transaction_log_hash, block_number, amount);

            // 5. Increment transaction count
            profile.coin_transaction_count += 1;

            // 6. Persist
            world.write_model(@profile);

            // 7. Emit event for logging
            world.emit_event(@CoinSpent {
                player: caller,
                amount,
                reason,
                block_number,
            });

            true
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
