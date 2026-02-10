# Neon Sentinel

![Neon Sentinel](./assets/cover.png)

**Neon Sentinel** is a Dojo Autonomous World — a provable, on-chain game and world logic running on Starknet. The world is the source of truth: runs are deterministic, replay-verifiable, and leaderboard entries are immutable once submitted.

[![discord](https://img.shields.io/badge/join-dojo-green?logo=discord&logoColor=white)](https://discord.com/invite/dojoengine)
[![Telegram Chat][tg-badge]][tg-url]

[tg-badge]: https://img.shields.io/endpoint?color=neon&logo=telegram&label=chat&style=flat-square&url=https%3A%2F%2Ftg.sumanjay.workers.dev%2Fdojoengine
[tg-url]: https://t.me/dojoengine

---

## What Is Neon Sentinel?

- **Autonomous World** — Game state, runs, and leaderboards live on-chain in a Dojo world. No off-chain game server; the chain is the authority.
- **Run-based gameplay** — Players start a run (`init_game`), play ticks (`execute_tick`), register hits (`hit_registration`), then end the run (`end_run`) and optionally submit to the weekly leaderboard (`submit_leaderboard`).
- **Coins and upgrades** — Players earn coins via daily claims (`claim_coins`) or by purchasing with STRK (`buy_coins`), and spend them on pregame upgrades when starting a run (`init_game` with upgrades). Coins are deducted and recorded in an append-only history.
- **Security by design** — Block-based timing (no client time), position verification for hits (no spoofing), replay protection (no double-execution of the same tick), and immutable run state after `end_run`.

---

## Contracts Architecture

The Dojo **World** owns the canonical state. All systems are Starknet contracts registered as writers of the `neon_sentinel` namespace. Support modules (`erc20`, `owner_access`, `token_validation`) provide shared logic and are not deployed as standalone contracts.

```mermaid
flowchart TB
  subgraph world [Dojo World]
    NS[Namespace: neon_sentinel]
  end

  subgraph game [Game Systems]
    IG[init_game]
    ET[execute_tick]
    HR[hit_registration]
    ER[end_run]
    SL[submit_leaderboard]
    ACT[actions]
  end

  subgraph economy [Economy Systems]
    CC[claim_coins]
    SC[spend_coins]
  end

  subgraph shop [Coin Shop Systems]
    ICS[initialize_coin_shop]
    BC[buy_coins]
    UER[update_exchange_rate]
    PUP[pause_unpause_purchasing]
  end

  subgraph models [Models]
    P[Player]
    R[RunState]
    E[Enemy]
    GT[GameTick]
    GE[GameEvent]
    LB[LeaderboardEntry]
    PP[PlayerProfile]
    CSG[CoinShopGlobal]
    TPC[TokenPurchaseConfig]
    CPR[CoinPurchaseRecord]
    CPH[CoinPurchaseHistory]
    WR[WithdrawalRequest]
    M[DirectionsAvailable / Moves / Position / PositionCount]
  end

  world --> NS
  game --> NS
  economy --> NS
  shop --> NS
  NS --> models
```

---

## Project Structure

```
neon-sentinel-dojo/
├── src/
│   ├── lib.cairo              # Package root (systems, models, tests)
│   ├── models.cairo           # Dojo models (Player, RunState, Enemy, GameTick, LeaderboardEntry, CoinShop*, etc.)
│   ├── erc20.cairo            # ERC20 interface (for STRK token)
│   ├── owner_access.cairo     # Owner checks (coin shop)
│   ├── token_validation.cairo # STRK amount/allowance/balance validation
│   ├── systems/               # World systems (contracts)
│   │   ├── actions.cairo      # Starter (move/spawn)
│   │   ├── init_game.cairo
│   │   ├── execute_tick.cairo
│   │   ├── hit_registration.cairo
│   │   ├── end_run.cairo
│   │   ├── submit_leaderboard.cairo
│   │   ├── claim_coins.cairo
│   │   ├── spend_coins.cairo
│   │   ├── buy_coins.cairo        # STRK → in-game coins
│   │   ├── initialize_coin_shop.cairo
│   │   ├── update_exchange_rate.cairo
│   │   └── pause_unpause_purchasing.cairo
│   └── tests/
│       ├── test_coin_shop.cairo
│       ├── test_systems_integration.cairo
│       └── test_world.cairo
├── dojo_dev.toml              # Dojo world config (dev)
├── Scarb.toml                 # Cairo/Scarb config
└── docs/
    ├── DEVELOPERS_BIBLE.md    # Deep dive into code and architecture
    ├── INTEGRATION_BIBLE.md   # Frontend integration guide
    ├── MANUAL_TESTING_STRK.md   # STRK coin purchase manual test checklist
    ├── SECURITY_REVIEW_STRK.md   # Security review checklist (coin shop)
    └── DEPLOY_TESTNET.md        # Deploy world to Sepolia testnet
```

---

## Running Locally

### Prerequisites

- [Dojo / Sozo](https://book.dojoengine.org/getting-started/installation)
- [Katana](https://book.dojoengine.org/toolchain/katana/overview) (local Starknet)
- [Torii](https://book.dojoengine.org/toolchain/torii/overview) (indexer / GraphQL, for frontends)

### Terminal 1 — Katana

```bash
katana --dev --dev.no-fee
```

### Terminal 2 — Build, migrate, Torii

```bash
# Build
sozo build

# Inspect world
sozo inspect

# Migrate (deploy world and systems)
sozo migrate

# Start Torii (replace <WORLD_ADDRESS> with the address from sozo migrate)
torii --world <WORLD_ADDRESS> --http.cors_origins "*"
```

### Docker

You can run the stack with Docker Compose:

```bash
docker compose up
```

---

## Documentation

| Document                                                | Description                                                             |
| ------------------------------------------------------- | ----------------------------------------------------------------------- |
| [DEVELOPERS_BIBLE.md](docs/DEVELOPERS_BIBLE.md)         | Architecture, models, systems, constants, security, and testing.        |
| [INTEGRATION_BIBLE.md](docs/INTEGRATION_BIBLE.md)       | Frontend integration: world calls, entities, events, and Torii/GraphQL. |
| [MANUAL_TESTING_STRK.md](docs/MANUAL_TESTING_STRK.md)   | Manual testing checklist for STRK → in-game coins flow.                 |
| [SECURITY_REVIEW_STRK.md](docs/SECURITY_REVIEW_STRK.md) | Security review checklist for the coin shop (STRK purchase) system.     |
| [DEPLOY_TESTNET.md](docs/DEPLOY_TESTNET.md)           | Step-by-step guide to deploy the world to Starknet Sepolia testnet.    |

---

## Quick Flow Summary

1. **Profile / coins** — Ensure the player has a `PlayerProfile` (e.g. seeded). They can `claim_coins` once per 24h (≈7200 blocks) or `buy_coins(amount_strk, max_coins_expected)` to purchase coins with STRK (after the shop is initialized and STRK approved).
2. **Start run** — `init_game(kernel, pregame_upgrades_mask, expected_cost)`. Creates `Player` and `RunState`, deducts coins if `expected_cost > 0`.
3. **Play** — Each tick: `execute_tick(run_id, player_input, sig_r, sig_s, enemy_ids)`. Updates position, processes collisions, writes `GameTick`. Hits: `hit_registration(run_id, enemy_id, damage, player_x, player_y, hit_proof)` when a shot hits an enemy (validated in range).
4. **End run** — `end_run(run_id)`. Sets `is_finished`, locks `final_score` and `final_layer`, marks player inactive.
5. **Leaderboard** — `submit_leaderboard(run_id, week)`. Week = `block_number / 50400`. Creates immutable `LeaderboardEntry` with proof fields.

---

## Contribution

- **Bugs** — [Open an issue](https://github.com/otaiki1/neon-sentinel-contract/issues).
- **Features** — [Request a feature](https://github.com/otaiki1/neon-sentinel-contract/issues).
- **Code** — Pull requests are welcome.

Happy coding!
