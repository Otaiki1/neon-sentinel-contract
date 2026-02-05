use core::integer::u256;
use starknet::ContractAddress;

// ============== Starter models (kept for existing systems/tests) ==============

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Moves {
    #[key]
    pub player: ContractAddress,
    pub remaining: u8,
    pub last_direction: Option<Direction>,
    pub can_move: bool,
}

#[derive(Drop, Serde, Debug)]
#[dojo::model]
pub struct DirectionsAvailable {
    #[key]
    pub player: ContractAddress,
    pub directions: Array<Direction>,
}

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Position {
    #[key]
    pub player: ContractAddress,
    pub vec: Vec2,
}

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct PositionCount {
    #[key]
    pub identity: ContractAddress,
    pub position: Span<(u8, u128)>,
}

// ============== Neon Sentinel models (Phase 2) ==============

/// Player state. SECURITY: invincible_until_block, tick_counter, last_tick_block are
/// block-based anti-cheat; upgrades_verified locks upgrades after game start.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Player {
    #[key]
    pub player_address: ContractAddress,
    pub run_id: u256,
    pub is_active: bool,
    pub x: u32,
    pub y: u32,
    pub lives: u8,
    pub max_lives: u8,
    pub kernel: u8,
    pub invincible_until_block: u64,
    pub overclock_meter: u32,
    pub shock_bomb_meter: u32,
    pub god_mode_meter: u32,
    pub overclock_active: bool,
    pub god_mode_active: bool,
    pub upgrades_verified: bool,
    pub tick_counter: u32,
    pub last_tick_block: u64,
}

/// Run state. SECURITY: when is_finished == true the run is immutable;
/// started_at_block/last_tick_block are block-time; submitted_to_leaderboard can only be set once.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct RunState {
    #[key]
    pub player_address: ContractAddress,
    #[key]
    pub run_id: u256,
    pub current_layer: u8,
    pub current_prestige: u8,
    pub score: u64,
    pub combo_multiplier: u32,
    pub corruption_level: u32,
    pub corruption_multiplier: u32,
    pub started_at_block: u64,
    pub last_tick_block: u64,
    pub total_ticks_processed: u32,
    pub enemies_defeated: u32,
    pub shots_fired: u32,
    pub shots_hit: u32,
    pub accuracy: u32,
    pub is_finished: bool,
    pub final_score: u64,
    pub final_layer: u8,
    pub submitted_to_leaderboard: bool,
}

/// Enemy instance. SECURITY: position is server-calculated; spawn/destroy use block time;
/// destruction_verified for anti-cheat.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct Enemy {
    #[key]
    pub enemy_id: u256,
    pub run_id: u256,
    pub player_address: ContractAddress,
    pub enemy_type: u8,
    pub health: u32,
    pub max_health: u32,
    pub speed: u32,
    pub points_value: u32,
    pub x: u32,
    pub y: u32,
    pub spawn_block: u64,
    pub last_position_update_block: u64,
    pub is_active: bool,
    pub destroyed_at_block: u64,
    pub destruction_verified: bool,
}

/// Per-tick record for replay verification. SECURITY: hashes and input_sig enable
/// deterministic replay and chain-of-custody verification.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct GameTick {
    #[key]
    pub player_address: ContractAddress,
    #[key]
    pub run_id: u256,
    #[key]
    pub tick_number: u32,
    pub block_number: u64,
    pub timestamp: u64,
    pub player_input: u8,
    pub input_sig: u256,
    pub player_x: u32,
    pub player_y: u32,
    pub score_delta: u64,
    pub enemies_killed: u32,
    pub damage_taken: u32,
    pub combo_before: u32,
    pub combo_after: u32,
    pub state_hash_before: u256,
    pub state_hash_after: u256,
    pub tick_hash: u256,
}

/// Immutable event log. SECURITY: events are immutable audit trail; hashes for verification.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct GameEvent {
    #[key]
    pub event_id: u256,
    pub run_id: u256,
    pub player_address: ContractAddress,
    pub event_type: u8,
    pub tick_number: u32,
    pub block_number: u64,
    pub entity_id: u256,
    pub data_primary: u256,
    pub data_secondary: u256,
    pub game_state_hash_before: u256,
    pub game_state_hash_after: u256,
    pub verified: bool,
}

/// Final leaderboard entry. SECURITY: entry is final and immutable once submitted;
/// block/hash fields for proof and replay.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct LeaderboardEntry {
    #[key]
    pub entry_id: u256,
    pub player_address: ContractAddress,
    pub player_name: felt252,
    pub week: u32,
    pub final_score: u64,
    pub deepest_layer: u8,
    pub prestige_level: u8,
    pub survival_blocks: u64,
    pub max_corruption: u32,
    pub enemies_defeated: u32,
    pub peak_combo: u32,
    pub accuracy: u32,
    pub run_id: u256,
    pub submission_block: u64,
    pub submission_hash: u256,
    pub event_log_hash: u256,
    pub game_seed: u256,
    pub replay_verifiable: bool,
    pub tick_count: u32,
    pub aberrations_detected: u32,
    pub verified: bool,
}

/// Persistent player profile. SECURITY: append-only (except coins);
/// last_coin_claim_block and hashes for integrity.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct PlayerProfile {
    #[key]
    pub player_address: ContractAddress,
    pub current_prestige: u8,
    pub current_layer: u8,
    pub highest_prestige_reached: u8,
    pub is_prime_sentinel: bool,
    pub total_runs: u32,
    pub lifetime_score: u64,
    pub lifetime_playtime_blocks: u64,
    pub lifetime_enemies_defeated: u32,
    pub best_combo_multiplier: u32,
    pub best_run_score: u64,
    pub best_corruption_reached: u32,
    pub coins: u32,
    pub last_coin_claim_block: u64,
    pub coin_transaction_log_hash: u256,
    pub selected_kernel: u8,
    pub kernel_unlocks: u64,
    pub avatar_unlocks: u64,
    pub cosmetic_unlocks: u64,
    pub last_profile_update_block: u64,
    pub profile_hash: u256,
}

// ============== Shared types (starter) ==============

#[derive(Serde, Copy, Drop, Introspect, PartialEq, Debug, DojoStore, Default)]
pub enum Direction {
    #[default]
    Left,
    Right,
    Up,
    Down,
}

#[derive(Copy, Drop, Serde, IntrospectPacked, Debug, DojoStore)]
pub struct Vec2 {
    pub x: u32,
    pub y: u32,
}


impl DirectionIntoFelt252 of Into<Direction, felt252> {
    fn into(self: Direction) -> felt252 {
        match self {
            Direction::Left => 1,
            Direction::Right => 2,
            Direction::Up => 3,
            Direction::Down => 4,
        }
    }
}

impl OptionDirectionIntoFelt252 of Into<Option<Direction>, felt252> {
    fn into(self: Option<Direction>) -> felt252 {
        match self {
            Option::None => 0,
            Option::Some(d) => d.into(),
        }
    }
}

#[generate_trait]
impl Vec2Impl of Vec2Trait {
    fn is_zero(self: Vec2) -> bool {
        if self.x - self.y == 0 {
            return true;
        }
        false
    }

    fn is_equal(self: Vec2, b: Vec2) -> bool {
        self.x == b.x && self.y == b.y
    }
}

#[cfg(test)]
mod tests {
    use super::{Vec2, Vec2Trait};

    #[test]
    fn test_vec_is_zero() {
        assert(Vec2Trait::is_zero(Vec2 { x: 0, y: 0 }), 'not zero');
    }

    #[test]
    fn test_vec_is_equal() {
        let position = Vec2 { x: 420, y: 0 };
        assert(position.is_equal(Vec2 { x: 420, y: 0 }), 'not equal');
    }
}
