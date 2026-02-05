//! execute_tick system: deterministic main game loop.
//! Validates run, signature (placeholder), sequential tick, forward block;
//! updates player and enemies, collisions, persists GameTick and anti-cheat.

use core::integer::u256;

/// Direction: idle, left, right, up, down (low 3 bits of player_input).
const DIR_IDLE: u8 = 0;
const DIR_LEFT: u8 = 1;
const DIR_RIGHT: u8 = 2;
const DIR_UP: u8 = 3;
const DIR_DOWN: u8 = 4;

/// Action: none, shoot, overclock, shock_bomb, god_mode (high 5 bits).
const ACTION_NONE: u8 = 0;
const ACTION_SHOOT: u8 = 1;
const ACTION_OVERCLOCK: u8 = 2;
const ACTION_SHOCK_BOMB: u8 = 3;
const ACTION_GOD_MODE: u8 = 4;

const WORLD_MAX_X: u32 = 1000;
const WORLD_MAX_Y: u32 = 1000;
const COLLISION_RADIUS: u32 = 8;
const DAMAGE_PER_HIT: u8 = 1;
const CORRUPTION_RATE: u32 = 1;
const CORRUPTION_CAP: u32 = 100;
const METER_CHARGE_RATE: u32 = 2;
const MAX_ENEMIES_PER_TICK: u32 = 32;
const SHOOT_RANGE: u32 = 50;
const COMBO_ONE: u32 = 1000;

#[starknet::interface]
pub trait IExecuteTick<T> {
    fn execute_tick(
        ref self: T,
        run_id: u256,
        player_input: u8,
        sig_r: u256,
        sig_s: u256,
        enemy_ids: Array<u256>,
    );
}

#[dojo::contract]
pub mod execute_tick {
    use core::integer::u256;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::{
        ACTION_GOD_MODE, ACTION_OVERCLOCK, ACTION_SHOOT, ACTION_SHOCK_BOMB,
        COLLISION_RADIUS, CORRUPTION_CAP, CORRUPTION_RATE, DAMAGE_PER_HIT,
        DIR_DOWN, DIR_LEFT, DIR_RIGHT, DIR_UP, MAX_ENEMIES_PER_TICK, METER_CHARGE_RATE,
        WORLD_MAX_X, WORLD_MAX_Y,
    };
    use super::IExecuteTick;
    use neon_sentinel::models::{Enemy, GameTick, Player, RunState};

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    /// Placeholder: store message hash for replay. ECDSA verification deferred until public key storage.
    fn message_hash_for_tick(
        run_id: u256,
        tick_number: u32,
        player_input: u8,
        caller: ContractAddress,
    ) -> u256 {
        // Store run_id as placeholder; full poseidon(run_id, tick, input, caller) when needed.
        run_id
    }

    const TWO_32: u128 = 4294967296;
    const TWO_64: u128 = 18446744073709551616;

    /// State hash placeholder (deterministic from key state fields).
    fn state_hash_placeholder(player: Player, run_state: RunState) -> u256 {
        let px: u128 = player.x.try_into().unwrap();
        let py: u128 = player.y.try_into().unwrap();
        let sc: u128 = run_state.score.try_into().unwrap();
        let tc: u128 = run_state.total_ticks_processed.try_into().unwrap();
        let cl: u128 = run_state.corruption_level.try_into().unwrap();
        let low = px + py * TWO_32 + sc * TWO_64;
        let high = tc + cl * TWO_32;
        u256 { low, high }
    }

    #[abi(embed_v0)]
    impl ExecuteTickImpl of IExecuteTick<ContractState> {
        fn execute_tick(
            ref self: ContractState,
            run_id: u256,
            player_input: u8,
            sig_r: u256,
            sig_s: u256,
            enemy_ids: Array<u256>,
        ) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;
            let block_timestamp = exec_info.block_info.block_timestamp;

            // 1. Run is active
            let mut player: Player = world.read_model(caller);
            assert(player.is_active, 'Run not active');
            assert(player.run_id.low == run_id.low && player.run_id.high == run_id.high, 'Run id mismatch');

            // 2. Run not finished
            let mut run_state: RunState = world.read_model((caller, run_id));
            assert(!run_state.is_finished, 'Run finished');

            // 4. Sequential tick
            let next_tick = run_state.total_ticks_processed + 1;
            assert(player.tick_counter == run_state.total_ticks_processed, 'Tick not sequential');

            // 5. Forward-only block
            assert(block_number > player.last_tick_block, 'Block must increase');

            // 3. Input signature placeholder (store message hash for replay)
            let tick_number = next_tick;
            let input_sig = message_hash_for_tick(run_id, tick_number, player_input, caller);
            // ECDSA verify deferred: assert(sig_r != zero_u256() || sig_s != zero_u256()) or skip

            // 6. State hash before
            let state_hash_before = state_hash_placeholder(player, run_state);
            let combo_before = run_state.combo_multiplier;

            // 7. Extract direction (3 bits) and action (5 bits)
            let direction = player_input & 7;
            let action = player_input / 8;

            // 8. Update player position (deterministic, unsigned)
            if direction == DIR_LEFT && player.x >= 1 {
                player.x -= 1;
            }
            if direction == DIR_RIGHT {
                player.x += 1;
                if player.x > WORLD_MAX_X {
                    player.x = WORLD_MAX_X;
                }
            }
            if direction == DIR_UP && player.y >= 1 {
                player.y -= 1;
            }
            if direction == DIR_DOWN {
                player.y += 1;
                if player.y > WORLD_MAX_Y {
                    player.y = WORLD_MAX_Y;
                }
            }

            let mut score_delta: u64 = 0;
            let mut enemies_killed: u32 = 0;
            let mut damage_taken: u32 = 0;

            // 9. Process action
            if action == ACTION_SHOOT {
                run_state.shots_fired += 1;
            } else if action == ACTION_OVERCLOCK && player.overclock_meter >= 20 {
                player.overclock_meter -= 20;
                player.overclock_active = true;
            } else if action == ACTION_SHOCK_BOMB && player.shock_bomb_meter >= 30 {
                player.shock_bomb_meter -= 30;
            } else if action == ACTION_GOD_MODE && player.god_mode_meter >= 50 {
                player.god_mode_meter -= 50;
                player.god_mode_active = true;
            }

            let god_mode_this_tick = player.god_mode_active;
            let invincible = block_number <= player.invincible_until_block;

            // 10-12. Enemies: validate, update position, collision, damage
            let len = enemy_ids.len();
            assert(len <= MAX_ENEMIES_PER_TICK, 'Too many enemies');
            let mut i: u32 = 0;
            while i < len {
                let enemy_id_snap = enemy_ids[i];
                let enemy_id = u256 { low: *enemy_id_snap.low, high: *enemy_id_snap.high };
                let mut enemy: Enemy = world.read_model(enemy_id);
                assert(enemy.run_id.low == run_id.low && enemy.run_id.high == run_id.high, 'Enemy run mismatch');
                assert(enemy.player_address == caller, 'Enemy player mismatch');
                assert(enemy.is_active, 'Enemy inactive');

                // Deterministic position update: delta 0,1,2 from run_id + tick + index
                let tick_128: u128 = tick_number.try_into().unwrap();
                let idx_128: u128 = i.try_into().unwrap();
                let dx_u128 = (run_id.low + tick_128 + idx_128) % 3;
                let dy_u128 = (run_id.high + tick_128 + idx_128) % 3;
                let dx_u: u32 = dx_u128.try_into().unwrap();
                let dy_u: u32 = dy_u128.try_into().unwrap();
                enemy.x += dx_u;
                enemy.y += dy_u;
                if enemy.x > WORLD_MAX_X {
                    enemy.x = WORLD_MAX_X;
                }
                if enemy.y > WORLD_MAX_Y {
                    enemy.y = WORLD_MAX_Y;
                }
                enemy.last_position_update_block = block_number;

                // 11. Collision with player
                let dx_p = if player.x >= enemy.x { player.x - enemy.x } else { enemy.x - player.x };
                let dy_p = if player.y >= enemy.y { player.y - enemy.y } else { enemy.y - player.y };
                let collided = dx_p <= COLLISION_RADIUS && dy_p <= COLLISION_RADIUS;

                if collided {
                    // 12. Apply damage to player if not invincible and not god mode
                    if !invincible && !god_mode_this_tick {
                        if player.lives >= DAMAGE_PER_HIT {
                            player.lives -= DAMAGE_PER_HIT;
                            damage_taken += 1_u32;
                        } else {
                            let remaining: u32 = player.lives.into();
                            damage_taken += remaining;
                            player.lives = 0;
                        }
                    }
                    // Destroy enemy on contact
                    enemy.is_active = false;
                    enemy.destroyed_at_block = block_number;
                    enemy.destruction_verified = true;
                    run_state.enemies_defeated += 1;
                    score_delta += (enemy.points_value.try_into().unwrap());
                    enemies_killed += 1;
                }

                world.write_model(@enemy);
                i += 1;
            }

            // 13. Corruption
            run_state.corruption_level += CORRUPTION_RATE;
            if run_state.corruption_level > CORRUPTION_CAP {
                run_state.corruption_level = CORRUPTION_CAP;
            }

            // 14. Charge abilities
            player.overclock_meter += METER_CHARGE_RATE;
            player.shock_bomb_meter += METER_CHARGE_RATE;
            player.god_mode_meter += METER_CHARGE_RATE;

            run_state.score += score_delta;
            let combo_after = run_state.combo_multiplier;
            if run_state.shots_fired > 0 {
                run_state.accuracy = (run_state.shots_hit * 1000) / run_state.shots_fired;
            }

            // Game over
            if player.lives == 0 {
                run_state.is_finished = true;
                run_state.final_score = run_state.score;
                run_state.final_layer = run_state.current_layer;
                player.is_active = false;
            }

            // 15. State hash after
            let state_hash_after = state_hash_placeholder(player, run_state);
            let tick_hash = u256 {
                low: state_hash_before.low + state_hash_after.low,
                high: state_hash_before.high + state_hash_after.high,
            };

            // 16. GameTick record
            let game_tick = GameTick {
                player_address: caller,
                run_id,
                tick_number,
                block_number,
                timestamp: block_timestamp,
                player_input,
                input_sig,
                player_x: player.x,
                player_y: player.y,
                score_delta,
                enemies_killed,
                damage_taken,
                combo_before,
                combo_after,
                state_hash_before,
                state_hash_after,
                tick_hash,
            };
            world.write_model(@game_tick);

            // 17. Anti-cheat: update Player and RunState
            player.tick_counter = next_tick;
            player.last_tick_block = block_number;
            run_state.last_tick_block = block_number;
            run_state.total_ticks_processed = next_tick;

            world.write_model(@player);
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
