//! claim_coins system: allows players to claim daily coins.
//! Uses block numbers for timing (24h ≈ 7200 blocks); records in coin history and emits event.

/// 24 hours ≈ 7200 blocks (at ~12s per block).
const BLOCKS_PER_DAY: u64 = 7200;

/// Coins granted per daily claim.
const COINS_PER_CLAIM: u32 = 3;

#[starknet::interface]
pub trait IClaimCoins<T> {
    fn claim_coins(ref self: T);
}

#[dojo::contract]
pub mod claim_coins {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::{ContractAddress, get_caller_address, get_execution_info};

    use super::{BLOCKS_PER_DAY, COINS_PER_CLAIM};
    use super::IClaimCoins;
    use neon_sentinel::models::PlayerProfile;

    fn zero_u256() -> u256 {
        u256 { low: 0, high: 0 }
    }

    /// Append transaction to log hash chain (deterministic).
    fn next_coin_log_hash(prev: u256, block_number: u64, amount: u32) -> u256 {
        let bl: u128 = block_number.try_into().unwrap();
        let am: u128 = amount.try_into().unwrap();
        u256 {
            low: prev.low + bl + am,
            high: prev.high + 1,
        }
    }

    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct CoinClaimed {
        #[key]
        pub player: ContractAddress,
        pub amount: u32,
        pub block_number: u64,
    }

    #[abi(embed_v0)]
    impl ClaimCoinsImpl of IClaimCoins<ContractState> {
        fn claim_coins(ref self: ContractState) {
            let mut world = self.world_default();
            let caller = get_caller_address();
            let exec_info = get_execution_info();
            let block_number = exec_info.block_info.block_number;

            // 1. Get player's profile
            let mut profile: PlayerProfile = world.read_model(caller);

            // 2. Check 24 hours (≈7200 blocks) have passed since last claim
            //    Allow first claim when last_coin_claim_block == 0
            let blocks_since_claim = block_number - profile.last_coin_claim_block;
            let can_claim = profile.last_coin_claim_block == 0
                || blocks_since_claim >= BLOCKS_PER_DAY;
            assert(can_claim, 'Too soon to claim');

            // 3. Add 3 coins to player balance
            profile.coins += COINS_PER_CLAIM;

            // 4. Update last_coin_claim_block = current block
            profile.last_coin_claim_block = block_number;

            // 5. Record transaction in coin history (update log hash chain)
            profile.coin_transaction_log_hash = next_coin_log_hash(
                profile.coin_transaction_log_hash,
                block_number,
                COINS_PER_CLAIM,
            );

            // 6. Increment coin_transaction_count
            profile.coin_transaction_count += 1;

            world.write_model(@profile);

            // 7. Emit event for logging
            world.emit_event(@CoinClaimed {
                player: caller,
                amount: COINS_PER_CLAIM,
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
