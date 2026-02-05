//! hit_registration system: registers when a player's bullet hits an enemy.
//! Validates position (anti-spoof), distance, applies kernel/upgrade damage, updates combo and events.

use core::integer::u256;

const MAX_HIT_RANGE: u32 = 50;
const MAX_HIT_RANGE_SQ: u64 = 2500; // MAX_HIT_RANGE * MAX_HIT_RANGE
const COMBO_STEP: u32 = 50;
const COMBO_MAX: u32 = 5000;
const UPGRADE_DAMAGE_MOD: u32 = 1000; // 1.0x placeholder
const EVENT_TYPE_HIT: u8 = 1;
const EVENT_TYPE_POWERUP: u8 = 2;
const EVENT_TYPE_LAYER: u8 = 3;
const MAX_LAYER: u8 = 6;

// Layer score thresholds (score >= this to advance to next layer).
const LAYER_2_SCORE: u64 = 1000;
const LAYER_3_SCORE: u64 = 5000;
const LAYER_4_SCORE: u64 = 15000;
const LAYER_5_SCORE: u64 = 40000;
const LAYER_6_SCORE: u64 = 100000;

#[starknet::interface]
pub trait IHitRegistration<T> {
    fn hit_registration(
        ref self: T,
        run_id: u256,
        enemy_id: u256,
        damage: u32,
        player_x: u32,
        player_y: u32,
        hit_proof: u256,
    );
}

#[dojo::contract]
pub mod hit_registration {
    use core::integer::u256;
    use dojo::model::ModelStorage;
    use starknet::{get_caller_address, get_execution_info};

    use super::{
        COMBO_MAX, COMBO_STEP, EVENT_TYPE_HIT, EVENT_TYPE_LAYER, EVENT_TYPE_POWERUP,
        LAYER_2_SCORE, LAYER_3_SCORE, LAYER_4_SCORE, LAYER_5_SCORE, LAYER_6_SCORE,
        MAX_HIT_RANGE_SQ, MAX_LAYER, UPGRADE_DAMAGE_MOD,
    };
    use super::IHitRegistration;
    use neon_sentinel::models::{Enemy, GameEvent, Player, RunState};

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    /// Absolute difference for u32 (for distance components).
    fn abs_diff_u32(a: u32, b: u32) -> u32 {
        if a >= b {
            a - b
        } else {
            b - a
        }
    }

    /// Kernel damage modifier (1000 = 1.0x). Kernel 0-5 -> 1000, 1050, 1100, ...
    fn kernel_damage_mod(kernel: u8) -> u32 {
        if kernel > 5 {
            return 1000_u32;
        }
        let k: u32 = kernel.into();
        1000_u32 + k * 50_u32
    }

    /// Score threshold for advancing to layer (1-based). Layer 1->2 needs LAYER_2_SCORE, etc.
    fn layer_threshold(layer: u8) -> u64 {
        match layer {
            1 => LAYER_2_SCORE,
            2 => LAYER_3_SCORE,
            3 => LAYER_4_SCORE,
            4 => LAYER_5_SCORE,
            5 => LAYER_6_SCORE,
            _ => 0,
        }
    }

    /// Unique event_id for hit/powerup/layer events (deterministic from run, enemy, block, type).
    fn event_id_for(run_id: u256, enemy_id: u256, block_number: u64, event_type: u8) -> u256 {
        let block_128: u128 = block_number.try_into().unwrap();
        let et_128: u128 = event_type.try_into().unwrap();
        let low = run_id.low + enemy_id.low + block_128 + et_128;
        let high = run_id.high + enemy_id.high;
        u256 { low, high }
    }

    #[abi(embed_v0)]
    impl HitRegistrationImpl of IHitRegistration<ContractState> {
        fn hit_registration(
            ref self: ContractState,
            run_id: u256,
            enemy_id: u256,
            damage: u32,
            player_x: u32,
            player_y: u32,
            hit_proof: u256,
        ) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1-2. Run active and not finished
            let player: Player = world.read_model(caller);
            assert(player.is_active, 'Run not active');
            assert(player.run_id.low == run_id.low && player.run_id.high == run_id.high, 'Run id mismatch');

            let mut run_state: RunState = world.read_model((caller, run_id));
            assert(!run_state.is_finished, 'Run finished');

            // 3. Enemy exists and active
            let mut enemy: Enemy = world.read_model(enemy_id);
            assert(enemy.run_id.low == run_id.low && enemy.run_id.high == run_id.high, 'Enemy run mismatch');
            assert(enemy.player_address == caller, 'Enemy player mismatch');
            assert(enemy.is_active, 'Enemy inactive');

            // Position verification (SECURITY: anti-spoof)
            assert(player.x == player_x && player.y == player_y, 'Position mismatch');

            // 5-6. Distance on-chain and in range
            let dx: u32 = abs_diff_u32(player_x, enemy.x);
            let dy: u32 = abs_diff_u32(player_y, enemy.y);
            let dx64: u64 = dx.into();
            let dy64: u64 = dy.into();
            let distance_sq = dx64 * dx64 + dy64 * dy64;
            assert(distance_sq <= MAX_HIT_RANGE_SQ, 'Out of range');

            // 7-8. Kernel and upgrade damage modifiers (u64 to avoid u32 overflow)
            let kernel_mod = kernel_damage_mod(player.kernel);
            let d64: u64 = damage.into();
            let k64: u64 = kernel_mod.into();
            let up_mod: u64 = UPGRADE_DAMAGE_MOD.into();
            let effective_damage_u64 = (d64 * k64 * up_mod) / 1000_u64 / 1000_u64;
            let effective_damage: u32 = if effective_damage_u64 >= 4294967295_u64 {
                4294967295_u32
            } else {
                effective_damage_u64.try_into().unwrap()
            };

            // 9. Reduce enemy health
            if effective_damage >= enemy.health {
                enemy.health = 0;
            } else {
                enemy.health -= effective_damage;
            }
            enemy.last_position_update_block = block_number;

            // 10. Increment shots_hit
            run_state.shots_hit += 1;

            // 11. If enemy dies
            if enemy.health == 0 {
                enemy.is_active = false;
                enemy.destroyed_at_block = block_number;
                enemy.destruction_verified = true;

                let points_u64: u64 = (enemy.points_value * run_state.combo_multiplier).into();
                let points_awarded = points_u64 / 1000_u64;
                run_state.score += points_awarded;

                run_state.combo_multiplier += COMBO_STEP;
                if run_state.combo_multiplier > COMBO_MAX {
                    run_state.combo_multiplier = COMBO_MAX;
                }
                run_state.enemies_defeated += 1;

                let ev_id = event_id_for(run_id, enemy_id, block_number, EVENT_TYPE_HIT);
                let data_primary: u256 = u256 { low: (effective_damage.into()), high: 0 };
                let data_secondary: u256 = u256 { low: (run_state.combo_multiplier.into()), high: 0 };
                let hit_event = GameEvent {
                    event_id: ev_id,
                    run_id,
                    player_address: caller,
                    event_type: EVENT_TYPE_HIT,
                    tick_number: run_state.total_ticks_processed,
                    block_number,
                    entity_id: enemy_id,
                    data_primary,
                    data_secondary: data_secondary,
                    game_state_hash_before: zero_u256(),
                    game_state_hash_after: zero_u256(),
                    verified: false,
                };
                world.write_model(@hit_event);

                // 12. Power-up drop (deterministic)
                let powerup_roll = (run_id.low + enemy_id.low) % 10;
                if powerup_roll == 0 {
                    let pu_ev_id = event_id_for(run_id, enemy_id, block_number, EVENT_TYPE_POWERUP);
                    let pu_event = GameEvent {
                        event_id: pu_ev_id,
                        run_id,
                        player_address: caller,
                        event_type: EVENT_TYPE_POWERUP,
                        tick_number: run_state.total_ticks_processed,
                        block_number,
                        entity_id: enemy_id,
                        data_primary: zero_u256(),
                        data_secondary: zero_u256(),
                        game_state_hash_before: zero_u256(),
                        game_state_hash_after: zero_u256(),
                        verified: false,
                    };
                    world.write_model(@pu_event);
                }

                // 13. Layer advancement
                if run_state.current_layer < MAX_LAYER {
                    let next_layer = run_state.current_layer + 1;
                    let threshold = layer_threshold(run_state.current_layer);
                    if run_state.score >= threshold {
                        run_state.current_layer = next_layer;
                        let layer_ev_id =
                            event_id_for(run_id, enemy_id, block_number, EVENT_TYPE_LAYER);
                        let layer_data: u256 =
                            u256 { low: (next_layer.into()), high: 0 };
                        let layer_event = GameEvent {
                            event_id: layer_ev_id,
                            run_id,
                            player_address: caller,
                            event_type: EVENT_TYPE_LAYER,
                            tick_number: run_state.total_ticks_processed,
                            block_number,
                            entity_id: zero_u256(),
                            data_primary: layer_data,
                            data_secondary: zero_u256(),
                            game_state_hash_before: zero_u256(),
                            game_state_hash_after: zero_u256(),
                            verified: false,
                        };
                        world.write_model(@layer_event);
                    }
                }
            }

            if run_state.shots_fired > 0 {
                run_state.accuracy = (run_state.shots_hit * 1000) / run_state.shots_fired;
            }

            world.write_model(@enemy);
            world.write_model(@run_state);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
