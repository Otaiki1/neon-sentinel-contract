//! init_game system (start_run): initializes a new game run with full validation.
//! Generates a run_id (run hash) from block_number + block_timestamp + caller; validated on end_run.
//! If called again while a run is active, the previous run is abandoned (overwrite Player + new RunState).

use core::integer::u256;

/// Event type: game_start (per Phase 2 GameEvent spec).
const EVENT_TYPE_GAME_START: u8 = 6;

/// Max valid kernel index (0-5).
const MAX_KERNEL: u8 = 5;

/// Max allowed pregame upgrades mask (all bits allowed for now).
const MAX_PREGAME_UPGRADES_MASK: u256 = u256 { low: 0xffffffffffffffffffffffffffffffff, high: 0xffffffffffffffffffffffffffffffff };

/// Coin cost per upgrade bit (for compute_upgrade_cost).
const COIN_PER_UPGRADE: u32 = 1;

/// Starting position and lives.
const START_X: u32 = 0;
const START_Y: u32 = 0;
const START_LIVES: u8 = 3;
const MAX_LIVES: u8 = 20;

/// Combo multiplier 1.0x = 1000.
const COMBO_ONE: u32 = 1000;

#[starknet::interface]
pub trait IInitGame<T> {
    fn init_game(
        ref self: T,
        kernel: u8,
        pregame_upgrades_mask: u256,
        expected_cost: u32,
    );
}

const TWO_POW_64: u128 = 18446744073709551616; // 2^64

/// Reason felt252 for upgrade spend (coin history and event).
const REASON_PREGAME_UPGRADES: felt252 = 'pregame_upgrades';

#[dojo::contract]
pub mod init_game {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::{
        COMBO_ONE, COIN_PER_UPGRADE, EVENT_TYPE_GAME_START, MAX_KERNEL, MAX_LIVES,
        MAX_PREGAME_UPGRADES_MASK, REASON_PREGAME_UPGRADES, START_LIVES, START_X, START_Y,
        TWO_POW_64,
    };
    use super::IInitGame;
    use neon_sentinel::models::{GameEvent, Player, PlayerProfile, RunState};

    /// Append transaction to log hash chain (same as spend_coins / claim_coins).
    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 { low: prev.low + bl + am, high: prev.high + 1 }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CoinSpent {
        #[key]
        pub player: ContractAddress,
        pub amount: u32,
        pub reason: felt252,
        pub block_number: u64,
    }

    /// 2^n for n in 0..=63 (used for kernel_unlocks bit check).
    fn pow2_u64(n: u8) -> u64 {
        let mut res: u64 = 1;
        let mut i: u8 = 0;
        loop {
            if i >= n {
                break;
            }
            res = res * 2;
            i += 1;
        }
        res
    }

    /// Deterministic seed from block + caller for replay verification.
    fn compute_run_seed(block_number: u64, block_timestamp: u64, _caller: ContractAddress) -> u256 {
        let bn: u128 = block_number.try_into().unwrap();
        let bt: u128 = block_timestamp.try_into().unwrap();
        let low = bn + bt * TWO_POW_64;
        let high: u128 = 0;
        u256 { low, high }
    }

    /// Expected coin cost from pregame upgrades mask (popcount * COIN_PER_UPGRADE).
    fn compute_upgrade_cost(mask: u256) -> u32 {
        let mut cost: u32 = 0;
        let mut m_low = mask.low;
        let mut m_high = mask.high;
        while m_low != 0 {
            if m_low & 1 != 0 {
                cost += COIN_PER_UPGRADE;
            }
            m_low /= 2;
        }
        while m_high != 0 {
            if m_high & 1 != 0 {
                cost += COIN_PER_UPGRADE;
            }
            m_high /= 2;
        }
        cost
    }

    #[abi(embed_v0)]
    impl InitGameImpl of IInitGame<ContractState> {
        fn init_game(
            ref self: ContractState,
            kernel: u8,
            pregame_upgrades_mask: u256,
            expected_cost: u32,
        ) {
            let mut world = self.world_default();
            let caller = get_caller_address();

            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;
            let block_timestamp = exec_info.block_info.block_timestamp;

            // 1. Validate kernel (0-5) and that caller owns it (kernel 0 always unlocked)
            assert(kernel <= MAX_KERNEL, 'Invalid kernel');
            let mut profile: PlayerProfile = world.read_model(caller);
            if kernel > 0 {
                let bit = pow2_u64(kernel);
                assert(
                    (profile.kernel_unlocks & bit) != 0,
                    'Kernel not unlocked',
                );
            }

            // 2. Pregame upgrades within valid range
            assert(
                pregame_upgrades_mask.low <= MAX_PREGAME_UPGRADES_MASK.low
                    && pregame_upgrades_mask.high <= MAX_PREGAME_UPGRADES_MASK.high,
                'Invalid pregame upgrades',
            );

            // 3. Expected coin cost matches computed
            let computed_cost = compute_upgrade_cost(pregame_upgrades_mask);
            assert(computed_cost == expected_cost, 'Cost mismatch');

            // 4. Sufficient coins
            assert(profile.coins >= expected_cost, 'Insufficient coins');

            // 5. No assert on active run: starting again overwrites Player and creates new RunState;
            //    the previous run is abandoned (never consolidated; end_run for old run_id will fail).
            let _player_state: Player = world.read_model(caller);

            // 6. Run hash (run_id): deterministic from block + timestamp + caller; validated on end_run.
            let run_id = compute_run_seed(block_number, block_timestamp, caller);

            // 7. Create Player entity (all anti-cheat fields)
            let new_player = Player {
                player_address: caller,
                run_id,
                is_active: true,
                x: START_X,
                y: START_Y,
                lives: START_LIVES,
                max_lives: MAX_LIVES,
                kernel,
                invincible_until_block: block_number,
                overclock_meter: 0,
                shock_bomb_meter: 0,
                god_mode_meter: 0,
                overclock_active: false,
                god_mode_active: false,
                upgrades_verified: true,
                tick_counter: 0,
                last_tick_block: block_number,
            };
            world.write_model(@new_player);

            // 8. Create RunState entity (pregame_upgrades_mask attests upgrades used for this run)
            let zero_u256 = u256 { low: 0, high: 0 };
            let run_state = RunState {
                player_address: caller,
                run_id,
                current_layer: 1,
                current_prestige: 0,
                score: 0,
                combo_multiplier: COMBO_ONE,
                corruption_level: 0,
                corruption_multiplier: 0,
                started_at_block: block_number,
                last_tick_block: block_number,
                total_ticks_processed: 0,
                enemies_defeated: 0,
                shots_fired: 0,
                shots_hit: 0,
                accuracy: 0,
                is_finished: false,
                final_score: 0,
                final_layer: 0,
                submitted_to_leaderboard: false,
                pregame_upgrades_mask,
            };
            world.write_model(@run_state);

            // 9. Emit GameEvent (game_start) - write_model for GameEvent (deterministic event_id from run_id)
            let event_id = u256 { low: run_id.low + 1, high: run_id.high };
            let game_event = GameEvent {
                event_id,
                run_id,
                player_address: caller,
                event_type: EVENT_TYPE_GAME_START,
                tick_number: 0,
                block_number,
                entity_id: zero_u256,
                data_primary: zero_u256,
                data_secondary: zero_u256,
                game_state_hash_before: zero_u256,
                game_state_hash_after: zero_u256,
                verified: false,
            };
            world.write_model(@game_event);

            // 10. Deduct coins and record in coin history (same as spend_coins)
            profile.coins -= expected_cost;
            profile.coin_transaction_log_hash =
                next_coin_log_hash(profile.coin_transaction_log_hash, block_number, expected_cost);
            profile.coin_transaction_count += 1;
            world.write_model(@profile);

            // 11. Emit CoinSpent-style event for logging
            world.emit_event(@CoinSpent {
                player: caller,
                amount: expected_cost,
                reason: REASON_PREGAME_UPGRADES,
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
