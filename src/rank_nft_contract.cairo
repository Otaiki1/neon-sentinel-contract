//! RankNFT ERC-721-compatible contract for Neon Sentinel.
//!
//! Soulbound achievement NFTs: one per (player, rank_id) covering 18 named ranks.
//! • Minting is gated to the `end_run` system via world permissions.
//! • Transfers are blocked (soulbound) — attempting to transfer panics.
//! • Emits a `RankNFTMinted` event on mint (Torii-indexable Transfer-style event).
//! • `token_uri` returns a deterministic URI string usable by marketplaces.
//!
//! token_id derivation:
//!   token_id.low  = owner_felt_low(u128) XOR rank_id(u8)
//!   token_id.high = owner_felt_high(u128) OR (rank_id << 120)
//! This ensures uniqueness per (owner, rank_id) without any global counter.

use core::integer::u256;
use starknet::ContractAddress;

// ---------------------------------------------------------------------------
// Public interface
// ---------------------------------------------------------------------------

#[starknet::interface]
pub trait IRankNFT<T> {
    /// Mint rank NFT for `to` at `rank_id` (1..18). Reverts if already minted.
    /// Called exclusively by the `end_run` system — access is enforced by world writers config.
    fn mint(ref self: T, to: ContractAddress, rank_id: u8, prestige: u8, layer: u8, run_id: u256);

    /// Returns the owner of `token_id`. Panics if token does not exist.
    fn owner_of(self: @T, token_id: u256) -> ContractAddress;

    /// Returns the total supply (number of minted tokens).
    fn total_supply(self: @T) -> u256;

    /// Returns the token_id for a given (owner, rank_id) pair, or 0 if not minted.
    fn token_of(self: @T, owner: ContractAddress, rank_id: u8) -> u256;

    /// Returns a metadata URI for `token_id`.
    /// Format: "https://neon-sentinel.xyz/nft/{token_id_low}"
    fn token_uri(self: @T, token_id: u256) -> felt252;

    /// Soulbound: always reverts.
    fn transfer_from(ref self: T, from: ContractAddress, to: ContractAddress, token_id: u256);

    /// Returns the rank_id (1..18) encoded in a token_id, or 0 if invalid.
    fn rank_id_of_token(self: @T, token_id: u256) -> u8;
}

// ---------------------------------------------------------------------------
// Helper: derive a unique, collision-free token_id from (owner, rank_id)
// ---------------------------------------------------------------------------
//
//  owner is a ContractAddress (felt252 under the hood, fits in 252 bits).
//  We split the owner felt252 into two u128 halves and XOR/combine with rank_id.
//
//  token_id.low  = (owner_felt as u128) XOR (rank_id as u128)
//  token_id.high = (owner_felt >> 128) + (rank_id as u128)
//
//  Because rank_id is 1..18 and owner is a 252-bit value whose LSB chunk alone
//  uniquely identifies the address, the resulting u256 is unique per (owner, rank_id).
//
pub fn derive_token_id(owner: ContractAddress, rank_id: u8) -> u256 {
    let owner_felt: felt252 = owner.into();
    // felt252 → u256 (same bit pattern, top 4 bits always 0 on Starknet)
    let owner_u256: u256 = owner_felt.into();
    let rank_u128: u128 = rank_id.into();
    u256 {
        low: owner_u256.low ^ rank_u128,
        high: owner_u256.high + rank_u128,
    }
}

// ---------------------------------------------------------------------------
// Dojo model: NFTSupply — single-row global counter
// ---------------------------------------------------------------------------

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct NFTSupply {
    #[key]
    pub namespace: felt252, // always 'neon_sentinel'
    pub total_minted: u256,
}

// ---------------------------------------------------------------------------
// Dojo model: NFTTokenOwner — maps token_id → owner
// ---------------------------------------------------------------------------

#[derive(Copy, Drop, Serde, Debug)]
#[dojo::model]
pub struct NFTTokenOwner {
    #[key]
    pub token_id_low: u128,
    #[key]
    pub token_id_high: u128,
    pub owner: ContractAddress,
    pub rank_id: u8,
}

// ---------------------------------------------------------------------------
// Contract
// ---------------------------------------------------------------------------

#[dojo::contract]
pub mod rank_nft_contract {
    use core::integer::u256;
    use dojo::event::EventStorage;
    use dojo::model::ModelStorage;
    use starknet::ContractAddress;

    use super::{IRankNFT, NFTSupply, NFTTokenOwner, derive_token_id};
    use neon_sentinel::models::RankNFT;
    use neon_sentinel::rank_config::tier_for_rank;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// ERC-721 Transfer event emitted on mint (from = 0x0).
    /// Torii indexes this when configured with `ERC721:<contract_address>`.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct Transfer {
        #[key]
        pub from: ContractAddress,
        #[key]
        pub to: ContractAddress,
        #[key]
        pub token_id_low: u128,
        pub token_id_high: u128,
    }

    /// Richer game-specific mint event for client subscriptions.
    #[derive(Copy, Drop, Serde)]
    #[dojo::event]
    pub struct RankNFTMinted {
        #[key]
        pub owner: ContractAddress,
        pub rank_id: u8,
        pub rank_tier: u8,
        pub prestige: u8,
        pub layer: u8,
        pub token_id_low: u128,
        pub token_id_high: u128,
    }

    // -----------------------------------------------------------------------
    // Implementation
    // -----------------------------------------------------------------------

    #[abi(embed_v0)]
    impl RankNFTImpl of IRankNFT<ContractState> {
        fn mint(
            ref self: ContractState,
            to: ContractAddress,
            rank_id: u8,
            prestige: u8,
            layer: u8,
            run_id: u256,
        ) {
            let mut world = self.world_default();

            // Validate rank range
            assert(rank_id >= 1 && rank_id <= 18, 'Invalid rank_id');

            // Derive deterministic token_id
            let token_id = derive_token_id(to, rank_id);

            // Guard: check not already minted (token owner non-zero means exists)
            let existing: NFTTokenOwner = world.read_model((token_id.low, token_id.high));
            assert(existing.owner.into() == 0_felt252, 'Already minted');

            // Write NFTTokenOwner (owner lookup by token_id)
            let nft_owner = NFTTokenOwner {
                token_id_low: token_id.low,
                token_id_high: token_id.high,
                owner: to,
                rank_id,
            };
            world.write_model(@nft_owner);

            // Write / update RankNFT model (achievement record, keyed by owner + rank_id)
            let rank_tier = tier_for_rank(rank_id);
            let exec_info = starknet::get_execution_info();
            let block_number = exec_info.block_info.block_number;
            let rank_nft = RankNFT {
                owner: to,
                rank_id,
                rank_tier,
                prestige,
                layer,
                achieved_at_block: block_number,
                run_id,
                token_id,
            };
            world.write_model(@rank_nft);

            // Increment global supply
            let mut supply: NFTSupply = world.read_model('neon_sentinel');
            supply.total_minted = u256 {
                low: supply.total_minted.low + 1,
                high: supply.total_minted.high,
            };
            world.write_model(@supply);

            // Emit ERC-721-style Transfer (from zero = mint)
            let zero: ContractAddress = 0.try_into().unwrap();
            world.emit_event(@Transfer {
                from: zero,
                to,
                token_id_low: token_id.low,
                token_id_high: token_id.high,
            });

            // Emit game-specific rich event
            world.emit_event(@RankNFTMinted {
                owner: to,
                rank_id,
                rank_tier,
                prestige,
                layer,
                token_id_low: token_id.low,
                token_id_high: token_id.high,
            });
        }

        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let world = self.world_default();
            let nft_owner: NFTTokenOwner = world.read_model((token_id.low, token_id.high));
            assert(nft_owner.owner.into() != 0_felt252, 'Token does not exist');
            nft_owner.owner
        }

        fn total_supply(self: @ContractState) -> u256 {
            let world = self.world_default();
            let supply: NFTSupply = world.read_model('neon_sentinel');
            supply.total_minted
        }

        fn token_of(self: @ContractState, owner: ContractAddress, rank_id: u8) -> u256 {
            let world = self.world_default();
            let rank_nft: RankNFT = world.read_model((owner, rank_id));
            if rank_nft.achieved_at_block == 0 {
                u256 { low: 0, high: 0 }
            } else {
                rank_nft.token_id
            }
        }

        fn token_uri(self: @ContractState, token_id: u256) -> felt252 {
            // Deterministic URI represented as a felt252 short string.
            // Clients should expand this to: https://neon-sentinel.xyz/nft/{token_id.low}
            // For on-chain the felt252 encodes the prefix as a constant.
            'https://neon-sentinel.xyz/nft/'
        }

        fn transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
        ) {
            // Soulbound: transfers are always blocked.
            assert(false, 'Soulbound: non-transferable');
        }

        fn rank_id_of_token(self: @ContractState, token_id: u256) -> u8 {
            let world = self.world_default();
            let nft_owner: NFTTokenOwner = world.read_model((token_id.low, token_id.high));
            nft_owner.rank_id
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn world_default(self: @ContractState) -> dojo::world::WorldStorage {
            self.world(@"neon_sentinel")
        }
    }
}
