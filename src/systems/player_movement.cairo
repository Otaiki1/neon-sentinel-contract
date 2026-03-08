//! player_movement system: handles on-chain player movement and actions.
//! Updates the Phase 2 `Player` model.
//! Includes boundary checks, tick validation, and input processing.

use neon_sentinel::models::Direction;
use core::integer::u256;

#[starknet::interface]
pub trait IPlayerMovement<T> {
    /// Move the player in a given direction.
    /// tick_hash: proof of the current tick state (placeholder for future replay verification).
    fn move_player(ref self: T, direction: Direction, tick_number: u32, tick_hash: u256);
    
    /// Trigger an ability (overclock, shock bomb, god mode).
    fn use_ability(ref self: T, ability_id: u8);
}

#[dojo::contract]
pub mod player_movement {
    // use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use neon_sentinel::models::{Direction, Player};
    use starknet::{get_caller_address, get_execution_info};
    use super::IPlayerMovement;

    const MAP_WIDTH: u32 = 1000;
    const MAP_HEIGHT: u32 = 1000;
    const PLAYER_SPEED: u32 = 10;

    #[abi(embed_v0)]
    impl PlayerMovementImpl of IPlayerMovement<ContractState> {
        fn move_player(ref self: ContractState, direction: Direction, tick_number: u32, tick_hash: u256) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let mut player: Player = world.read_model(caller);

            // 1. Validation
            assert(player.is_active, 'Player not active');
            assert(tick_number > player.tick_counter, 'Stale tick');
            
            // 2. Process movement
            let mut new_x = player.x;
            let mut new_y = player.y;

            match direction {
                Direction::Left => {
                    if new_x >= PLAYER_SPEED { new_x -= PLAYER_SPEED; }
                    else { new_x = 0; }
                },
                Direction::Right => {
                    new_x += PLAYER_SPEED;
                    if new_x > MAP_WIDTH { new_x = MAP_WIDTH; }
                },
                Direction::Up => {
                    if new_y >= PLAYER_SPEED { new_y -= PLAYER_SPEED; }
                    else { new_y = 0; }
                },
                Direction::Down => {
                    new_y += PLAYER_SPEED;
                    if new_y > MAP_HEIGHT { new_y = MAP_HEIGHT; }
                },
            };

            // 3. Update state
            player.x = new_x;
            player.y = new_y;
            player.tick_counter = tick_number;
            let block_number = get_execution_info().block_info.block_number;
            player.last_tick_block = block_number;

            world.write_model(@player);
            
            // Optional: Log tick event (if needed for robust auditing)
            // world.emit_event(...)
        }

        fn use_ability(ref self: ContractState, ability_id: u8) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let mut player: Player = world.read_model(caller);

            assert(player.is_active, 'Player not active');

            if ability_id == 1 { // Overclock
                assert(player.overclock_meter >= 100, 'Overclock not charged');
                player.overclock_active = true;
                player.overclock_meter = 0;
            } else if ability_id == 2 { // Shock Bomb
                assert(player.shock_bomb_meter >= 100, 'Shock Bomb not charged');
                player.shock_bomb_meter = 0;
                // logic for shock bomb would go here (destroy local enemies)
            } else if ability_id == 3 { // God Mode
                assert(player.god_mode_meter >= 100, 'God Mode not charged');
                player.god_mode_active = true;
                player.god_mode_meter = 0;
            }

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
