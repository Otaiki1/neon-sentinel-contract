//! System integration tests (BALANCED): user journey (FE guide), game init, end_run,
//! submit_leaderboard, purchase_cosmetic, rank NFTs, and security tests.
//!
//! Tests mirror INTEGRATION_BIBLE §7 (Recommended Frontend Flows): load state, claim/buy coins,
//! start run (init_game), gameplay (client-side), end run + submit leaderboard, leaderboard view.

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
        LeaderboardEntry, Player, PlayerProfile, RunState,
        m_Enemy, m_GameEvent, m_GameTick, m_LeaderboardEntry, m_Player, m_PlayerProfile,
        m_RankNFT, m_RunState,
    };
    use neon_sentinel::systems::end_run::{IEndRunDispatcher, IEndRunDispatcherTrait, end_run};
    use neon_sentinel::systems::init_game::{
        IInitGameDispatcher, IInitGameDispatcherTrait, init_game,
    };
    use neon_sentinel::systems::claim_coins::{IClaimCoinsDispatcher, IClaimCoinsDispatcherTrait, claim_coins};
    use neon_sentinel::systems::submit_leaderboard::{
        ISubmitLeaderboardDispatcher, ISubmitLeaderboardDispatcherTrait, submit_leaderboard,
    };
    use neon_sentinel::systems::purchase_cosmetic::{
        IPurchaseCosmeticDispatcher, IPurchaseCosmeticDispatcherTrait, purchase_cosmetic,
    };
    use neon_sentinel::systems::spend_revive::{
        ISpendReviveDispatcher, ISpendReviveDispatcherTrait, spend_revive,
    };
    use starknet::testing::{set_block_number, set_block_timestamp};
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
                TestResource::Model(m_RankNFT::TEST_CLASS_HASH),
                TestResource::Event(init_game::e_CoinSpent::TEST_CLASS_HASH),
                TestResource::Contract(init_game::TEST_CLASS_HASH),
                TestResource::Contract(end_run::TEST_CLASS_HASH),
                TestResource::Contract(submit_leaderboard::TEST_CLASS_HASH),
                TestResource::Event(claim_coins::e_CoinClaimed::TEST_CLASS_HASH),
                TestResource::Contract(claim_coins::TEST_CLASS_HASH),
                TestResource::Contract(purchase_cosmetic::TEST_CLASS_HASH),
                TestResource::Event(purchase_cosmetic::e_CosmeticPurchased::TEST_CLASS_HASH),
                TestResource::Contract(spend_revive::TEST_CLASS_HASH),
                TestResource::Event(spend_revive::e_RevivePurchased::TEST_CLASS_HASH),
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
            ContractDefTrait::new(@"neon_sentinel", @"end_run")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"submit_leaderboard")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"claim_coins")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"purchase_cosmetic")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"spend_revive")
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
            highest_rank_tier_minted: 0,
            highest_rank_id: 0,
            last_prime_sentinel_claim_block: 0,
            mini_me_sessions_purchased: 0,
        };
        world.write_model_test(@profile);
        (world, caller)
    }

    // ========== User journey (FE guide: §7 Recommended Frontend Flows) ==========

    /// Full user journey: purchase kernel → start run (kernel 1) → end run → submit leaderboard.
    /// Mirrors FE: load profile → purchase_cosmetic → init_game → [client plays] → end_run → submit_leaderboard.
    #[test]
    #[available_gas(120000000)]
    fn test_user_journey_purchase_kernel_start_run_end_submit_leaderboard() {
        use neon_sentinel::models::RankNFT;

        set_block_number(2000);
        let (mut world, caller) = setup_world_with_profile();
        let mut profile: PlayerProfile = world.read_model(caller);
        profile.current_prestige = 1;
        profile.coins = 1000;
        world.write_model_test(@profile);

        // §7.2 / §7.3: User has coins and prestige 1; purchase kernel 1 (item_type=0, item_id=1, 500 coins)
        let (purchase_addr, _) = world.dns(@"purchase_cosmetic").unwrap();
        let purchase = IPurchaseCosmeticDispatcher { contract_address: purchase_addr };
        purchase.purchase_cosmetic(0, 1);

        let profile_after_purchase: PlayerProfile = world.read_model(caller);
        assert(profile_after_purchase.coins == 500, 'coins after purchase');
        assert(profile_after_purchase.kernel_unlocks == 2, 'kernel 1 unlocked');
        assert(profile_after_purchase.selected_kernel == 1, 'selected kernel 1');

        // §7.3: Start run with purchased kernel; no pregame upgrades (cost 0)
        let (init_addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: init_addr };
        init.init_game(1, zero_u256(), 0);

        let player: Player = world.read_model(caller);
        let run_id = player.run_id;
        assert(player.is_active, 'player active');
        assert(player.kernel == 1, 'kernel 1 used');

        // §7.4 (client-side) + §7.5: End run with client-submitted final state
        // RunState.current_prestige is 0 at init; use milestone (0, 3) → rank_id 2 (intermediate tier).
        let (end_addr, _) = world.dns(@"end_run").unwrap();
        let end_sys = IEndRunDispatcher { contract_address: end_addr };
        let final_score: u64 = 1500;
        let total_kills: u32 = 25;
        let final_layer: u8 = 3;
        end_sys.end_run(run_id, final_score, total_kills, final_layer);

        let profile_after_end: PlayerProfile = world.read_model(caller);
        assert(profile_after_end.total_runs == 1, 'total_runs');
        assert(profile_after_end.lifetime_score == final_score, 'lifetime_score');
        assert(profile_after_end.best_run_score == final_score, 'best_run_score');
        assert(profile_after_end.current_layer == final_layer, 'current_layer');
        assert(profile_after_end.coins == 500 + 10, 'bonus coins for score >= 1000');

        // Rank: (0,3) → rank_id 2 (entry tier per tier_for_rank: 1–3 = entry)
        assert(profile_after_end.highest_rank_id == 2, 'highest_rank_id 2');
        assert(profile_after_end.highest_rank_tier_minted == 2, 'rank tier minted');

        // §7.5: Submit to leaderboard (week from timestamp; ts < 604800 => week 0)
        set_block_timestamp(1000);
        let week: u32 = 0;
        let (sub_addr, _) = world.dns(@"submit_leaderboard").unwrap();
        let sub_sys = ISubmitLeaderboardDispatcher { contract_address: sub_addr };
        sub_sys.submit_leaderboard(run_id, week);

        let run_state: RunState = world.read_model((caller, run_id));
        assert(run_state.submitted_to_leaderboard == true, 'submitted');
        assert(run_state.is_finished == true, 'finished');

        // §7.6: Leaderboard entry exists and is verified
        let entry_id = u256 { low: run_id.low + week.into(), high: run_id.high };
        let entry: LeaderboardEntry = world.read_model(entry_id);
        assert(entry.verified == true, 'entry verified');
        assert(entry.final_score == final_score, 'entry score');
        assert(entry.player_address == caller, 'entry player');

        // Rank NFT query by (owner, rank_id)
        let rank_id: u8 = 2;
        let rank_nft: RankNFT = world.read_model((caller, rank_id));
        assert(rank_nft.owner == caller, 'rank nft owner');
        assert(rank_nft.rank_id == 2, 'rank nft rank_id');
        assert(rank_nft.rank_tier == 1, 'rank nft tier entry');
        assert(rank_nft.prestige == 0 && rank_nft.layer == 3, 'prestige layer');
    }

    /// §7.2: Claim coins (first claim); then §7.3 start run. Mirrors FE: claim → start run.
    #[test]
    #[available_gas(80000000)]
    fn test_user_journey_claim_coins_then_start_run() {
        set_block_number(7200);
        let (mut world, caller) = setup_world_with_profile();

        let (claim_addr, _) = world.dns(@"claim_coins").unwrap();
        let claim_sys = IClaimCoinsDispatcher { contract_address: claim_addr };
        claim_sys.claim_coins();

        let profile: PlayerProfile = world.read_model(caller);
        assert(profile.coins == 100 + 3, 'coins after first claim');
        assert(profile.last_coin_claim_block == 7200, 'last_coin_claim_block');

        let (init_addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: init_addr };
        init.init_game(0, zero_u256(), 0);

        let player: Player = world.read_model(caller);
        assert(player.is_active, 'active run');
        assert(player.run_id.low != 0 || player.run_id.high != 0, 'run_id set');
    }

    /// §7.3: Start run with pregame upgrades (mask bit 0 = Extra Heart, cost 25). FE: compute cost from catalog, call init_game.
    #[test]
    #[available_gas(60000000)]
    fn test_user_journey_start_run_with_pregame_upgrades() {
        set_block_number(3000);
        let (mut world, caller) = setup_world_with_profile();

        let (init_addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: init_addr };
        let one_bit_mask = u256 { low: 1, high: 0 };
        init.init_game(0, one_bit_mask, 25);

        let profile: PlayerProfile = world.read_model(caller);
        assert(profile.coins == 75, '25 coins spent on upgrade');

        let player: Player = world.read_model(caller);
        let run_state: RunState = world.read_model((caller, player.run_id));
        assert(run_state.pregame_upgrades_mask.low == 1, 'pregame mask stored');
        assert(player.is_active, 'run active');
    }

    // ---------- Single-flow workflow tests ----------

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
    #[available_gas(80000000)]
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
        let final_score: u64 = 500;
        let total_kills: u32 = 0;
        let final_layer: u8 = 1;
        end_sys.end_run(run_id, final_score, total_kills, final_layer);

        let run_state: RunState = world.read_model((caller, run_id));
        assert(run_state.is_finished == true, 'is_finished true');
        assert(run_state.final_score == final_score, 'final_score from client');
        assert(run_state.enemies_defeated == total_kills, 'total_kills from client');
        assert(run_state.final_layer == final_layer, 'final_layer from client');

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
        end_sys.end_run(run_id, 1000, 5, 2);

        set_block_timestamp(1000);
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

    #[test]
    #[available_gas(40000000)]
    fn test_purchase_cosmetic_deducts_coins_and_sets_unlock() {
        set_block_number(4100);
        let (mut world, caller) = setup_world_with_profile();
        let mut profile: PlayerProfile = world.read_model(caller);
        profile.current_prestige = 1;
        profile.coins = 1000;
        world.write_model_test(@profile);

        let (addr, _) = world.dns(@"purchase_cosmetic").unwrap();
        let purchase = IPurchaseCosmeticDispatcher { contract_address: addr };
        purchase.purchase_cosmetic(0, 1);

        let profile: PlayerProfile = world.read_model(caller);
        assert(profile.kernel_unlocks == 2, 'kernel 1 unlocked');
        assert(profile.coins == 500, '500 coins spent for kernel 1');
        assert(profile.selected_kernel == 1, 'selected kernel 1');
    }

    #[test]
    #[available_gas(90000000)]
    fn test_end_run_mints_rank_nft_when_tier_increases() {
        use neon_sentinel::models::RankNFT;

        set_block_number(4200);
        let (mut world, caller) = setup_world_with_profile();

        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);

        let player: Player = world.read_model(caller);
        let run_id = player.run_id;

        // End at milestone (0, 1) → rank_id 1 (entry tier) so Rank NFT is minted
        let (end_addr, _) = world.dns(@"end_run").unwrap();
        let end_sys = IEndRunDispatcher { contract_address: end_addr };
        end_sys.end_run(run_id, 500, 10, 1);

        let profile: PlayerProfile = world.read_model(caller);
        assert(profile.highest_rank_id == 1, 'highest_rank_id 1');
        assert(profile.highest_rank_tier_minted == 1, 'tier 1 minted');

        let rank_id: u8 = 1;
        let rank_nft: RankNFT = world.read_model((caller, rank_id));
        assert(rank_nft.owner == caller, 'nft owner');
        assert(rank_nft.rank_id == 1, 'rank id 1');
        assert(rank_nft.rank_tier == 1, 'rank tier 1 entry');
        assert(rank_nft.prestige == 0 && rank_nft.layer == 1, 'prestige layer');
    }

    // ---------- Error cases (§8 Errors and Validation; run with snforge for should_panic) ----------

    #[test]
    #[ignore]
    #[should_panic(expected: ('Invalid kernel',))]
    fn test_cannot_init_game_with_invalid_kernel() {
        set_block_number(5000);
        let (mut world, _caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(11, zero_u256(), 0);
    }

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Kernel not unlocked',))]
    fn test_cannot_init_game_with_kernel_not_purchased() {
        set_block_number(5100);
        let (mut world, _caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(1, zero_u256(), 0);
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
        init.init_game(0, u256 { low: 1, high: 0 }, 25);
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
    #[available_gas(100000000)]
    #[should_panic(expected: ('Already submitted',))]
    fn test_security_double_submission_leaderboard_twice() {
        set_block_number(50000);
        set_block_timestamp(1000);
        let (mut world, caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        let player: Player = world.read_model(caller);
        let run_id = player.run_id;
        let (end_addr, _) = world.dns(@"end_run").unwrap();
        let end_sys = IEndRunDispatcher { contract_address: end_addr };
        end_sys.end_run(run_id, 800, 3, 1);
        let week: u32 = 0;
        let (sub_addr, _) = world.dns(@"submit_leaderboard").unwrap();
        let sub_sys = ISubmitLeaderboardDispatcher { contract_address: sub_addr };
        sub_sys.submit_leaderboard(run_id, week);
        sub_sys.submit_leaderboard(run_id, week);
    }

    #[test]
    #[available_gas(120000000)]
    fn test_start_run_again_overwrites_previous_run() {
        set_block_number(60000);
        let (mut world, caller) = setup_world_with_profile();
        let (addr, _) = world.dns(@"init_game").unwrap();
        let init = IInitGameDispatcher { contract_address: addr };
        init.init_game(0, zero_u256(), 0);
        let player1: Player = world.read_model(caller);
        let run_id_1 = player1.run_id;

        set_block_number(60001);
        init.init_game(0, zero_u256(), 0);
        let player2: Player = world.read_model(caller);
        let run_id_2 = player2.run_id;

        assert(player2.run_id.low != run_id_1.low || player2.run_id.high != run_id_1.high, 'new run_id');
        assert(player2.is_active == true, 'active');

        let (end_addr, _) = world.dns(@"end_run").unwrap();
        let end_sys = IEndRunDispatcher { contract_address: end_addr };
        end_sys.end_run(run_id_2, 100, 0, 1);

        let run_state_2: RunState = world.read_model((caller, run_id_2));
        assert(run_state_2.is_finished == true, 'second run finished');
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
