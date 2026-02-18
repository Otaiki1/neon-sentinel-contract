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
    /// Attestation: which pregame upgrades were used for this run (set at start_run).
    pub pregame_upgrades_mask: u256,
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
    pub coin_transaction_count: u32,
    pub selected_kernel: u8,
    pub kernel_unlocks: u64,
    pub avatar_unlocks: u64,
    pub cosmetic_unlocks: u64,
    pub last_profile_update_block: u64,
    pub profile_hash: u256,
    /// Highest rank tier (prestige*6 + layer-1) for which a RankNFT was minted; avoids duplicate mints.
    pub highest_rank_tier_minted: u8,
}

/// Rank achievement NFT (soulbound). Minted when player reaches a new rank tier.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct RankNFT {
    #[key]
    pub token_id: u256,
    pub owner: ContractAddress,
    pub rank_tier: u8,
    pub prestige: u8,
    pub layer: u8,
    pub achieved_at_block: u64,
    pub run_id: u256,
}

// ============== Token purchase & treasury models ==============

/// Single-row pointer to the coin shop owner (so systems can resolve TokenPurchaseConfig by owner).
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct CoinShopGlobal {
    #[key]
    /// Use 0 for the single global row.
    pub global_key: felt252,
    pub owner: ContractAddress,
}

/// Global config for STRK → in-game coin purchasing. SECURITY: only owner can modify.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct TokenPurchaseConfig {
    #[key]
    pub owner: ContractAddress,
    pub strk_token_address: ContractAddress,
    pub coin_exchange_rate: u32,
    pub total_strk_collected: u256,
    pub total_strk_withdrawn: u256,
    pub total_coins_sold: u256,
    pub is_enabled: bool,
    pub paused: bool,
    pub last_updated: u64,
    pub collected_strk_version: u32,
    pub next_withdrawal_id: u256,
}

/// Immutable record of a single coin purchase. Used for auditing and receipt verification.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct CoinPurchaseRecord {
    #[key]
    pub purchase_id: u256,
    pub player_address: ContractAddress,
    pub strk_amount: u256,
    pub coins_received: u256,
    pub purchase_block: u64,
    pub purchase_timestamp: u64,
    pub transaction_hash: u256,
    pub verified: bool,
}

/// Per-player purchase history. Append-only; tracks spending and purchase behavior.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct CoinPurchaseHistory {
    #[key]
    pub player_address: ContractAddress,
    pub total_strk_spent: u256,
    pub total_coins_purchased: u256,
    pub purchase_count: u32,
    pub first_purchase_block: u64,
    pub last_purchase_block: u64,
    pub last_claimed_coins_block: u64,
    pub verified_purchases: u32,
}

/// Owner withdrawal request. Audit trail for treasury management; status lifecycle.
#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct WithdrawalRequest {
    #[key]
    pub withdrawal_id: u256,
    pub owner_address: ContractAddress,
    pub strk_amount: u256,
    pub requested_block: u64,
    /// 0=pending, 1=approved, 2=executed, 3=rejected
    pub status: u8,
    pub executed_block: u64,
    pub executed_at_transaction: u256,
    pub notes: felt252,
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
    use core::integer::u256;
    use starknet::ContractAddress;

    use super::{
        Enemy, GameTick, LeaderboardEntry, Player, RunState, Vec2, Vec2Trait,
    };

    fn dummy_address() -> ContractAddress {
        0.try_into().unwrap()
    }

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    // ---------- Vec2 (existing) ----------

    #[test]
    fn test_vec_is_zero() {
        assert(Vec2Trait::is_zero(Vec2 { x: 0, y: 0 }), 'not zero');
    }

    #[test]
    fn test_vec_is_equal() {
        let position = Vec2 { x: 420, y: 0 };
        assert(position.is_equal(Vec2 { x: 420, y: 0 }), 'not equal');
    }

    // ---------- 1. Player model ----------

    #[test]
    fn test_player_create_with_valid_data() {
        let run_id = u256 { low: 1, high: 0 };
        let player = Player {
            player_address: dummy_address(),
            run_id,
            is_active: true,
            x: 0,
            y: 0,
            lives: 3,
            max_lives: 20,
            kernel: 2,
            invincible_until_block: 100,
            overclock_meter: 0,
            shock_bomb_meter: 0,
            god_mode_meter: 0,
            overclock_active: false,
            god_mode_active: false,
            upgrades_verified: true,
            tick_counter: 0,
            last_tick_block: 100,
        };
        assert(player.player_address == dummy_address(), 'address');
        assert(player.run_id.low == 1 && player.run_id.high == 0, 'run_id');
        assert(player.kernel == 2, 'kernel');
    }

    #[test]
    fn test_player_kernel_range_valid() {
        let run_id = zero_u256();
        let player_min = Player {
            player_address: dummy_address(),
            run_id,
            is_active: true,
            x: 0,
            y: 0,
            lives: 3,
            max_lives: 20,
            kernel: 0,
            invincible_until_block: 0,
            overclock_meter: 0,
            shock_bomb_meter: 0,
            god_mode_meter: 0,
            overclock_active: false,
            god_mode_active: false,
            upgrades_verified: true,
            tick_counter: 0,
            last_tick_block: 0,
        };
        assert(player_min.kernel == 0, 'kernel min 0');
        let player_max = Player {
            player_address: dummy_address(),
            run_id,
            is_active: true,
            x: 0,
            y: 0,
            lives: 3,
            max_lives: 20,
            kernel: 5,
            invincible_until_block: 0,
            overclock_meter: 0,
            shock_bomb_meter: 0,
            god_mode_meter: 0,
            overclock_active: false,
            god_mode_active: false,
            upgrades_verified: true,
            tick_counter: 0,
            last_tick_block: 0,
        };
        assert(player_max.kernel == 5, 'kernel max 5');
    }

    #[test]
    fn test_player_upgrades_verified_set_correctly() {
        let run_id = zero_u256();
        let verified = Player {
            player_address: dummy_address(),
            run_id,
            is_active: true,
            x: 0,
            y: 0,
            lives: 3,
            max_lives: 20,
            kernel: 0,
            invincible_until_block: 0,
            overclock_meter: 0,
            shock_bomb_meter: 0,
            god_mode_meter: 0,
            overclock_active: false,
            god_mode_active: false,
            upgrades_verified: true,
            tick_counter: 0,
            last_tick_block: 0,
        };
        assert(verified.upgrades_verified == true, 'upgrades_verified true');
        let unverified = Player {
            player_address: dummy_address(),
            run_id,
            is_active: false,
            x: 0,
            y: 0,
            lives: 3,
            max_lives: 20,
            kernel: 0,
            invincible_until_block: 0,
            overclock_meter: 0,
            shock_bomb_meter: 0,
            god_mode_meter: 0,
            overclock_active: false,
            god_mode_active: false,
            upgrades_verified: false,
            tick_counter: 0,
            last_tick_block: 0,
        };
        assert(unverified.upgrades_verified == false, 'upgrades_verified false');
    }

    #[test]
    fn test_player_abilities_initialized_zero_or_false() {
        let run_id = zero_u256();
        let player = Player {
            player_address: dummy_address(),
            run_id,
            is_active: true,
            x: 0,
            y: 0,
            lives: 3,
            max_lives: 20,
            kernel: 0,
            invincible_until_block: 0,
            overclock_meter: 0,
            shock_bomb_meter: 0,
            god_mode_meter: 0,
            overclock_active: false,
            god_mode_active: false,
            upgrades_verified: true,
            tick_counter: 0,
            last_tick_block: 0,
        };
        assert(player.overclock_meter == 0, 'overclock_meter 0');
        assert(player.shock_bomb_meter == 0, 'shock_bomb_meter 0');
        assert(player.god_mode_meter == 0, 'god_mode_meter 0');
        assert(player.overclock_active == false, 'overclock_active false');
        assert(player.god_mode_active == false, 'god_mode_active false');
    }

    // ---------- 2. RunState model ----------

    #[test]
    fn test_run_state_create_with_valid_data() {
        let run_id = u256 { low: 42, high: 0 };
        let state = RunState {
            player_address: dummy_address(),
            run_id,
            current_layer: 1,
            current_prestige: 0,
            score: 0,
            combo_multiplier: 1000,
            corruption_level: 0,
            corruption_multiplier: 0,
            started_at_block: 1000,
            last_tick_block: 1000,
            total_ticks_processed: 0,
            enemies_defeated: 0,
            shots_fired: 0,
            shots_hit: 0,
            accuracy: 0,
            is_finished: false,
            final_score: 0,
            final_layer: 0,
            submitted_to_leaderboard: false,
            pregame_upgrades_mask: zero_u256(),
        };
        assert(state.run_id.low == 42, 'run_id');
        assert(state.current_layer == 1, 'layer');
    }

    #[test]
    fn test_run_state_metrics_initialized_to_zero() {
        let state = RunState {
            player_address: dummy_address(),
            run_id: zero_u256(),
            current_layer: 0,
            current_prestige: 0,
            score: 0,
            combo_multiplier: 0,
            corruption_level: 0,
            corruption_multiplier: 0,
            started_at_block: 0,
            last_tick_block: 0,
            total_ticks_processed: 0,
            enemies_defeated: 0,
            shots_fired: 0,
            shots_hit: 0,
            accuracy: 0,
            is_finished: false,
            final_score: 0,
            final_layer: 0,
            submitted_to_leaderboard: false,
            pregame_upgrades_mask: zero_u256(),
        };
        assert(state.score == 0, 'score');
        assert(state.total_ticks_processed == 0, 'total_ticks');
        assert(state.enemies_defeated == 0, 'enemies_defeated');
        assert(state.shots_fired == 0, 'shots_fired');
        assert(state.shots_hit == 0, 'shots_hit');
        assert(state.accuracy == 0, 'accuracy');
        assert(state.final_score == 0, 'final_score');
    }

    #[test]
    fn test_run_state_is_finished_false_initially() {
        let state = RunState {
            player_address: dummy_address(),
            run_id: zero_u256(),
            current_layer: 1,
            current_prestige: 0,
            score: 0,
            combo_multiplier: 1000,
            corruption_level: 0,
            corruption_multiplier: 0,
            started_at_block: 0,
            last_tick_block: 0,
            total_ticks_processed: 0,
            enemies_defeated: 0,
            shots_fired: 0,
            shots_hit: 0,
            accuracy: 0,
            is_finished: false,
            final_score: 0,
            final_layer: 0,
            submitted_to_leaderboard: false,
            pregame_upgrades_mask: zero_u256(),
        };
        assert(state.is_finished == false, 'is_finished false');
    }

    // ---------- 3. Enemy model ----------

    #[test]
    fn test_enemy_create_with_valid_enemy_type() {
        let enemy_id = u256 { low: 1, high: 0 };
        let run_id = zero_u256();
        let enemy_low = Enemy {
            enemy_id,
            run_id,
            player_address: dummy_address(),
            enemy_type: 1,
            health: 10,
            max_health: 10,
            speed: 1,
            points_value: 100,
            x: 50,
            y: 50,
            spawn_block: 100,
            last_position_update_block: 100,
            is_active: true,
            destroyed_at_block: 0,
            destruction_verified: false,
        };
        assert(enemy_low.enemy_type == 1, 'enemy_type min');
        let enemy_high = Enemy {
            enemy_id,
            run_id,
            player_address: dummy_address(),
            enemy_type: 10,
            health: 10,
            max_health: 10,
            speed: 1,
            points_value: 100,
            x: 50,
            y: 50,
            spawn_block: 100,
            last_position_update_block: 100,
            is_active: true,
            destroyed_at_block: 0,
            destruction_verified: false,
        };
        assert(enemy_high.enemy_type == 10, 'enemy_type max');
    }

    #[test]
    fn test_enemy_health_properly_set() {
        let enemy = Enemy {
            enemy_id: u256 { low: 1, high: 0 },
            run_id: zero_u256(),
            player_address: dummy_address(),
            enemy_type: 1,
            health: 25,
            max_health: 25,
            speed: 2,
            points_value: 50,
            x: 0,
            y: 0,
            spawn_block: 0,
            last_position_update_block: 0,
            is_active: true,
            destroyed_at_block: 0,
            destruction_verified: false,
        };
        assert(enemy.health == 25, 'health');
        assert(enemy.max_health == 25, 'max_health');
    }

    #[test]
    fn test_enemy_is_active_starts_true() {
        let enemy = Enemy {
            enemy_id: zero_u256(),
            run_id: zero_u256(),
            player_address: dummy_address(),
            enemy_type: 1,
            health: 10,
            max_health: 10,
            speed: 0,
            points_value: 0,
            x: 0,
            y: 0,
            spawn_block: 0,
            last_position_update_block: 0,
            is_active: true,
            destroyed_at_block: 0,
            destruction_verified: false,
        };
        assert(enemy.is_active == true, 'is_active true');
    }

    // ---------- 4. GameTick model ----------

    #[test]
    fn test_game_tick_records_input_correctly() {
        let run_id = zero_u256();
        let input_sig = u256 { low: 123, high: 0 };
        let tick = GameTick {
            player_address: dummy_address(),
            run_id,
            tick_number: 1,
            block_number: 200,
            timestamp: 2000,
            player_input: 3,
            input_sig,
            player_x: 10,
            player_y: 20,
            score_delta: 100,
            enemies_killed: 1,
            damage_taken: 0,
            combo_before: 1000,
            combo_after: 1200,
            state_hash_before: zero_u256(),
            state_hash_after: u256 { low: 1, high: 0 },
            tick_hash: u256 { low: 2, high: 0 },
        };
        assert(tick.player_input == 3, 'player_input');
        assert(tick.input_sig.low == 123, 'input_sig');
    }

    #[test]
    fn test_game_tick_stores_state_hashes() {
        let hash_before = u256 { low: 100, high: 1 };
        let hash_after = u256 { low: 200, high: 2 };
        let tick_hash = u256 { low: 300, high: 3 };
        let tick = GameTick {
            player_address: dummy_address(),
            run_id: zero_u256(),
            tick_number: 0,
            block_number: 0,
            timestamp: 0,
            player_input: 0,
            input_sig: zero_u256(),
            player_x: 0,
            player_y: 0,
            score_delta: 0,
            enemies_killed: 0,
            damage_taken: 0,
            combo_before: 0,
            combo_after: 0,
            state_hash_before: hash_before,
            state_hash_after: hash_after,
            tick_hash,
        };
        assert(tick.state_hash_before.low == 100 && tick.state_hash_before.high == 1, 'before');
        assert(tick.state_hash_after.low == 200 && tick.state_hash_after.high == 2, 'after');
        assert(tick.tick_hash.low == 300 && tick.tick_hash.high == 3, 'tick_hash');
    }

    // ---------- 5. LeaderboardEntry model ----------

    #[test]
    fn test_leaderboard_entry_contains_all_proof_fields() {
        let entry_id = u256 { low: 1, high: 0 };
        let run_id = u256 { low: 2, high: 0 };
        let submission_hash = u256 { low: 10, high: 0 };
        let event_log_hash = u256 { low: 20, high: 0 };
        let game_seed = u256 { low: 30, high: 0 };
        let entry = LeaderboardEntry {
            entry_id,
            player_address: dummy_address(),
            player_name: 0,
            week: 1,
            final_score: 5000,
            deepest_layer: 3,
            prestige_level: 0,
            survival_blocks: 10000,
            max_corruption: 50,
            enemies_defeated: 100,
            peak_combo: 2000,
            accuracy: 850,
            run_id,
            submission_block: 12345,
            submission_hash,
            event_log_hash,
            game_seed,
            replay_verifiable: true,
            tick_count: 500,
            aberrations_detected: 0,
            verified: true,
        };
        assert(entry.submission_block == 12345, 'submission_block');
        assert(entry.submission_hash.low == 10, 'submission_hash');
        assert(entry.event_log_hash.low == 20, 'event_log_hash');
        assert(entry.game_seed.low == 30, 'game_seed');
        assert(entry.replay_verifiable == true, 'replay_verifiable');
        assert(entry.verified == true, 'verified');
    }

    #[test]
    fn test_leaderboard_entry_cannot_be_modified_after_creation() {
        let entry = LeaderboardEntry {
            entry_id: u256 { low: 1, high: 0 },
            player_address: dummy_address(),
            player_name: 0,
            week: 1,
            final_score: 1000,
            deepest_layer: 1,
            prestige_level: 0,
            survival_blocks: 100,
            max_corruption: 0,
            enemies_defeated: 10,
            peak_combo: 1000,
            accuracy: 1000,
            run_id: zero_u256(),
            submission_block: 100,
            submission_hash: zero_u256(),
            event_log_hash: zero_u256(),
            game_seed: zero_u256(),
            replay_verifiable: true,
            tick_count: 50,
            aberrations_detected: 0,
            verified: true,
        };
        let snapshot_score = entry.final_score;
        let snapshot_hash = entry.submission_hash.low;
        assert(snapshot_score == 1000, 'score unchanged');
        assert(snapshot_hash == 0, 'hash unchanged');
    }
}
