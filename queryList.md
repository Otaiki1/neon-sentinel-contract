# ⛩️ Neon Sentinel - Torii GraphQL Query List

Use these queries at your Torii endpoint to inspect the world state.

**Endpoint:** `https://api.cartridge.gg/x/neon-sentinel-test/torii/graphql`

---

## 1. Player Profile
Get the core persistent data for a specific player (coins, lifetime stats, rank).

```graphql
query GetPlayerProfile($address: String!) {
  neonSentinelPlayerProfileModels(where: { player_address: $address }) {
    edges {
      node {
        player_address
        coins
        total_runs
        lifetime_score
        best_run_score
        current_layer
        highest_rank_id
        selected_kernel
        mini_me_sessions_purchased
      }
    }
  }
}
```

## 2. Active Run & Game State
Check if a player is currently in a run and get their real-time stats.

```graphql
query GetActiveRun($address: String!) {
  # Player model tracks ephemeral state like position and meters
  neonSentinelPlayerModels(where: { player_address: $address }) {
    edges {
      node {
        is_active
        run_id
        lives
        x
        y
        kernel
        overclock_meter
        god_mode_active
      }
    }
  }
  # RunState tracks statistical progress for the run
  neonSentinelRunStateModels(where: { player_address: $address, is_finished: false }) {
    edges {
      node {
        run_id
        score
        current_layer
        enemies_defeated
        accuracy
      }
    }
  }
}
```

## 3. Weekly Leaderboard
Fetch top scores for the current week. 
*Note: The `week` variable is `floor(block_timestamp / 604800)`.*

```graphql
query GetWeeklyLeaderboard($week: Int!) {
  neonSentinelLeaderboardEntryModels(
    where: { week: $week }, 
    order: { direction: DESC, field: FINAL_SCORE },
    limit: 10
  ) {
    edges {
      node {
        player_address
        final_score
        deepest_layer
        enemies_defeated
        peak_combo
      }
    }
  }
}
```

## 4. Recent Game Events
Audit the trail of starts (Type 6) and ends (Type 7) for a player.

```graphql
query GetRecentEvents($address: String!) {
  neonSentinelGameEventModels(
    where: { player_address: $address },
    order: { direction: DESC, field: EVENT_ID },
    limit: 10
  ) {
    edges {
      node {
        event_type
        run_id
        block_number
        data_primary
      }
    }
  }
}
```

## 5. Mini-Me Inventory
Check the player's companion collection.

```graphql
query GetInventory($address: String!) {
  neonSentinelMiniMeInventoryModels(where: { player_address: $address }) {
    edges {
      node {
        unit_type
        count
      }
    }
  }
}
```

## 6. Real-time Subscription
Listen for any change to the player's profile (e.g., when a run ends or coins are claimed).

```graphql
subscription OnProfileUpdate($address: String!) {
  entityUpdated(id: $address) {
    id
    models {
      ... on neonSentinelPlayerProfile {
        player_address
        coins
        lifetime_score
        best_run_score
      }
    }
  }
}
```

---
*Generated for Neon Sentinel Dojo v1.7.0 (Sepolia)*
