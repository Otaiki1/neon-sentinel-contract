//! Rank catalog: 18 named ranks at (prestige, layer) milestones and 5 display tiers.
//! FE aligns via RANK_CONFIG; chain uses rank_id 1..18 and tier 1..5 (entry..legendary).

/// Tier display enum (u8): 1=entry, 2=intermediate, 3=advanced, 4=elite, 5=legendary.
pub const TIER_ENTRY: u8 = 1;
pub const TIER_INTERMEDIATE: u8 = 2;
pub const TIER_ADVANCED: u8 = 3;
pub const TIER_ELITE: u8 = 4;
pub const TIER_LEGENDARY: u8 = 5;

/// Number of ranks (1..18).
pub const NUM_RANKS: u8 = 18;

/// Returns rank_id (1..18) for the given (prestige, layer) milestone, or 0 if not a defined rank.
/// Mapping: (0,1)→1, (0,3)→2, (0,6)→3, (1,3)→4, (1,6)→5, (2,3)→6, (2,6)→7, (3,3)→8, (3,6)→9,
/// (4,3)→10, (4,6)→11, (5,3)→12, (5,6)→13, (6,3)→14, (6,6)→15, (7,3)→16, (7,6)→17, (8,6)→18.
pub fn rank_id_for_milestone(prestige: u8, layer: u8) -> u8 {
    if prestige == 0 {
        if layer == 1 {
            return 1;
        }
        if layer == 3 {
            return 2;
        }
        if layer == 6 {
            return 3;
        }
    }
    if prestige == 1 {
        if layer == 3 {
            return 4;
        }
        if layer == 6 {
            return 5;
        }
    }
    if prestige == 2 {
        if layer == 3 {
            return 6;
        }
        if layer == 6 {
            return 7;
        }
    }
    if prestige == 3 {
        if layer == 3 {
            return 8;
        }
        if layer == 6 {
            return 9;
        }
    }
    if prestige == 4 {
        if layer == 3 {
            return 10;
        }
        if layer == 6 {
            return 11;
        }
    }
    if prestige == 5 {
        if layer == 3 {
            return 12;
        }
        if layer == 6 {
            return 13;
        }
    }
    if prestige == 6 {
        if layer == 3 {
            return 14;
        }
        if layer == 6 {
            return 15;
        }
    }
    if prestige == 7 {
        if layer == 3 {
            return 16;
        }
        if layer == 6 {
            return 17;
        }
    }
    if prestige == 8 && layer == 6 {
        return 18;
    }
    0
}

/// Returns tier (1..5) for display for the given rank_id (1..18).
/// 1–3 entry, 4–5 entry, 6–7 intermediate, 8–9 intermediate, 10–11 advanced, 12–13 advanced,
/// 14–15 elite, 16–17 elite, 18 legendary.
pub fn tier_for_rank(rank_id: u8) -> u8 {
    if rank_id >= 1 && rank_id <= 3 {
        return TIER_ENTRY;
    }
    if rank_id >= 4 && rank_id <= 5 {
        return TIER_ENTRY;
    }
    if rank_id >= 6 && rank_id <= 7 {
        return TIER_INTERMEDIATE;
    }
    if rank_id >= 8 && rank_id <= 9 {
        return TIER_INTERMEDIATE;
    }
    if rank_id >= 10 && rank_id <= 11 {
        return TIER_ADVANCED;
    }
    if rank_id >= 12 && rank_id <= 13 {
        return TIER_ADVANCED;
    }
    if rank_id >= 14 && rank_id <= 15 {
        return TIER_ELITE;
    }
    if rank_id >= 16 && rank_id <= 17 {
        return TIER_ELITE;
    }
    if rank_id == 18 {
        return TIER_LEGENDARY;
    }
    TIER_ENTRY
}
