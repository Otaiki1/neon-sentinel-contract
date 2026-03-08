//! enemy_manager system: handles on-chain enemy generation and spawning.
//! Updates the Phase 2 `Enemy` model.
//! Includes procedural spawning logic based on layer and prestige.

use core::integer::u256;
// use starknet::ContractAddress;

#[starknet::interface]
pub trait IEnemyManager<T> {
    /// Spawn enemies for the current run.
    /// tick_number: proof of the current tick context.
    fn spawn_enemies(ref self: T, run_id: u256, tick_number: u32, layer: u8, prestige: u8);
    
    /// Update existing enemies (move towards player, check health).
    fn update_enemies(ref self: T, run_id: u256, player_x: u32, player_y: u32);
}

#[dojo::contract]
pub mod enemy_manager {
    // use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use neon_sentinel::models::{Enemy};
    use starknet::{get_caller_address, get_execution_info};
    use super::IEnemyManager;

    const MAP_WIDTH: u32 = 1000;
    const MAP_HEIGHT: u32 = 1000;
    const ENEMY_SPEED: u32 = 5;

    #[abi(embed_v0)]
    impl EnemyManagerImpl of IEnemyManager<ContractState> {
        fn spawn_enemies(ref self: ContractState, run_id: u256, tick_number: u32, layer: u8, prestige: u8) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;
            let block_timestamp = exec_info.block_info.block_timestamp;

            // Compute deterministic enemy_id from run_id, tick, and position
            // Simple procedural logic for demonstration.
            let mut i: u256 = 0;
            loop {
                if i >= 3 { break; } // Spawn 3 enemies per call

                let enemy_id = u256 { low: run_id.low + tick_number.into() + i.low, high: run_id.high };
                
                // Deterministic positions based on block timestamp
                let spawn_x: u32 = (block_timestamp.try_into().unwrap() + i.low.try_into().unwrap() * 100) % MAP_WIDTH;
                let spawn_y: u32 = (block_timestamp.try_into().unwrap() + i.low.try_into().unwrap() * 50) % MAP_HEIGHT;

                let enemy = Enemy {
                    enemy_id,
                    run_id,
                    player_address: caller,
                    enemy_type: 1, // Standard drone
                    health: 10 + layer.into() * 2 + prestige.into() * 5,
                    max_health: 10 + layer.into() * 2 + prestige.into() * 5,
                    speed: ENEMY_SPEED + prestige.into(),
                    points_value: 100 + layer.into() * 10,
                    x: spawn_x,
                    y: spawn_y,
                    spawn_block: block_number,
                    last_position_update_block: block_number,
                    is_active: true,
                    destroyed_at_block: 0,
                    destruction_verified: false,
                };

                world.write_model(@enemy);
                i += 1;
            };
        }

        fn update_enemies(ref self: ContractState, run_id: u256, player_x: u32, player_y: u32) {
            // This would fetch all active enemies for the run and update their positions.
            // Dojo currently doesn't support easy querying of all models of a type filtered by a key easily in systems
            // without a specific index. 
            // In a real robust system, we would maintain a list of active enemy_ids per run.
            // For now, this serves as a placeholder for where that logic would reside.
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
