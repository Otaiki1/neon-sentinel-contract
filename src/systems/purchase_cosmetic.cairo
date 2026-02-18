//! purchase_cosmetic system: spend game coins to unlock kernels, avatars, or skins.
//! Updates PlayerProfile kernel_unlocks, avatar_unlocks, or cosmetic_unlocks (bit N = item N).

/// Item type: 0 = kernel, 1 = avatar, 2 = skin.
const ITEM_TYPE_KERNEL: u8 = 0;
const ITEM_TYPE_AVATAR: u8 = 1;
const ITEM_TYPE_SKIN: u8 = 2;

/// Max item_id (bit index in u64); 0..63.
const MAX_ITEM_ID: u8 = 63;

/// Kernel 0 is always unlocked; valid kernel indices 0..5.
const MAX_KERNEL_ID: u8 = 5;

/// Coin price per cosmetic (constant for now).
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
        COIN_PRICE_PER_COSMETIC, ITEM_TYPE_AVATAR, ITEM_TYPE_KERNEL, ITEM_TYPE_SKIN, MAX_ITEM_ID,
        MAX_KERNEL_ID,
    };
    use super::IPurchaseCosmetic;
    use neon_sentinel::models::PlayerProfile;

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

            // 3. Get profile and check sufficient coins
            let mut profile: PlayerProfile = world.read_model(caller);
            assert(profile.coins >= COIN_PRICE_PER_COSMETIC, 'Insufficient coins');

            let bit = pow2_u64(item_id);

            // 4. Check not already unlocked and set the correct bitfield
            if item_type == ITEM_TYPE_KERNEL {
                assert(
                    (profile.kernel_unlocks & bit) == 0,
                    'Kernel already unlocked',
                );
                profile.kernel_unlocks = profile.kernel_unlocks + bit;
            } else if item_type == ITEM_TYPE_AVATAR {
                assert(
                    (profile.avatar_unlocks & bit) == 0,
                    'Avatar already unlocked',
                );
                profile.avatar_unlocks = profile.avatar_unlocks + bit;
            } else {
                assert(
                    (profile.cosmetic_unlocks & bit) == 0,
                    'Skin already unlocked',
                );
                profile.cosmetic_unlocks = profile.cosmetic_unlocks + bit;
            }

            // 5. Deduct coins and update coin history
            profile.coins -= COIN_PRICE_PER_COSMETIC;
            profile.coin_transaction_log_hash = next_coin_log_hash(
                profile.coin_transaction_log_hash,
                block_number,
                COIN_PRICE_PER_COSMETIC,
            );
            profile.coin_transaction_count += 1;

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
