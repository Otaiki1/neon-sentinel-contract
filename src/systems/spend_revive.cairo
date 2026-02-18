//! spend_revive system: spend coins to revive during an active run.
//! Cost = 100 * 2^revive_count (1st=100, 2nd=200, 3rd=400, ...). Increments RunState.revive_count.

use core::integer::u256;

#[starknet::interface]
pub trait ISpendRevive<T> {
    fn spend_revive(ref self: T, run_id: u256);
}

#[dojo::contract]
pub mod spend_revive {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::ISpendRevive;
    use neon_sentinel::coin_shop_config::REVIVE_BASE_COINS;
    use neon_sentinel::models::{Player, PlayerProfile, RunState};

    /// 2^n for n in 0..=24 (fits u32).
    fn pow2_u32(n: u32) -> u32 {
        let mut res: u32 = 1;
        let mut i: u32 = 0;
        loop {
            if i >= n {
                break;
            }
            res = res * 2;
            i += 1;
        }
        res
    }

    /// Append transaction to log hash chain (same as spend_coins).
    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 { low: prev.low + bl + am, high: prev.high + 1 }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct RevivePurchased {
        #[key]
        pub player: ContractAddress,
        pub run_id: u256,
        pub revive_count_after: u32,
        pub cost: u32,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl SpendReviveImpl of ISpendRevive<ContractState> {
        fn spend_revive(ref self: ContractState, run_id: u256) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1. Player must have active run with this run_id
            let player: Player = world.read_model(caller);
            assert(player.is_active, 'Run not active');
            assert(
                player.run_id.low == run_id.low && player.run_id.high == run_id.high,
                'Run id mismatch',
            );

            // 2. Load RunState and assert run not finished
            let mut run_state: RunState = world.read_model((caller, run_id));
            assert(!run_state.is_finished, 'Run already finished');

            // 3. Cost = REVIVE_BASE_COINS * 2^revive_count
            let cost = REVIVE_BASE_COINS * pow2_u32(run_state.revive_count);

            // 4. Profile: sufficient coins
            let mut profile: PlayerProfile = world.read_model(caller);
            assert(profile.coins >= cost, 'Insufficient coins');

            // 5. Deduct coins and update log
            profile.coins -= cost;
            profile.coin_transaction_log_hash =
                next_coin_log_hash(profile.coin_transaction_log_hash, block_number, cost);
            profile.coin_transaction_count += 1;

            // 6. Increment revive count for this run
            run_state.revive_count += 1;

            world.write_model(@profile);
            world.write_model(@run_state);

            world.emit_event(@RevivePurchased {
                player: caller,
                run_id,
                revive_count_after: run_state.revive_count,
                cost,
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
