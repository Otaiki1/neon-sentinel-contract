//! end_run system: finalizes a run and makes it immutable.
//! Once is_finished = true, score and run state cannot be modified.

use core::integer::u256;

const EVENT_TYPE_GAME_END: u8 = 7;

#[starknet::interface]
pub trait IEndRun<T> {
    fn end_run(ref self: T, run_id: u256);
}

#[dojo::contract]
pub mod end_run {
    use core::integer::u256;
    use dojo::model::ModelStorage;
    use starknet::{get_caller_address, get_execution_info};

    use super::EVENT_TYPE_GAME_END;
    use super::IEndRun;
    use neon_sentinel::models::{GameEvent, Player, RunState};

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    const TWO_32: u128 = 4294967296;
    const TWO_64: u128 = 18446744073709551616;

    /// Deterministic state hash for finalized run (for replay/verification).
    fn state_hash_for_run(run_state: RunState) -> u256 {
        let sc: u128 = run_state.score.try_into().unwrap();
        let tc: u128 = run_state.total_ticks_processed.try_into().unwrap();
        let cl: u128 = run_state.corruption_level.try_into().unwrap();
        let fl: u128 = run_state.final_layer.try_into().unwrap();
        let low = sc + fl * TWO_32;
        let high = tc + cl * TWO_32;
        u256 { low, high }
    }

    /// Unique event_id for game_end (deterministic from run_id and block).
    fn game_end_event_id(run_id: u256, block_number: u64) -> u256 {
        let block_128: u128 = block_number.try_into().unwrap();
        u256 {
            low: run_id.low + block_128 + (EVENT_TYPE_GAME_END.into()),
            high: run_id.high,
        }
    }

    #[abi(embed_v0)]
    impl EndRunImpl of IEndRun<ContractState> {
        fn end_run(ref self: ContractState, run_id: u256) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1. Validate run exists and player has active run
            let mut player: Player = world.read_model(caller);
            assert(player.is_active, 'No active run');
            assert(
                player.run_id.low == run_id.low && player.run_id.high == run_id.high,
                'Run id mismatch',
            );

            // 2. Check run is not already finished
            let mut run_state: RunState = world.read_model((caller, run_id));
            assert(!run_state.is_finished, 'Run already finished');

            // 3. Mark is_finished = true (IMMUTABLE LOCK)
            run_state.is_finished = true;

            // 4. Set last_tick_block = current block (records when run ended)
            run_state.last_tick_block = block_number;

            // 5-6. Lock final_score and final_layer
            run_state.final_score = run_state.score;
            run_state.final_layer = run_state.current_layer;

            // 7. Calculate state_hash (stored in GameEvent below)
            let state_hash = state_hash_for_run(run_state);

            // 8. event_log_hash: placeholder (no event list to hash on-chain)
            let event_log_hash = zero_u256();

            // 9. Set submitted_to_leaderboard = false
            run_state.submitted_to_leaderboard = false;

            // 10. Mark player as inactive
            player.is_active = false;

            // 11. Emit GameEvent for game over
            let event_id = game_end_event_id(run_id, block_number);
            let data_primary = u256 { low: run_state.score.try_into().unwrap(), high: 0 };
            let data_secondary = event_log_hash;
            let game_end_event = GameEvent {
                event_id,
                run_id,
                player_address: caller,
                event_type: EVENT_TYPE_GAME_END,
                tick_number: run_state.total_ticks_processed,
                block_number,
                entity_id: zero_u256(),
                data_primary,
                data_secondary,
                game_state_hash_before: zero_u256(),
                game_state_hash_after: state_hash,
                verified: false,
            };
            world.write_model(@game_end_event);

            world.write_model(@run_state);
            world.write_model(@player);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
