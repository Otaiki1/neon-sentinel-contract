//! Coin and purchase catalog constants (Option A). Frontend can mirror these for UX.
//! Bit index 0..6 = pregame upgrade IDs; kernel_id 0..10; mini_me unit_type 0..6.

/// Pregame upgrade prices (one-time per run). Bit N in mask => price at index N.
/// 0=Extra Heart 25, 1=Double Heart 50, 2=Reinforced Core 40, 3=Overcharged Gun 45,
/// 4=Rapid Fire 40, 5=Extended Boost 35, 6=Agility Pack 30.
pub const PRICE_PREGAME_0: u32 = 25;  // Extra Heart
pub const PRICE_PREGAME_1: u32 = 50;  // Double Heart
pub const PRICE_PREGAME_2: u32 = 40;  // Reinforced Core
pub const PRICE_PREGAME_3: u32 = 45;  // Overcharged Gun
pub const PRICE_PREGAME_4: u32 = 40;  // Rapid Fire
pub const PRICE_PREGAME_5: u32 = 35;  // Extended Boost
pub const PRICE_PREGAME_6: u32 = 30;  // Agility Pack

/// Number of pregame upgrades (bit indices 0..6).
pub const NUM_PREGAME_UPGRADES: u8 = 7;

/// Revive: cost = REVIVE_BASE * 2^revive_count. 1st=100, 2nd=200, 3rd=400, ...
pub const REVIVE_BASE_COINS: u32 = 100;

/// Kernel prices (kernel_id 0..10). Kernel 0 is free and always unlocked.
pub const PRICE_KERNEL_0: u32 = 0;
pub const PRICE_KERNEL_1: u32 = 500;
pub const PRICE_KERNEL_2: u32 = 500;
pub const PRICE_KERNEL_3: u32 = 1500;
pub const PRICE_KERNEL_4: u32 = 1500;
pub const PRICE_KERNEL_5: u32 = 2000;
pub const PRICE_KERNEL_6: u32 = 3000;
pub const PRICE_KERNEL_7: u32 = 3500;
pub const PRICE_KERNEL_8: u32 = 4000;
pub const PRICE_KERNEL_9: u32 = 5000;
pub const PRICE_KERNEL_10: u32 = 7500;

/// Prestige required to purchase/unlock each kernel (0..10). Kernel 10 also requires is_prime_sentinel.
pub const PRESTIGE_KERNEL_0: u8 = 0;
pub const PRESTIGE_KERNEL_1: u8 = 1;
pub const PRESTIGE_KERNEL_2: u8 = 1;
pub const PRESTIGE_KERNEL_3: u8 = 2;
pub const PRESTIGE_KERNEL_4: u8 = 2;
pub const PRESTIGE_KERNEL_5: u8 = 3;
pub const PRESTIGE_KERNEL_6: u8 = 4;
pub const PRESTIGE_KERNEL_7: u8 = 4;
pub const PRESTIGE_KERNEL_8: u8 = 5;
pub const PRESTIGE_KERNEL_9: u8 = 6;
pub const PRESTIGE_KERNEL_10: u8 = 8;

/// Kernel 10 (Transcendent Form) requires defeating final boss (is_prime_sentinel = P8 L6).
pub const KERNEL_10_ID: u8 = 10;

/// Max kernel index (kernels 0..10).
pub const MAX_KERNEL_ID: u8 = 10;

/// Mini-Me unit prices (unit_type 0..6). Scout, Gunner, Shield, Decoy, Collector, Stun, Healer.
pub const PRICE_MINI_ME_0: u32 = 50;   // Scout
pub const PRICE_MINI_ME_1: u32 = 75;   // Gunner
pub const PRICE_MINI_ME_2: u32 = 100;  // Shield
pub const PRICE_MINI_ME_3: u32 = 100;  // Decoy
pub const PRICE_MINI_ME_4: u32 = 75;   // Collector
pub const PRICE_MINI_ME_5: u32 = 125;  // Stun
pub const PRICE_MINI_ME_6: u32 = 125;  // Healer

/// Max Mini-Me unit type index (7 types: 0..6).
pub const MAX_MINI_ME_TYPE: u8 = 6;

/// Max units per type in inventory.
pub const MAX_MINI_ME_UNITS_PER_TYPE: u8 = 20;

/// Mini-Me sessions pack: 100 coins = +3 sessions (permanent).
pub const PRICE_MINI_ME_SESSIONS_PACK: u32 = 100;
