//! end_run system (BALANCED): finalizes a run with client-submitted final state.
//! Client simulates gameplay locally and submits final_score, total_kills, final_layer.
//! Chain accepts these values and updates RunState, Player, PlayerProfile; awards bonus coins if score >= threshold.

use core::integer::u256;

const EVENT_TYPE_GAME_END: u8 = 7;
const LEADERBOARD_MIN_SCORE: u64 = 1000;
const SCORE_BONUS_COINS: u32 = 10;
const MAX_LAYER: u8 = 6;

#[starknet::interface]
pub trait IEndRun<T> {
    fn end_run(
        ref self: T,
        run_id: u256,
        final_score: u64,
        total_kills: u32,
        final_layer: u8,
    );
}

#[dojo::contract]
pub mod end_run {
    use core::integer::u256;
    use dojo::model::ModelStorage;
    use starknet::{get_caller_address, get_execution_info};

    use super::{EVENT_TYPE_GAME_END, LEADERBOARD_MIN_SCORE, MAX_LAYER, SCORE_BONUS_COINS};
    use super::IEndRun;
    use neon_sentinel::models::{GameEvent, Player, PlayerProfile, RankNFT, RunState};
    use neon_sentinel::rank_config::{rank_id_for_milestone, tier_for_rank};

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    /// 2^n for n in 0..=24 (fits u32). Used for prestige coin reward.
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
        fn end_run(
            ref self: ContractState,
            run_id: u256,
            final_score: u64,
            total_kills: u32,
            final_layer: u8,
        ) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1. Validate run exists and player has active run
            let mut player: Player = world.read_model(caller);
            assert(player.is_active, 'Run not active');
            assert(
                player.run_id.low == run_id.low && player.run_id.high == run_id.high,
                'Run id mismatch',
            );

            // 2. Check run is not already finished; validate final_layer range
            let mut run_state: RunState = world.read_model((caller, run_id));
            assert(!run_state.is_finished, 'Already finished');
            assert(final_layer >= 1 && final_layer <= MAX_LAYER, 'Invalid layer');

            // 3. Accept client-submitted final state
            run_state.is_finished = true;
            run_state.last_tick_block = block_number;
            run_state.final_score = final_score;
            run_state.enemies_defeated = total_kills;
            run_state.final_layer = final_layer;
            run_state.submitted_to_leaderboard = false;

            // 4. Mark player as inactive
            player.is_active = false;

            // 5. Update PlayerProfile with final stats
            let mut profile: PlayerProfile = world.read_model(caller);
            profile.total_runs += 1;
            profile.lifetime_enemies_defeated += total_kills;
            profile.lifetime_score += final_score;
            if final_score > profile.best_run_score {
                profile.best_run_score = final_score;
            }
            if final_layer > profile.current_layer {
                profile.current_layer = final_layer;
            }
            if final_score >= LEADERBOARD_MIN_SCORE {
                profile.coins += SCORE_BONUS_COINS;
            }

            // 5a. Prestige coins: clearing layer 6 awards 2 * 2^current_prestige and advances prestige
            if final_layer == MAX_LAYER {
                let prestige_reward = 2 * pow2_u32(run_state.current_prestige.into());
                profile.coins += prestige_reward;
                let new_prestige = run_state.current_prestige + 1;
                profile.current_prestige = new_prestige;
                if new_prestige > profile.highest_prestige_reached {
                    profile.highest_prestige_reached = new_prestige;
                }
                // Reaching P8 and clearing layer 6 grants Prime Sentinel (required for kernel 10)
                if run_state.current_prestige == 8 {
                    profile.is_prime_sentinel = true;
                }
            }

            // 5b. Rank (18 named ranks): update highest_rank_id and mint RankNFT when player first achieves this rank
            let rank_id = rank_id_for_milestone(run_state.current_prestige, final_layer);
            if rank_id > 0 && rank_id > profile.highest_rank_id {
                profile.highest_rank_id = rank_id;
                profile.highest_rank_tier_minted = rank_id;
            }
            if rank_id > 0 {
                let existing: RankNFT = world.read_model((caller, rank_id));
                if existing.achieved_at_block == 0 {
                    let rank_tier_display = tier_for_rank(rank_id);
                    let rank_128: u128 = rank_id.try_into().unwrap();
                    let token_id = u256 {
                        low: rank_128 + run_id.low * 256,
                        high: run_id.high,
                    };
                    let rank_nft = RankNFT {
                        owner: caller,
                        rank_id,
                        rank_tier: rank_tier_display,
                        prestige: run_state.current_prestige,
                        layer: final_layer,
                        achieved_at_block: block_number,
                        run_id,
                        token_id,
                    };
                    world.write_model(@rank_nft);
                }
            }

            // 6. Emit GameEvent for game over
            let event_id = game_end_event_id(run_id, block_number);
            let data_primary = u256 { low: final_score.try_into().unwrap(), high: 0 };
            let game_end_event = GameEvent {
                event_id,
                run_id,
                player_address: caller,
                event_type: EVENT_TYPE_GAME_END,
                tick_number: 0,
                block_number,
                entity_id: zero_u256(),
                data_primary,
                data_secondary: zero_u256(),
                game_state_hash_before: zero_u256(),
                game_state_hash_after: zero_u256(),
                verified: false,
            };
            world.write_model(@game_end_event);

            world.write_model(@run_state);
            world.write_model(@player);
            world.write_model(@profile);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
