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
- **Coins and upgrades** — Players earn coins via daily claims (`claim_coins`) and spend them on pregame upgrades when starting a run (`init_game` with upgrades). Coins are deducted and recorded in an append-only history.
- **Security by design** — Block-based timing (no client time), position verification for hits (no spoofing), replay protection (no double-execution of the same tick), and immutable run state after `end_run`.

---

## Project Structure

```
neon-sentinel-dojo/
├── src/
│   ├── lib.cairo          # Package root (systems, models, tests)
│   ├── models.cairo       # Dojo models (Player, RunState, Enemy, GameTick, LeaderboardEntry, etc.)
│   └── systems/          # World systems (contracts)
│       ├── init_game.cairo
│       ├── execute_tick.cairo
│       ├── hit_registration.cairo
│       ├── end_run.cairo
│       ├── submit_leaderboard.cairo
│       ├── claim_coins.cairo
│       ├── spend_coins.cairo
│       └── actions.cairo  # Starter (move/spawn)
├── dojo_dev.toml         # Dojo world config (dev)
├── Scarb.toml            # Cairo/Scarb config
└── docs/
    ├── DEVELOPERS_BIBLE.md   # Deep dive into code and architecture
    └── INTEGRATION_BIBLE.md  # Frontend integration guide
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

| Document                                          | Description                                                             |
| ------------------------------------------------- | ----------------------------------------------------------------------- |
| [DEVELOPERS_BIBLE.md](docs/DEVELOPERS_BIBLE.md)   | Architecture, models, systems, constants, security, and testing.        |
| [INTEGRATION_BIBLE.md](docs/INTEGRATION_BIBLE.md) | Frontend integration: world calls, entities, events, and Torii/GraphQL. |

---

## Quick Flow Summary

1. **Profile / coins** — Ensure the player has a `PlayerProfile` (e.g. seeded). They can `claim_coins` once per 24h (≈7200 blocks).
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
