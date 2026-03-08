//! game_tick system: robust coordinator for full on-chain game simulation.
//! Orchestrates player movement, enemy spawning/updating, and collision detection.
//! Acts as the "master" entry point for processing a game tick on-chain.

use core::integer::u256;
use neon_sentinel::models::Direction;

#[starknet::interface]
pub trait IGameTick<T> {
    /// Advance the game state by one or more ticks.
    /// tick_number: number of the current tick being processed.
    /// player_input: encoded player actions (move, shoot, etc.).
    /// state_proof: placeholder for ZK state transition proof (if ever needed).
    fn process_tick(ref self: T, tick_number: u32, player_input: Direction, ability_id: u8, state_proof: u256);
}

#[dojo::contract]
pub mod game_tick {
    use dojo::model::ModelStorage;
    use neon_sentinel::models::{Direction, Player, RunState};
    use neon_sentinel::systems::player_movement::{IPlayerMovementDispatcher, IPlayerMovementDispatcherTrait};
    use neon_sentinel::systems::enemy_manager::{IEnemyManagerDispatcher, IEnemyManagerDispatcherTrait};
    use dojo::world::WorldStorageTrait;
    use starknet::{get_caller_address, get_execution_info};
    use super::IGameTick;

    #[abi(embed_v0)]
    impl GameTickImpl of IGameTick<ContractState> {
        fn process_tick(ref self: ContractState, tick_number: u32, player_input: Direction, ability_id: u8, state_proof: u256) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let mut player: Player = world.read_model(caller);
            let mut run_state: RunState = world.read_model((caller, player.run_id));

            assert(player.is_active, 'Player not active');
            assert(!run_state.is_finished, 'Run already finished');

            // 1. Move player
            let (movement_addr, _) = world.dns(@"player_movement").expect('player_movement not found');
            let movement = IPlayerMovementDispatcher { contract_address: movement_addr };
            movement.move_player(player_input, tick_number, state_proof);

            // 2. Use ability if requested
            if ability_id > 0 {
                movement.use_ability(ability_id);
            }

            // 3. Spawn enemies every 10 ticks
            if tick_number % 10 == 0 {
                let (enemy_addr, _) = world.dns(@"enemy_manager").expect('enemy_manager not found');
                let enemy_manager = IEnemyManagerDispatcher { contract_address: enemy_addr };
                enemy_manager.spawn_enemies(player.run_id, tick_number, run_state.current_layer, run_state.current_prestige);
            }

            // 4. Update core simulation metadata
            let block_number = get_execution_info().block_info.block_number;
            run_state.last_tick_block = block_number;
            run_state.total_ticks_processed = tick_number;
            
            world.write_model(@run_state);

            // Optional: Collision detection and score updates would follow here.
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
