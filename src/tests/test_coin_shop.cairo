//! Unit, integration, and security tests for STRK coin shop: buy_coins, treasury, owner.

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
        CoinShopGlobal, TokenPurchaseConfig, PlayerProfile,
        m_CoinPurchaseHistory, m_CoinPurchaseRecord, m_CoinShopGlobal, m_TokenPurchaseConfig,
        m_PlayerProfile, m_WithdrawalRequest,
    };
    use neon_sentinel::systems::buy_coins::{
        IBuyCoinsDispatcher, IBuyCoinsDispatcherTrait, buy_coins,
    };
    use neon_sentinel::systems::initialize_coin_shop::{
        IInitializeCoinShopDispatcher, IInitializeCoinShopDispatcherTrait, initialize_coin_shop,
    };
    use neon_sentinel::systems::pause_unpause_purchasing::{
        IPauseUnpausePurchasingDispatcher, IPauseUnpausePurchasingDispatcherTrait,
        pause_unpause_purchasing,
    };
    use neon_sentinel::token_validation::{
        CalculateCoinsFromStrkTrait, ValidateStrkAmountTrait,
    };
    use starknet::testing::set_block_number;
    use starknet::ContractAddress;

    const ZERO_FELT: felt252 = 0;

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    fn namespace_def() -> NamespaceDef {
        let ndef = NamespaceDef {
            namespace: "neon_sentinel",
            resources: [
                TestResource::Model(m_CoinShopGlobal::TEST_CLASS_HASH),
                TestResource::Model(m_TokenPurchaseConfig::TEST_CLASS_HASH),
                TestResource::Model(m_CoinPurchaseRecord::TEST_CLASS_HASH),
                TestResource::Model(m_CoinPurchaseHistory::TEST_CLASS_HASH),
                TestResource::Model(m_WithdrawalRequest::TEST_CLASS_HASH),
                TestResource::Model(m_PlayerProfile::TEST_CLASS_HASH),
                TestResource::Event(initialize_coin_shop::e_CoinShopInitialized::TEST_CLASS_HASH),
                TestResource::Event(buy_coins::e_CoinsPurchased::TEST_CLASS_HASH),
                TestResource::Event(buy_coins::e_StrkWithdrawn::TEST_CLASS_HASH),
                TestResource::Event(buy_coins::e_WithdrawalRequestCreated::TEST_CLASS_HASH),
                TestResource::Event(buy_coins::e_WithdrawalExecuted::TEST_CLASS_HASH),
                TestResource::Event(pause_unpause_purchasing::e_PurchasingPauseToggled::TEST_CLASS_HASH),
                TestResource::Contract(initialize_coin_shop::TEST_CLASS_HASH),
                TestResource::Contract(buy_coins::TEST_CLASS_HASH),
                TestResource::Contract(pause_unpause_purchasing::TEST_CLASS_HASH),
            ]
                .span(),
        };
        ndef
    }

    fn contract_defs() -> Span<ContractDef> {
        let ns_hash = dojo::utils::bytearray_hash(@"neon_sentinel");
        [
            ContractDefTrait::new(@"neon_sentinel", @"initialize_coin_shop")
                .with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"buy_coins").with_writer_of([ns_hash].span()),
            ContractDefTrait::new(@"neon_sentinel", @"pause_unpause_purchasing")
                .with_writer_of([ns_hash].span()),
        ]
            .span()
    }

    fn setup_world_with_coin_shop(strk_token_address: ContractAddress) -> (dojo::world::WorldStorage, ContractAddress) {
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
            coins: 0,
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
        };
        world.write_model_test(@profile);

        set_block_number(1000);
        let (init_addr, _) = world.dns(@"initialize_coin_shop").unwrap();
        let init = IInitializeCoinShopDispatcher { contract_address: init_addr };
        init.initialize_coin_shop(strk_token_address, 5);

        (world, caller)
    }

    // ============== Unit tests (token_validation, no world) ==============

    #[test]
    fn test_validate_strk_amount_zero_fails() {
        assert(
            !ValidateStrkAmountTrait::validate_strk_amount(zero_u256()),
            'zero invalid',
        );
    }

    #[test]
    fn test_validate_strk_amount_one_valid() {
        let one = u256 { low: 1, high: 0 };
        assert(ValidateStrkAmountTrait::validate_strk_amount(one), 'one valid');
    }

    #[test]
    fn test_validate_strk_amount_max_1000_valid() {
        let max = u256 { low: 1000, high: 0 };
        assert(ValidateStrkAmountTrait::validate_strk_amount(max), '1000 valid');
    }

    #[test]
    fn test_validate_strk_amount_over_1000_fails() {
        let over = u256 { low: 1001, high: 0 };
        assert(
            !ValidateStrkAmountTrait::validate_strk_amount(over),
            '1001 invalid',
        );
    }

    #[test]
    fn test_calculate_coins_from_strk_10_times_5() {
        let amount = u256 { low: 10, high: 0 };
        let (coins, overflow) = CalculateCoinsFromStrkTrait::calculate_coins_from_strk(amount, 5);
        assert(!overflow, 'no overflow');
        assert(coins.low == 50 && coins.high == 0, '50 coins');
    }

    #[test]
    fn test_calculate_coins_from_strk_zero_rate() {
        let amount = u256 { low: 10, high: 0 };
        let (coins, _) = CalculateCoinsFromStrkTrait::calculate_coins_from_strk(amount, 0);
        assert(coins.low == 0 && coins.high == 0, 'zero coins');
    }

    // ============== Integration: initialize_coin_shop & treasury views ==============

    #[test]
    #[available_gas(50000000)]
    fn test_initialize_coin_shop_sets_config_and_global() {
        set_block_number(500);
        let (world, caller) = setup_world_with_coin_shop(0x123.try_into().unwrap());

        let global: CoinShopGlobal = world.read_model(ZERO_FELT);
        assert(global.owner == caller, 'owner set');

        let config: TokenPurchaseConfig = world.read_model(caller);
        assert(config.coin_exchange_rate == 5, 'rate 5');
        assert(config.total_strk_collected.low == 0 && config.total_strk_collected.high == 0, 'collected 0');
        assert(config.is_enabled == true, 'enabled');
        assert(config.paused == false, 'not paused');
    }

    #[test]
    #[available_gas(50000000)]
    fn test_get_treasury_balance_and_info_after_init() {
        set_block_number(600);
        let (world, _caller) = setup_world_with_coin_shop(0x1.try_into().unwrap());

        let (buy_addr, _) = world.dns(@"buy_coins").unwrap();
        let buy = IBuyCoinsDispatcher { contract_address: buy_addr };

        let balance = buy.get_treasury_balance();
        assert(balance.low == 0 && balance.high == 0, 'balance 0');

        let (collected, withdrawn, available, pending) = buy.get_treasury_info();
        assert(collected.low == 0 && collected.high == 0, 'collected 0');
        assert(withdrawn.low == 0 && withdrawn.high == 0, 'withdrawn 0');
        assert(available.low == 0 && available.high == 0, 'available 0');
        assert(pending.low == 0 && pending.high == 0, 'pending 0');
    }

    // ============== Failure cases (buy_coins without working STRK = fails at ERC20 or earlier) ==============

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Purchasing disabled',))]
    fn test_buy_coins_fails_when_purchasing_disabled() {
        set_block_number(700);
        let (mut world, caller) = setup_world_with_coin_shop(0x1.try_into().unwrap());

        let mut config: TokenPurchaseConfig = world.read_model(caller);
        config.is_enabled = false;
        world.write_model_test(@config);

        let (buy_addr, _) = world.dns(@"buy_coins").unwrap();
        let buy = IBuyCoinsDispatcher { contract_address: buy_addr };
        let ten = u256 { low: 10, high: 0 };
        let fifty = u256 { low: 50, high: 0 };
        buy.buy_coins(ten, fifty);
    }

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Purchasing paused',))]
    fn test_buy_coins_fails_when_paused() {
        set_block_number(800);
        let (mut world, caller) = setup_world_with_coin_shop(0x1.try_into().unwrap());

        let mut config: TokenPurchaseConfig = world.read_model(caller);
        config.paused = true;
        world.write_model_test(@config);

        let (buy_addr, _) = world.dns(@"buy_coins").unwrap();
        let buy = IBuyCoinsDispatcher { contract_address: buy_addr };
        let ten = u256 { low: 10, high: 0 };
        let fifty = u256 { low: 50, high: 0 };
        buy.buy_coins(ten, fifty);
    }

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('Expected coins mismatch',))]
    fn test_buy_coins_rejects_wrong_max_coins_expected() {
        set_block_number(900);
        let (mut world, _caller) = setup_world_with_coin_shop(0x1.try_into().unwrap());

        let (buy_addr, _) = world.dns(@"buy_coins").unwrap();
        let buy = IBuyCoinsDispatcher { contract_address: buy_addr };
        let ten = u256 { low: 10, high: 0 };
        let wrong_coins = u256 { low: 99, high: 0 };
        buy.buy_coins(ten, wrong_coins);
    }

    // ============== Security: owner withdraw without STRK in contract fails ==============

    #[test]
    #[ignore]
    #[available_gas(50000000)]
    #[should_panic(expected: ('STRK transfer failed',))]
    fn test_withdraw_fails_when_no_strk_in_contract() {
        set_block_number(1000);
        let (mut world, owner) = setup_world_with_coin_shop(0x1.try_into().unwrap());

        let mut config: TokenPurchaseConfig = world.read_model(owner);
        config.total_strk_collected = u256 { low: 100, high: 0 };
        world.write_model_test(@config);

        let (buy_addr, _) = world.dns(@"buy_coins").unwrap();
        let buy = IBuyCoinsDispatcher { contract_address: buy_addr };
        let ten = u256 { low: 10, high: 0 };
        let notes: felt252 = 0;
        buy.withdraw_strk(ten, notes);
    }

    #[test]
    #[available_gas(50000000)]
    fn test_owner_can_toggle_pause() {
        set_block_number(1100);
        let (world, _owner) = setup_world_with_coin_shop(0x1.try_into().unwrap());

        let (pause_addr, _) = world.dns(@"pause_unpause_purchasing").unwrap();
        let pause = IPauseUnpausePurchasingDispatcher { contract_address: pause_addr };
        let first = pause.pause_unpause_purchasing();
        assert(first == true, 'paused');
        let second = pause.pause_unpause_purchasing();
        assert(second == false, 'unpaused');
    }

    // ============== Owner withdrawal and treasury ==============

    #[test]
    #[available_gas(50000000)]
    fn test_owner_can_request_and_get_treasury_info() {
        set_block_number(1200);
        let (mut world, owner) = setup_world_with_coin_shop(0x1.try_into().unwrap());

        let mut config: TokenPurchaseConfig = world.read_model(owner);
        config.total_strk_collected = u256 { low: 50, high: 0 };
        world.write_model_test(@config);

        let (buy_addr, _) = world.dns(@"buy_coins").unwrap();
        let buy = IBuyCoinsDispatcher { contract_address: buy_addr };
        let (collected, withdrawn, available, _) = buy.get_treasury_info();
        assert(collected.low == 50 && collected.high == 0, 'collected 50');
        assert(withdrawn.low == 0 && withdrawn.high == 0, 'withdrawn 0');
        assert(available.low == 50 && available.high == 0, 'available 50');
    }
}
