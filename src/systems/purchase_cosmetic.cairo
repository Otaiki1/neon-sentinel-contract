//! purchase_cosmetic system: spend game coins to unlock kernels, avatars, or skins.
//! Updates PlayerProfile kernel_unlocks, avatar_unlocks, or cosmetic_unlocks (bit N = item N).

/// Item type: 0 = kernel, 1 = avatar, 2 = skin.
const ITEM_TYPE_KERNEL: u8 = 0;
const ITEM_TYPE_AVATAR: u8 = 1;
const ITEM_TYPE_SKIN: u8 = 2;

/// Max item_id (bit index in u64); 0..63.
const MAX_ITEM_ID: u8 = 63;

/// Kernel 0 is always unlocked; valid kernel indices 0..10.
const MAX_KERNEL_ID: u8 = 10;

/// Kernel 10 (Transcendent) requires is_prime_sentinel (P8 L6).
const KERNEL_10_ID: u8 = 10;

/// Coin price per cosmetic for avatar/skin (non-kernel).
const COIN_PRICE_PER_COSMETIC: u32 = 1;

#[starknet::interface]
pub trait IPurchaseCosmetic<T> {
    fn purchase_cosmetic(ref self: T, item_type: u8, item_id: u8);
}

#[dojo::contract]
pub mod purchase_cosmetic {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::{
        COIN_PRICE_PER_COSMETIC, ITEM_TYPE_AVATAR, ITEM_TYPE_KERNEL, ITEM_TYPE_SKIN, KERNEL_10_ID,
        MAX_ITEM_ID, MAX_KERNEL_ID,
    };
    use super::IPurchaseCosmetic;
    use neon_sentinel::coin_shop_config::{
        PRESTIGE_KERNEL_0, PRESTIGE_KERNEL_1, PRESTIGE_KERNEL_2, PRESTIGE_KERNEL_3,
        PRESTIGE_KERNEL_4, PRESTIGE_KERNEL_5, PRESTIGE_KERNEL_6, PRESTIGE_KERNEL_7,
        PRESTIGE_KERNEL_8, PRESTIGE_KERNEL_9, PRESTIGE_KERNEL_10,
        PRICE_KERNEL_0, PRICE_KERNEL_1, PRICE_KERNEL_2, PRICE_KERNEL_3, PRICE_KERNEL_4,
        PRICE_KERNEL_5, PRICE_KERNEL_6, PRICE_KERNEL_7, PRICE_KERNEL_8, PRICE_KERNEL_9,
        PRICE_KERNEL_10,
    };
    use neon_sentinel::models::PlayerProfile;

    fn kernel_price(kernel_id: u8) -> u32 {
        if kernel_id == 0 {
            PRICE_KERNEL_0
        } else if kernel_id == 1 {
            PRICE_KERNEL_1
        } else if kernel_id == 2 {
            PRICE_KERNEL_2
        } else if kernel_id == 3 {
            PRICE_KERNEL_3
        } else if kernel_id == 4 {
            PRICE_KERNEL_4
        } else if kernel_id == 5 {
            PRICE_KERNEL_5
        } else if kernel_id == 6 {
            PRICE_KERNEL_6
        } else if kernel_id == 7 {
            PRICE_KERNEL_7
        } else if kernel_id == 8 {
            PRICE_KERNEL_8
        } else if kernel_id == 9 {
            PRICE_KERNEL_9
        } else {
            PRICE_KERNEL_10
        }
    }

    fn kernel_prestige_required(kernel_id: u8) -> u8 {
        if kernel_id == 0 {
            PRESTIGE_KERNEL_0
        } else if kernel_id == 1 {
            PRESTIGE_KERNEL_1
        } else if kernel_id == 2 {
            PRESTIGE_KERNEL_2
        } else if kernel_id == 3 {
            PRESTIGE_KERNEL_3
        } else if kernel_id == 4 {
            PRESTIGE_KERNEL_4
        } else if kernel_id == 5 {
            PRESTIGE_KERNEL_5
        } else if kernel_id == 6 {
            PRESTIGE_KERNEL_6
        } else if kernel_id == 7 {
            PRESTIGE_KERNEL_7
        } else if kernel_id == 8 {
            PRESTIGE_KERNEL_8
        } else if kernel_id == 9 {
            PRESTIGE_KERNEL_9
        } else {
            PRESTIGE_KERNEL_10
        }
    }

    /// 2^n for n in 0..=63 (bit position).
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

    /// Append transaction to log hash chain (same as spend_coins).
    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 { low: prev.low + bl + am, high: prev.high + 1 }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CosmeticPurchased {
        #[key]
        pub player: ContractAddress,
        pub item_type: u8,
        pub item_id: u8,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl PurchaseCosmeticImpl of IPurchaseCosmetic<ContractState> {
        fn purchase_cosmetic(ref self: ContractState, item_type: u8, item_id: u8) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1. Validate item_type (0, 1, 2)
            assert(
                item_type == ITEM_TYPE_KERNEL || item_type == ITEM_TYPE_AVATAR
                    || item_type == ITEM_TYPE_SKIN,
                'Invalid item type',
            );

            // 2. Validate item_id (for kernel 0..5; for avatar/skin 0..63)
            assert(item_id <= MAX_ITEM_ID, 'Item id out of range');
            if item_type == ITEM_TYPE_KERNEL {
                assert(item_id <= MAX_KERNEL_ID, 'Kernel id out of range');
                // Kernel 0 is always unlocked; cannot purchase again
                assert(item_id > 0, 'Kernel 0 is free');
            }

            // 3. Get profile
            let mut profile: PlayerProfile = world.read_model(caller);

            let bit = pow2_u64(item_id);

            // 4. For kernel: prestige, is_prime_sentinel (kernel 10), price, and not already unlocked
            if item_type == ITEM_TYPE_KERNEL {
                assert(
                    profile.current_prestige >= kernel_prestige_required(item_id),
                    'Prestige too low for kernel',
                );
                if item_id == KERNEL_10_ID {
                    assert(profile.is_prime_sentinel, 'Need Prime Sentinel');
                }
                let price = kernel_price(item_id);
                assert(profile.coins >= price, 'Insufficient coins');
                assert(
                    (profile.kernel_unlocks & bit) == 0,
                    'Kernel already unlocked',
                );
                profile.kernel_unlocks = profile.kernel_unlocks + bit;
                profile.coins -= price;
                profile.coin_transaction_log_hash =
                    next_coin_log_hash(profile.coin_transaction_log_hash, block_number, price);
                profile.coin_transaction_count += 1;
            } else {
                assert(profile.coins >= COIN_PRICE_PER_COSMETIC, 'Insufficient coins');
            }

            // 5. Avatar/skin: check not already unlocked and set bitfield; deduct coins
            if item_type == ITEM_TYPE_AVATAR {
                assert(
                    (profile.avatar_unlocks & bit) == 0,
                    'Avatar already unlocked',
                );
                profile.avatar_unlocks = profile.avatar_unlocks + bit;
                profile.coins -= COIN_PRICE_PER_COSMETIC;
                profile.coin_transaction_log_hash = next_coin_log_hash(
                    profile.coin_transaction_log_hash,
                    block_number,
                    COIN_PRICE_PER_COSMETIC,
                );
                profile.coin_transaction_count += 1;
            } else if item_type == ITEM_TYPE_SKIN {
                assert(
                    (profile.cosmetic_unlocks & bit) == 0,
                    'Skin already unlocked',
                );
                profile.cosmetic_unlocks = profile.cosmetic_unlocks + bit;
                profile.coins -= COIN_PRICE_PER_COSMETIC;
                profile.coin_transaction_log_hash = next_coin_log_hash(
                    profile.coin_transaction_log_hash,
                    block_number,
                    COIN_PRICE_PER_COSMETIC,
                );
                profile.coin_transaction_count += 1;
            }

            // 6. If kernel, set selected_kernel to the newly purchased one
            if item_type == ITEM_TYPE_KERNEL {
                profile.selected_kernel = item_id;
            }

            world.write_model(@profile);

            // 7. Emit event
            world.emit_event(@CosmeticPurchased {
                player: caller,
                item_type,
                item_id,
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
