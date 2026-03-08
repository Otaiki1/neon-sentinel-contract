# Neon Sentinel — Data Structures

This document describes all persistent and runtime data structures used in the Neon Sentinel app: localStorage keys, Phaser Registry keys, configuration shapes, and how data flows between React and the game.

---

## 1. Overview

- **Persistence**: Most player progress is stored in **localStorage** via service modules under `src/services/`.
- **Runtime state**: The Phaser game uses **Phaser Registry** for cross-scene state (GameScene ↔ UIScene). React passes initial data into the registry when the game boots (GamePage).
- **Configuration**: Static game data lives in `src/game/config.ts` (layers, enemies, kernels, achievements, etc.). This file does not define runtime-only structures; see Registry and services for those.

---

## 2. localStorage Keys and Shapes

All keys and their JSON shapes. Services merge with defaults on load; types below are the stored/effective shapes.

| Key | Service / Location | Shape |
|-----|--------------------|--------|
| `neon-sentinel-rank-history` | `rankService.ts` | `Rank[]` |
| `neon-sentinel-current-rank` | `rankService.ts` | `Rank` |
| `neon-sentinel-current-progress` | `rankService.ts` | `{ prestige: number; layer: number }` |
| `neon_sentinel_scores` | `scoreService.ts` | `Record<string, ScoreEntry[]>` (week string → entries) |
| `neon_sentinel_current_week` | `scoreService.ts` | `string` (number as string) |
| `neonSentinel_coins` | `coinService.ts` | `CoinState` |
| `neonSentinel_miniMeInventory` | `inventoryService.ts` | `MiniMeInventory` |
| `neonSentinel_miniMeSessions` | `miniMeSessionsService.ts` | `string` (number as string) |
| `neon-sentinel-kernels` | `kernelService.ts` | `KernelState` |
| `neon-sentinel-hero-grades` | `heroGradeService.ts` | `HeroGradeState` |
| `neon-sentinel-achievements` | `achievementService.ts` | `AchievementState` |
| `neon-sentinel-settings` | `settingsService.ts` | `GameplaySettings` |
| `neon-sentinel-session-rewards` | `sessionRewardService.ts` | `SessionRewardState` |
| `neon-sentinel-story-milestones` | `storyService.ts` | `StoryMilestone[]` |
| `neon-sentinel-story-state` | `storyService.ts` | Serialized `StoryState` (completed milestones, etc.) |
| `neonSentinel_viewedDialogues` | `dialogueService.ts` | `string[]` |
| `neonSentinel_purchasedAvatars` | `avatarService.ts` | `string[]` (AvatarId[]) |
| `neonSentinel_activeAvatarId` | `avatarService.ts` | `string` (AvatarId) |
| `neonSentinel_finalBossDefeated` | `avatarService.ts` | `"true"` when set |
| `neon-sentinel-wallet-modal-seen` | `LandingPage.tsx` | `"true"` when set |
| `neon-sentinel-user-mode` | `LandingPage.tsx` | `"anonymous"` \| `"wallet"` |
| `neon-sentinel-story-modal-seen` | `LandingPage.tsx` | `"true"` when set |
| `neonSentinel_prestigeCompleted` | `ProfilePage.tsx` | `boolean[]` (index = prestige 0..8) |
| Tooltip / joystick | Various | `neonSentinel_tooltip_*`, joystick sensitivity key |

---

## 3. Service Data Types

### 3.1 Rank Service (`rankService.ts`)

```ts
interface Rank {
  number: number;
  prestige: number;
  layer: number;
  name: string;
  badge: string;
  tier: string;
}

// CURRENT_PROGRESS_KEY stores actual player progress (used for unlock checks).
// getCurrentRankFromStorage() returns the rank *definition* (same prestige/layer as that rank), not necessarily the player's latest progress.
{ prestige: number; layer: number }  // CURRENT_PROGRESS_KEY
```

### 3.2 Score Service (`scoreService.ts`)

```ts
interface ScoreEntry {
  score: number;
  finalScore: number;
  walletAddress?: string;
  playerName: string;
  timestamp: number;
  week: number;
  deepestLayer?: number;
  prestigeLevel?: number;
  currentRank?: string;
  modifierKey?: string;
  survivalTime?: number;
  maxCorruptionReached?: number;
  totalEnemiesDefeated?: number;
  runsWithoutDamage?: number;
  peakComboMultiplier?: number;
  timeToReachLayer6?: number;
  deepestLayerWithPrestige?: number;
}

interface RunMetrics {
  survivalTime: number;
  maxCorruptionReached: number;
  totalEnemiesDefeated: number;
  runsWithoutDamage: number;
  peakComboMultiplier: number;
  timeToReachLayer6?: number;
  deepestLayerWithPrestige: number;
}
```

### 3.3 Coin Service (`coinService.ts`)

```ts
type CoinState = {
  coins: number;
  lastResetDate: string;  // ISO date YYYY-MM-DD
  lastPrimeSentinelBonus?: string;
  transactionHistory: CoinTransaction[];
};

type CoinTransaction = {
  timestamp: number;
  amount: number;
  type: 'earn' | 'spend';
  source?: string;
  purpose?: string;
  balanceAfter: number;
};
```

### 3.4 Inventory Service (`inventoryService.ts`)

```ts
type MiniMeType = 'scout' | 'gunner' | 'shield' | 'decoy' | 'collector' | 'stun' | 'healer';

interface MiniMeInventory {
  scout: number;
  gunner: number;
  shield: number;
  decoy: number;
  collector: number;
  stun: number;
  healer: number;
}
// Each type capped at 20 (MAX_PER_TYPE).
```

### 3.5 Kernel Service (`kernelService.ts`)

```ts
type KernelKey = keyof typeof PLAYER_KERNELS;  // e.g. sentinel_standard, sentinel_speed, ...

type KernelState = {
  selectedKernel: KernelKey;
  unlocked: Record<KernelKey, boolean>;
  totalKills: number;
  totalHitsTaken: number;
  totalShotsFired: number;
  totalShotsHit: number;
};
```

### 3.6 Hero Grade Service (`heroGradeService.ts`)

```ts
type HeroGrade = 1 | 2 | 3 | 4 | 5;

type HeroGradeState = {
  unlockedGrades: HeroGrade[];
  currentGrade: HeroGrade;
};
```

### 3.7 Achievement Service (`achievementService.ts`)

```ts
type AchievementState = {
  unlocked: string[];
  progress: Record<string, number>;
  notified: string[];
  lifetimeScore: number;
  lifetimePlayMs: number;
  lifetimeEnemiesDefeated: number;
  bestComboMultiplier: number;
  bestEnemiesDefeated: number;
  bestCorruption: number;
  bestRunStats: BestRunStats | null;
  layerVisits: Record<string, number>;
  recentRecords: Array<{ label: string; value: string; timestamp: number }>;
  selectedCosmetic: string;
  selectedHero: string;
  selectedSkin: string;
  extraBadges: string[];
  extraCosmetics: string[];
};

type BestRunStats = {
  survivalTimeMs: number;
  finalScore: number;
  deepestLayer: number;
  maxCorruption: number;
  enemiesDefeated: number;
  accuracy: number;
  bestCombo: number;
  livesUsed: number;
  powerUpsCollected: number;
  deaths: number;
};
```

### 3.8 Settings Service (`settingsService.ts`)

```ts
type DifficultyMode = 'normal' | 'easy' | 'hard';

type GameplaySettings = {
  difficulty: DifficultyMode;
  accessibility: {
    colorBlindMode: boolean;
    highContrast: boolean;
    dyslexiaFont: boolean;
    reduceMotion: boolean;
    reduceFlash: boolean;
  };
  visual: {
    uiScale: number;
    uiOpacity: number;
    screenShakeIntensity: number;
    gridIntensity: number;
  };
};
```

### 3.9 Session Reward Service (`sessionRewardService.ts`)

```ts
type SessionRewardState = {
  lastPlayDate: string | null;
  lastSessionDate: string | null;
  streak: number;
  lifetimePlayMs: number;
  milestonesGranted: string[];
  sessionCount: number;
};
```

### 3.10 Story Service (`storyService.ts`)

```ts
interface StoryMilestone {
  id: string;
  prestige: number;
  layer: number;
  type: 'game_start' | 'layer_complete' | 'prestige_milestone' | 'boss_defeat' | 'final_boss';
  character: 'white_sentinel' | 'prime_sentinel' | 'zrechostikal';
  dialogueId: string;
  completed: boolean;
}

interface StoryState {
  currentPrestige: number;
  currentLayer: number;
  completedMilestones: Set<string>;
  lastTriggeredMilestone: string | null;
  storyArc: string | null;
}
// Stored as JSON; completedMilestones may be serialized as array.
```

### 3.11 Avatar Service (`avatarService.ts`)

- `AvatarId`: keys of `AVATAR_CONFIG` from config (e.g. `default_sentinel`, `transcendent_form`).
- Purchased list: `string[]`. Active: single `string` (AvatarId).

### 3.12 Pregame Upgrade Service (`pregameUpgradeService.ts`) — No persistence

Session-only. Upgrade IDs and merged effects are passed via React Router state into GamePage, then into Registry.

```ts
type PregameUpgradeId =
  | 'extra_health_1' | 'extra_health_2' | 'max_health_6'
  | 'gun_power' | 'fire_rate' | 'powerup_duration' | 'movement_speed';

interface PregameSessionEffects {
  extraHealthBars: number;
  maxHealthBars: number | null;
  bulletDamageMultiplier: number;
  fireRateMultiplier: number;
  powerupDurationMultiplier: number;
  speedMultiplier: number;
}
```

---

## 4. Phaser Registry Keys

Set by GamePage on init or by GameScene/UIScene during the run. Types are the values read/written.

| Key | Type | Set By | Notes |
|-----|------|--------|--------|
| `gameplaySettings` | `GameplaySettings` | GamePage | From settingsService |
| `coins` | `number` | GamePage | Snapshot at boot |
| `pregameSessionEffects` | `PregameSessionEffects` | GamePage | From location.state pregameUpgrades, merged |
| `currentRank` | `string` | GameScene | Rank name |
| `coinBalance` | `number` | GameScene | Synced from coinService |
| `healthBars` | `number` | GameScene | Current health bars |
| `maxHealthBars` | `number` | GameScene | Can be 5 or 6 (pregame) |
| `activeMiniMes` | `number` | GameScene | Count of active mini-me entities |
| `miniMeSessionsRemaining` | `number` | GameScene | From miniMeSessionsService |
| `score` | `number` | GameScene | Current score |
| `finalScore` | `number` | GameScene | Set on game over |
| `gameOver` | `boolean` | GameScene | |
| `comboMultiplier` | `number` | GameScene | |
| `currentLayer` | `number` | GameScene | 1–6 |
| `layerName` | `string` | GameScene | LAYER_CONFIG name |
| `isPaused` | `boolean` | GameScene | |
| `prestigeChampion` | `boolean` | GameScene | |
| `prestigeLevel` | `number` | GameScene | |
| `currentPrestige` | `number` | GameScene | |
| `previousPrestige` | `number` | GameScene | |
| `prestigeCompleted` | `boolean[]` | GameScene | Index = prestige 0..8 |
| `isPrimeSentinel` | `boolean` | GameScene | |
| `overclockActive` | `boolean` | GameScene | |
| `overclockProgress` | `number` | GameScene | 0–1 |
| `overclockCooldown` | `number` | GameScene | 0–1 |
| `overclockActivationsRemaining` | `number` | GameScene | |
| `shockBombProgress` | `number` | GameScene | 0–1 |
| `shockBombReady` | `boolean` | GameScene | |
| `godModeProgress` | `number` | GameScene | 0–1 |
| `godModeReady` | `boolean` | GameScene | |
| `godModeActive` | `boolean` | GameScene | |
| `challengeActive` | `boolean` | GameScene | |
| `challengeTitle` | `string` | GameScene | |
| `challengeDescription` | `string` | GameScene | |
| `challengeProgress` | `number` | GameScene | |
| `runStats` | `RunStats` | GameScene | Live HUD stats |
| `runMetrics` | `RunMetrics` \| null | GameScene | Set on game over for feedback |
| `uiGlitchIntensity` | `number` | GameScene | |
| `reviveCount` | `number` | GameScene | |
| `joystickSensitivity` | `number` | UIScene / GameScene | |
| `musicBpm` | `number` | GameScene | |
| `avatarSpeedMultiplier` | `number` | GameScene | |
| `avatarFireRateMultiplier` | `number` | GameScene | |
| `avatarHealthMultiplier` | `number` | GameScene | |
| `avatarDamageMultiplier` | `number` | GameScene | |
| `activeAvatarId` | `string` | GameScene | AvatarId |
| `walletAddress` | `string` \| undefined | GamePage (via context) | |
| `inventoryModalOpen` | `boolean` | GamePage / UIScene | |
| `finalBossVictory` | `boolean` | GameScene | Set on final boss win |
| `lastRankAchievement` | `{ rank: Rank }` \| null | GameScene | Pop when shown |

**RunStats** (registry `runStats`):

```ts
{
  survivalTimeMs: number;
  enemiesDefeated: number;
  shotsFired: number;
  shotsHit: number;
  accuracy: number;
  dodges: number;
  // ... other live run fields
}
```

---

## 5. React Router State (GamePage)

When navigating to `/play`:

```ts
location.state = {
  pregameUpgrades?: PregameUpgradeId[];  // From PregameUpgradesModal "Launch"
};
```

- **Launch with upgrades**: Modal calls `navigate('/play', { state: { pregameUpgrades: selectedIds } })`. GamePage reads `location.state?.pregameUpgrades`, merges via `mergePregameEffects()`, and sets `game.registry.set('pregameSessionEffects', pregameEffects)`.
- **Skip**: No state or empty array; `pregameSessionEffects` has default multipliers (1) and no extra/max health.

---

## 6. Configuration-Derived Structures (config.ts)

These are not stored as-is in localStorage; they define game rules. Key exports:

- **RANK_CONFIG**: `{ ranks: Rank[] }` — rank definitions by (prestige, layer).
- **LAYER_CONFIG**: `Record<1|2|3|4|5|6, { name, scoreThreshold, enemies, bossChance, gridColor, healthMultiplier, spawnRateMultiplier, ... }>`.
- **ENEMY_CONFIG**: Per-type stats (green, yellow, yellowShield, yellowEcho, blue, blueBuff, purple, purpleFragmenter, red, flameRed).
- **PLAYER_KERNELS**: Kernel keys and config (name, baseSpeed, fireRate, unlockCondition, spriteVariant, etc.).
- **AVATAR_CONFIG_FLAT** (avatarService): AvatarId → { unlockPrestige, stat multipliers, requiresFinalBoss?, etc. }.
- **HERO_GRADES** (heroGradeService): Grade 1–5 config (unlockCondition, specialFeature bonuses).
- **ACHIEVEMENTS**: Tiers and list of `{ id, reward }`.
- **POWERUP_CONFIG**, **SPAWN_CONFIG**, **CORRUPTION_SYSTEM**, **OVERCLOCK_CONFIG**, **SHOCK_BOMB_CONFIG**, **GOD_MODE_CONFIG**, **MID_RUN_CHALLENGES**, **ROTATING_LAYER_MODIFIERS**, **FAILURE_FEEDBACK**, **SESSION_REWARDS**, **CUSTOMIZABLE_SETTINGS**, **SENSORY_ESCALATION**, **LEADERBOARD_CATEGORIES**, etc.

Enemy **color** and **sprite** mapping (including red / flameRed for layers 5 and 6) are in `enemyService.ts` and `assetMap.ts`; layer→color override is applied in GameScene (e.g. layer ≥ 6 → flameRed, layer ≥ 5 → red).

---

## 7. Data Flow Summary

1. **Boot (GamePage)**  
   - Reads `getGameplaySettings()`, `getAvailableCoins()`, `location.state?.pregameUpgrades`.  
   - Sets `gameplaySettings`, `coins`, `pregameSessionEffects` in registry.  
   - Wallet address (if any) set in registry for score submission.

2. **GameScene create()**  
   - Reads `gameplaySettings`, `pregameSessionEffects` from registry.  
   - Applies pregame effects (extra/max health, damage/fire rate/powerup duration/speed multipliers).  
   - Applies gameplay settings (difficulty, accessibility, visual).  
   - Initializes run state and writes score, layer, health, overclock, shock bomb, god mode, runStats, etc. to registry.

3. **During run**  
   - GameScene updates registry (score, combo, layer, health, abilities, runStats, etc.).  
   - UIScene (and React overlays) read registry for display and modals.

4. **Game over**  
   - GameScene sets `gameOver`, `finalScore`, `runMetrics`, submits score to scoreService, updates achievements, hero grade, kernel stats, rank (updateCurrentRank → saves CURRENT_PROGRESS_KEY and current rank), coins, session rewards, etc.  
   - All persistence is via service calls from game or React; no direct localStorage in GameScene except joystick sensitivity.

5. **Unlock checks (avatars, kernels, etc.)**  
   - Use **player progress** from `getCurrentPrestigeFromStorage()` / `getCurrentLayerFromStorage()` (CURRENT_PROGRESS_KEY), not the prestige/layer of the rank object from `getCurrentRankFromStorage()`.

---

## 8. Prestige Progress vs Rank Definition

- **CURRENT_PROGRESS_KEY** (`neon-sentinel-current-progress`): Stores the player’s actual `(prestige, layer)` progress. Used for “have they reached prestige 1?” (avatar/kernel unlocks, etc.).
- **CURRENT_RANK_KEY** (`neon-sentinel-current-rank`): Stores the **Rank** object that corresponds to the highest rank achieved (e.g. “Boot Master” has prestige 0, layer 6 in its definition).
- For unlock logic, always use `getCurrentPrestigeFromStorage()` and `getCurrentLayerFromStorage()`. Do not use `getCurrentRankFromStorage()?.prestige` for “has the player completed prestige 1?”.

---

_Last updated to match the codebase as of 2026-02-04 (pregame upgrades, prestige progress fix, red/flameRed enemies, profile and landing updates)._
