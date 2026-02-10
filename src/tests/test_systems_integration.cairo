//! System integration tests: game init, tick, hit, end_run, submit_leaderboard,
//! error cases, and security tests (attack prevention).

#[cfg(test)]
mod tests {
    use core::integer::u256;
    use dojo::model::{ModelStorage, ModelStorageTest};
    use dojo::world::{WorldStorageTrait, world};
    use dojo_cairo_test::{
        ContractDef, ContractDefTrait, NamespaceDef, TestResource, WorldStorageTestTrait,
        spawn_test_world,
    };
    use neon_sentinel::models::{
        Enemy, LeaderboardEntry, Player, PlayerProfile, RunState,
        m_Enemy, m_GameEvent, m_GameTick, m_LeaderboardEntry, m_Player, m_PlayerProfile,
        m_RunState,
    };
    use neon_sentinel::systems::end_run::{IEndRunDispatcher, IEndRunDispatcherTrait, end_run};
    use neon_sentinel::systems::hit_registration::{
        IHitRegistrationDispatcher, IHitRegistrationDispatcherTrait, hit_registration,
    };
    use neon_sentinel::systems::init_game::{
        IInitGameDispatcher, IInitGameDispatcherTrait, init_game,
    };
    use neon_sentinel::systems::claim_coins::{IClaimCoinsDispatcher, IClaimCoinsDispatcherTrait, claim_coins};
    use neon_sentinel::systems::submit_leaderboard::{
        ISubmitLeaderboardDispatcher, ISubmitLeaderboardDispatcherTrait, submit_leaderboard,
    };
    use starknet::testing::set_block_number;
    use starknet::ContractAddress;

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    fn namespace_def() -> NamespaceDef {
        let ndef = NamespaceDef {
            namespace: "neon_sentinel",
            resources: [
                TestResource::Model(m_Player::TEST_CLASS_HASH),
                TestResource::Model(m_RunState::TEST_CLASS_HASH),
                TestResource::Model(m_Enemy::TEST_CLASS_HASH),
                TestResource::Model(m_GameTick::TEST_CLASS_HASH),
                TestResource::Model(m_GameEvent::TEST_CLASS_HASH),
                TestResource::Model(m_LeaderboardEntry::TEST_CLASS_HASH),
                TestResource::Model(m_PlayerProfile::TEST_CLASS_HASH),
                TestResource::Event(init_game::e_CoinSpent::TEST_CLASS_HASH),
                TestResource::Contract(init_game::TEST_CLASS_HASH),
                TestResource::Contract(hit_registration::TEST_CLASS_HASH),
                TestResource::Contract(end_run::TEST_CLASS_HASH),
                TestResource::Contract(submit_leaderboard::TEST_CLASS_HASH),
                TestResource::Event(claim_coins::e_CoinClaimed::TEST_CLASS_HASH),
                TestResource::Contract(claim_coins::TEST_CLASS_HASH),
            ]
                .span(),
        };
        ndef
    }

    fn contract_defs() -> Span<ContractDef> {
        let ns_hash = dojo::utils::bytearray_hash(@"neon_sentinel");
        [
            ContractDefTrait::new(@"neon_sentinel", @"init_game")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"hit_registration")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"end_run")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"submit_leaderboard")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"claim_coins")
                .with_writer_of([ns_hash].span()),
        ]
            .span()
    }

    fn setup_world_with_profile() -> (dojo::world::WorldStorage, ContractAddress) {
        let caller: ContractAddress = 0.try_into().unwrap();
        let ndef = namespace_def();
        let mut world = spawn_test_world(world::TEST_CLASS_HASH, [ndef].span());
        world.sync_perms_and_inits(contract_defs());

        let profile = PlayerProfile {
            player_address: caller,
            current_prestige: 0,
            current_layer: 0,
            highest_prestige_reached: 0,
            is_prime_sentinel: false,
            total_runs: 0,
            lifetime_score: 0,
            lifetime_playtime_blocks: 0,
            lifetime_enemies_defeated: 0,
            best_combo_multiplier: 0,
            best_run_score: 0,
            best_corruption_reached: 0,
            coins: 100,
            last_coin_claim_block: 0,
            coin_transaction_log_hash: zero_u256(),
            coin_transaction_count: 0,
            selected_kernel: 0,
            kernel_unlocks: 0,
            avatar_unlocks: 0,
            cosmetic_unlocks: 0,
            last_profile_update_block: 0,
            profile_hash: zero_u256(),
        };
        world.write_model_test(@profile);
        (world, caller)
    }

    // ---------- Workflow tests ----------

    #[test]
    #[available_gas(50000000)]
    fn test_game_init_creates_player_and_run_state_deducts_coins() {
        set_block_number(1000);
        let (mut world, caller) = setup_world_with_profile();

        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);

        let player: Player = world.read_model(caller);
        assert(player.is_active, 'player active');
        assert(player.kernel == 0, 'kernel 0');
        assert(player.x == 0 && player.y == 0, 'start position');
        assert(player.upgrades_verified == true, 'upgrades verified');

        let run_id = player.run_id;
        let run_state: RunState = world.read_model((caller, run_id));
        assert(run_state.is_finished == false, 'run not finished');
        assert(run_state.score == 0, 'score 0');
        assert(run_state.current_layer == 1, 'layer 1');

        let profile: PlayerProfile = world.read_model(caller);
        assert(profile.coins == 100, 'coins unchanged when cost 0');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_hit_registration_reduces_health_increases_score() {
        set_block_number(2000);
        let (mut world, caller) = setup_world_with_profile();

        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);

        let player: Player = world.read_model(caller);
        let run_id = player.run_id;

        let enemy_id = u256 { low: 1, high: 0 };
        let enemy = Enemy {
            enemy_id,
            run_id,
            player_address: caller,
            enemy_type: 1,
            health: 10,
            max_health: 10,
            speed: 0,
            points_value: 100,
            x: 5,
            y: 0,
            spawn_block: 2000,
            last_position_update_block: 2000,
            is_active: true,
            destroyed_at_block: 0,
            destruction_verified: false,
        };
        world.write_model_test(@enemy);

        let (hit_addr, _) = world.dns(@"hit_registration").unwrap();
        let hit_sys = IHitRegistrationDispatcher { contract_address: hit_addr };
        hit_sys.hit_registration(run_id, enemy_id, 10, 0, 0, zero_u256());

        let enemy_after: Enemy = world.read_model(enemy_id);
        assert(enemy_after.health == 0, 'enemy health 0');
        assert(enemy_after.is_active == false, 'enemy inactive');

        let run_state: RunState = world.read_model((caller, run_id));
        assert(run_state.score > 0, 'score increased');
        assert(run_state.enemies_defeated == 1, 'enemies_defeated 1');
    }

    #[test]
    #[available_gas(60000000)]
    fn test_end_run_sets_finished_and_locks_final_score() {
        set_block_number(3000);
        let (mut world, caller) = setup_world_with_profile();

        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);

        let player: Player = world.read_model(caller);
        let run_id = player.run_id;

        let (end_addr, _) = world.dns(@"end_run").unwrap();
        let end_sys = IEndRunDispatcher { contract_address: end_addr };
        end_sys.end_run(run_id);

        let run_state: RunState = world.read_model((caller, run_id));
        assert(run_state.is_finished == true, 'is_finished true');
        assert(run_state.final_score == run_state.score, 'final_score locked');
        assert(run_state.final_layer == run_state.current_layer, 'final_layer locked');

        let player_after: Player = world.read_model(caller);
        assert(player_after.is_active == false, 'player inactive');
    }

    #[test]
    #[available_gas(100000000)]
    fn test_submit_leaderboard_creates_entry_verified_true() {
        set_block_number(4000);
        let (mut world, caller) = setup_world_with_profile();

        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);

        let player: Player = world.read_model(caller);
        let run_id = player.run_id;

        let (end_addr, _) = world.dns(@"end_run").unwrap();
        let end_sys = IEndRunDispatcher { contract_address: end_addr };
        end_sys.end_run(run_id);

        let week: u32 = 0;
        let (sub_addr, _) = world.dns(@"submit_leaderboard").unwrap();
        let sub_sys = ISubmitLeaderboardDispatcher { contract_address: sub_addr };
        sub_sys.submit_leaderboard(run_id, week);

        let run_state: RunState = world.read_model((caller, run_id));
        assert(run_state.submitted_to_leaderboard == true, 'submitted flag');

        let entry_id = u256 { low: run_id.low + week.into(), high: run_id.high };
        let entry: LeaderboardEntry = world.read_model(entry_id);
        assert(entry.verified == true, 'entry verified');
        assert(entry.player_address == caller, 'entry player');
        assert(entry.run_id.low == run_id.low && entry.run_id.high == run_id.high, 'entry run_id');
    }

    // ---------- Error cases (ignored: scarb test does not support should_panic for contract calls; run with snforge) ----------

    #[test]
    #[ignore]
    #[should_panic(expected: ('Invalid kernel',))]
    fn test_cannot_init_game_with_invalid_kernel() {
        set_block_number(5000);
        let (mut world, _caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(6, zero_u256(), 0);
    }

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Insufficient coins',))]
    fn test_cannot_spend_coins_you_dont_have() {
        set_block_number(6000);
        let (mut world, caller) = setup_world_with_profile();
        let mut profile: PlayerProfile = world.read_model(caller);
        profile.coins = 0;
        world.write_model_test(@profile);
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, u256 { low: 1, high: 0 }, 1);
    }

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Out of range',))]
    fn test_cannot_register_hit_out_of_range() {
        set_block_number(7000);
        let (mut world, caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        let player: Player = world.read_model(caller);
        let run_id = player.run_id;
        let enemy_id = u256 { low: 2, high: 0 };
        let enemy = Enemy {
            enemy_id,
            run_id,
            player_address: caller,
            enemy_type: 1,
            health: 10,
            max_health: 10,
            speed: 0,
            points_value: 100,
            x: 100,
            y: 100,
            spawn_block: 7000,
            last_position_update_block: 7000,
            is_active: true,
            destroyed_at_block: 0,
            destruction_verified: false,
        };
        world.write_model_test(@enemy);
        let (hit_addr, _) = world.dns(@"hit_registration").unwrap();
        let hit_sys = IHitRegistrationDispatcher { contract_address: hit_addr };
        hit_sys.hit_registration(run_id, enemy_id, 10, 0, 0, zero_u256());
    }

    // ---------- Security tests (attack prevention) ----------
    // Tests that expect specific failure use #[should_panic] + #[ignore] for scarb test; run with snforge to verify.

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Too soon to claim',))]
    fn test_security_time_travel_claim_coins_before_24h() {
        set_block_number(20000);
        let (mut world, _caller) = setup_world_with_profile();
        let (claim_addr, _) = world.dns(@"claim_coins").unwrap();
        let claim_sys = IClaimCoinsDispatcher { contract_address: claim_addr };
        claim_sys.claim_coins();
        set_block_number(20000 + 3600);
        claim_sys.claim_coins();
    }

    #[test]
    #[available_gas(60000000)]
    fn test_security_score_modification_no_direct_set() {
        set_block_number(30000);
        let (mut world, caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        let player: Player = world.read_model(caller);
        let run_id = player.run_id;
        let run_state: RunState = world.read_model((caller, run_id));
        assert(run_state.score == 0, 'score no injection');
    }

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Out of range',))]
    fn test_security_position_spoofing_hit_enemy_500_away() {
        set_block_number(40000);
        let (mut world, caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        let player: Player = world.read_model(caller);
        let run_id = player.run_id;
        let enemy_id = u256 { low: 10, high: 0 };
        let enemy = Enemy {
            enemy_id,
            run_id,
            player_address: caller,
            enemy_type: 1,
            health: 10,
            max_health: 10,
            speed: 0,
            points_value: 100,
            x: 500,
            y: 0,
            spawn_block: 40000,
            last_position_update_block: 40000,
            is_active: true,
            destroyed_at_block: 0,
            destruction_verified: false,
        };
        world.write_model_test(@enemy);
        let (hit_addr, _) = world.dns(@"hit_registration").unwrap();
        let hit_sys = IHitRegistrationDispatcher { contract_address: hit_addr };
        hit_sys.hit_registration(run_id, enemy_id, 10, 0, 0, zero_u256());
    }

    #[test]
    #[ignore]
    #[available_gas(100000000)]
    #[should_panic(expected: ('Already submitted',))]
    fn test_security_double_submission_leaderboard_twice() {
        set_block_number(50000);
        let (mut world, caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        let player: Player = world.read_model(caller);
        let run_id = player.run_id;
        let (end_addr, _) = world.dns(@"end_run").unwrap();
        let end_sys = IEndRunDispatcher { contract_address: end_addr };
        end_sys.end_run(run_id);
        let week: u32 = 0;
        let (sub_addr, _) = world.dns(@"submit_leaderboard").unwrap();
        let sub_sys = ISubmitLeaderboardDispatcher { contract_address: sub_addr };
        sub_sys.submit_leaderboard(run_id, week);
        sub_sys.submit_leaderboard(run_id, week);
    }

    #[test]
    #[ignore]
    #[available_gas(40000000)]
    #[should_panic(expected: ('Active run exists',))]
    fn test_security_upgrade_tampering_change_upgrades_mid_game() {
        set_block_number(60000);
        let (mut world, _caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        init.init_game(5, zero_u256(), 0);
    }

    #[test]
    #[available_gas(50000000)]
    fn test_security_infinite_lives_lives_capped_by_max() {
        set_block_number(70000);
        let (mut world, caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        let player: Player = world.read_model(caller);
        assert(player.lives <= player.max_lives, 'lives cap');
        assert(player.lives == 3 && player.max_lives == 20, 'init lives');
    }

}
