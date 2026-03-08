# 🔧 Neon Sentinel - Developer's Bible

> **Complete Technical Documentation & Architecture Guide**

This document provides comprehensive technical documentation for developers working on Neon Sentinel. It covers architecture, configuration, implementation details, and all technical aspects of the game.

---

## 📖 Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Configuration System](#configuration-system)
4. [Game Systems](#game-systems)
5. [Scene Architecture](#scene-architecture)
6. [Physics & Collisions](#physics--collisions)
7. [State Management](#state-management)
8. [Data Structures](./DATASTRUCTURES.md) (localStorage, Registry, service types)
9. [Asset Management](#asset-management)
10. [Performance Optimization](#performance-optimization)
11. [Mobile Support](#mobile-support)
12. [Integration Points](#integration-points)
13. [Build & Deployment](#build--deployment)

---

## 🎯 Project Overview

### Tech Stack

- **Framework**: React 18 + TypeScript
- **Game Engine**: Phaser 3.90.0
- **Build Tool**: Vite 5.1.4
- **Styling**: Tailwind CSS 3.4.0
- **Wallet Integration**: Dynamic Labs SDK v4 + Wagmi + viem
- **Routing**: React Router DOM 7.12.0
- **State Management**: Phaser Registry + React Context
- **Data**: TanStack Query 5
- **PWA**: Vite PWA + Workbox

### Project Structure

```
neon-sentinel/
├── src/
│   ├── game/              # Phaser game code
│   │   ├── config.ts      # All game configuration
│   │   ├── Game.ts        # Phaser game initialization
│   │   └── scenes/         # Phaser scenes
│   │       ├── BootScene.ts    # Asset loading
│   │       ├── GameScene.ts    # Main gameplay
│   │       └── UIScene.ts      # UI overlay
│   ├── pages/             # React pages
│   │   ├── LandingPage.tsx     # Main menu
│   │   ├── LeaderboardPage.tsx # Hall of Fame leaderboard view
│   │   ├── GamePage.tsx        # Game container
│   │   ├── ProfilePage.tsx    # Profile, rank, stats, kernels, heroes
│   │   └── AboutPage.tsx       # About / info
│   ├── components/        # React components
│   │   ├── StoryModal.tsx
│   │   ├── PregameUpgradesModal.tsx
│   │   ├── InventoryModal.tsx
│   │   └── AvatarSelectionModal.tsx
│   ├── services/         # Business logic
│   │   ├── scoreService.ts     # Leaderboard logic
│   │   ├── achievementService.ts # Achievement persistence + cosmetics
│   │   ├── rotatingLayerService.ts # Rotating modifier schedule helper
│   │   ├── kernelService.ts # Kernel selection + unlock tracking
│   │   ├── coinService.ts # Daily coin system
│   │   ├── pregameUpgradeService.ts # Session-only pre-run upgrades
│   │   ├── sessionRewardService.ts # Session tracking and rewards
│   │   ├── settingsService.ts # Gameplay settings persistence
│   │   └── storyService.ts # Story milestone tracking
│   ├── game/
│   │   ├── lore/        # Story content
│   │   │   ├── storyArcs.ts # Story progression data
│   │   │   └── characters.ts # Character definitions and dialogue
│   │   └── dialogue/    # Dialogue system
│   │       └── DialogueManager.ts # Dialogue display manager
│   └── assets/           # Static assets
│       └── sprites/       # SVG game sprites
├── public/               # Public assets
│   └── sprites/          # Sprite files served statically
└── dist/                 # Build output
```

---

## 🏗️ Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────┐
│         React Application               │
│  (LandingPage / GamePage)               │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│         Phaser Game Instance            │
│  ┌──────────┬──────────┬──────────┐   │
│  │ BootScene│GameScene │ UIScene  │   │
│  │ (Assets) │(Gameplay)│  (UI)    │   │
│  └──────────┴──────────┴──────────┘   │
└─────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│      Phaser Registry (State)            │
│  - score, lives, layer, gameOver, etc.  │
└─────────────────────────────────────────┘
```

### Scene Flow

1. **BootScene**: Loads all assets, then starts GameScene and launches UIScene
2. **GameScene**: Main gameplay loop, physics, collisions, enemy spawning
3. **UIScene**: Renders UI overlay, listens to registry changes, handles modals

### Communication Patterns

- **GameScene ↔ UIScene**: Phaser Registry (cross-scene state)
- **GameScene → React**: Custom events via `window` object
- **React → GameScene**: Exposed functions on game instance
- **Wallet → Game**: Wallet address passed via registry

---

## ⚙️ Configuration System

All game configuration is centralized in `src/game/config.ts`.

### Player Configuration

```typescript
PLAYER_CONFIG = {
    speed: 400,              // Movement speed (pixels/second)
    bulletSpeed: 600,       // Bullet velocity (pixels/second)
    fireRate: 150,          // Milliseconds between shots
    startX: 400,            // Initial X position (deprecated, now dynamic)
    startY: 550,            // Initial Y position (deprecated, now dynamic)
    initialLives: 1,        // Starting lives count
}
```

### Enemy Configuration

```typescript
ENEMY_CONFIG = {
    green: {
        points: 10,          // Score points
        speed: 150,          // Movement speed
        health: 2,           // Base health (scales with layer)
        spawnWeight: 5,       // Spawn probability weight
        canShoot: false,     // Can shoot bullets
    },
    yellow: {
        points: 25,
        speed: 200,
        health: 2,
        spawnWeight: 3,
        canShoot: false,
    },
    yellowShield: {
        points: 15,
        speed: 100,
        health: 3,
        spawnWeight: 2,
        canShoot: false,
        shieldRadius: 100, // Halved from 200 - more lethal proximity damage
        shieldDamageReduction: 0.5,
    },
    yellowEcho: {
        points: 25,
        speed: 180,
        health: 2,
        spawnWeight: 2,
        canShoot: false,
        echoCount: 2,
        echoDuration: 2000,
    },
    blue: {
        points: 50,
        speed: 180,
        health: 4,
        spawnWeight: 2,
        canShoot: true,
        shootInterval: 1500, // Milliseconds between shots
        bulletSpeed: 250,    // Enemy bullet speed
    },
    blueBuff: {
        points: 50,
        speed: 150,
        health: 3,
        spawnWeight: 1,
        canShoot: true,
        shootInterval: 1700,
        bulletSpeed: 240,
        buffRadius: 250,
        buffShootingSpeed: 1.3,
        buffDamage: 1.2,
    },
    purple: {
        points: 100,
        speed: 220,
        health: 6,
        spawnWeight: 1,
        canShoot: false,
    },
    purpleFragmenter: {
        points: 100,
        speed: 200,
        health: 4,
        spawnWeight: 1,
        canShoot: false,
        fragmentsOnDeath: 3,
        fragmentType: "green",
        fragmentHealth: 1,
    },
    red: {
        points: 500,
        speed: 120,
        health: 20,
        spawnWeight: 0,      // Boss - spawned separately
        canShoot: false,
    },
    flameRed: {
        points: 500,
        speed: 120,
        health: 20,
        spawnWeight: 0,      // Layer 6 graduation bosses; visuals differ from red
        canShoot: false,
    },
}
```

**Enemy color by layer**: GameScene overrides sprite/color by layer: layer ≥ 5 uses red pawn/boss sprites; layer ≥ 6 uses flameRed. See `enemyService.ts` and `assetMap.ts` for sprite keys.

### Layer Configuration

```typescript
LAYER_CONFIG = {
    1: {
        name: "Boot Sector",
        scoreThreshold: 0,
        enemies: ["green"],
        bossChance: 0,
        gridColor: 0x00ff00,        // Hex color for grid
        healthMultiplier: 1.0,     // Enemy health multiplier
        spawnRateMultiplier: 1.0,  // Enemy spawn rate multiplier
    },
    // ... layers 2-6
}
```

### Prestige Configuration

```typescript
PRESTIGE_CONFIG = {
    prestigeLevels: [
        { level: 1, difficultyMultiplier: 1.5, scoreMultiplier: 1.0 },
        { level: 2, difficultyMultiplier: 2.0, scoreMultiplier: 1.5 },
        { level: 3, difficultyMultiplier: 2.5, scoreMultiplier: 2.0 },
        { level: 4, difficultyMultiplier: 3.0, scoreMultiplier: 2.5 },
    ],
    prestigeResetThreshold: 100000,
    visualEffects: {
        gridGlitchIntensity: 0.3,
        screenFlashFrequency: 1.2,
        corruptionVFX: true,
    },
}
```

**Prestige Mechanics**:
- Unlocks after defeating the Layer 6 graduation boss
- Loops back to Layer 1 with higher difficulty + score multipliers
- Multipliers scale beyond the listed tiers

### Difficulty Evolution Configuration

```typescript
DIFFICULTY_EVOLUTION = {
    phase1: { startMs: 0, endMs: 180000, enemyBehaviors: ["basic_pursuit"] },
    phase2: { startMs: 180000, endMs: 480000, enemyBehaviors: ["predictive_movement"] },
    phase3: { startMs: 480000, endMs: 900000, enemyBehaviors: ["coordinated_fire"] },
    phase4: { startMs: 900000, endMs: Infinity, enemyBehaviors: ["adaptive_learning"] },
}

ENEMY_BEHAVIOR_CONFIG = {
    predictiveLeadTime: 0.7,
    adaptationThreshold: 30,
    formationSpawnChance: 0.3,
    coordinatedFireDistance: 400,
    behaviourResetInterval: 120000,
}
```

**Evolution Mechanics**:
- Phase selection is time-based (ms since run start)
- Predictive aiming uses player velocity with movement-stability dampening
- Coordinated fire triggers when blue enemies cluster within range
- Adaptive learning biases spawn lanes after threshold kills, resets every interval

### Corruption System Configuration

```typescript
CORRUPTION_SYSTEM = {
    currentCorruption: 0,
    maxCorruption: 100,
    passiveIncreaseRate: 0.5,
    safePlayDecay: -0.2,
    riskPlayBonus: {
        enterCorruptedZone: 5,
        defeatBoss: 10,
        noHitStreak: 1,
        comboMultiplier: 2,
    },
    scoreMultiplier: {
        low: 1.0,
        medium: 1.5,
        high: 2.0,
        critical: 3.0,
    },
    enemyDifficultyMultiplier: {
        low: 1.0,
        medium: 1.3,
        high: 1.7,
        critical: 2.2,
    },
}
```

**Corruption Mechanics**:
- Timer-based tick (1s) applies passive rise, risk bonuses, and safe-play decay
- Score multiplier and enemy difficulty scale by corruption tier
- Corrupted zones are detected by nearby enemy density

### Overclock Configuration

```typescript
OVERCLOCK_CONFIG = {
    activationKey: "Q",
    cooldownBetweenActivations: 60000,
    maxActivationsPerRun: 5,
    duration: 15000,
    effects: {
        playerSpeedMultiplier: 1.4,
        scoreMultiplier: 2.0,
        fireRateMultiplier: 0.6,
        enemySpawningMultiplier: 1.8,
        playerVisibility: 1.0,
    },
    indicators: {
        overclockBar: true,
        screenBurnEffect: true,
        playerGlowEffect: true,
    },
}
```

**Overclock Mechanics**:
- Manual activation (`Q`) with cooldown + max charges per run
- Temporary multipliers for speed, fire rate, score, and spawn rate
- UI exposes remaining duration and cooldown
- **Note**: Shares Q key with God Mode - whichever is ready activates first

### Shock Bomb Configuration

```typescript
SHOCK_BOMB_CONFIG = {
    activationKey: "B",
    fillRate: 0.5, // Percentage per second (fills in ~2 seconds)
    killPercentage: 0.7, // Kills 70% of enemies
    cooldownAfterUse: 30000, // 30 seconds cooldown
    unlockScore: 10000, // Unlock at 10,000 lifetime score
}
```

**Shock Bomb Mechanics**:
- **Unlock Requirement**: 10,000 lifetime score (checked via `abilityService.isShockBombUnlocked()`)
- Meter-based ability that fills over time during gameplay
- Activation (`B`) instantly kills 70% of all enemies on screen
- Meter fills at 0.5% per second (~2 seconds to full)
- 30-second cooldown after use before meter starts refilling
- Visual meter displayed in UI with glow effect when ready
- Meter UI only created if unlocked (hidden if locked)
- Attempting to activate when locked shows "LOCKED" announcement

### God Mode Configuration

```typescript
GOD_MODE_CONFIG = {
    activationKey: "Q",
    fillRate: 0.3, // Percentage per second (fills in ~3.3 seconds)
    duration: 10000, // 10 seconds invincibility
    cooldownAfterUse: 40000, // 40 seconds cooldown
    unlockScore: 25000, // Unlock at 25,000 lifetime score
}
```

**God Mode Mechanics**:
- **Unlock Requirement**: 25,000 lifetime score (checked via `abilityService.isGodModeUnlocked()`)
- Meter-based ability that fills over time during gameplay
- Activation (`Q`) grants 10 seconds of complete invincibility
- Meter fills at 0.3% per second (~3.3 seconds to full)
- 40-second cooldown after use before meter starts refilling
- Visual meter displayed in UI with glow effect when ready
- Meter UI only created if unlocked (hidden if locked)
- Attempting to activate when locked shows "LOCKED" announcement
- Player sprite switches to `heroGodMode` texture while active (with fallback tint if texture missing)
- Camera flash and announcement card on activation
- **Note**: Shares Q key with Overclock - whichever is ready activates first

### Leaderboard Categories Configuration

```typescript
LEADERBOARD_CATEGORIES = {
    highestScore: { title: "Score Champion", metric: "finalScore" },
    longestSurvival: { title: "Endurance Sentinel", metric: "survivalTime" },
    highestCorruption: { title: "Risk Taker", metric: "maxCorruptionReached" },
    mostEnemiesDefeated: { title: "Swarm Slayer", metric: "totalEnemiesDefeated" },
    cleanRuns: { title: "Perfect Sentinel", metric: "runsWithoutDamage" },
    highestCombo: { title: "Rhythm Master", metric: "peakComboMultiplier" },
    deepestLayer: { title: "System Diver", metric: "deepestLayerWithPrestige" },
    speedrun: { title: "Speed Runner", metric: "timeToReachLayer6" },
}
```

**Leaderboard Mechanics**:
- Weekly featured categories rotate via deterministic selection
- All-time records shown for inactive categories on the Hall of Fame page
- Challenge leaderboard shows non-standard modifier runs

### Rotating Layer Modifier Configuration

```typescript
ROTATING_LAYER_MODIFIERS = {
    firewall: {
        name: "Firewall Layer",
        enemySpawnRate: 1.2,
        modifiers: [{ type: "speed_cap", value: 0.7 }],
    },
    memory_leak: {
        name: "Memory Leak",
        enemySpawnRate: 0.9,
        modifiers: [
            { type: "input_delay", value: 0.1, frequency: "random_5s" },
            { type: "screen_glitch", intensity: 0.3 },
        ],
    },
    // ... more modifiers
}

ROTATING_LAYER_SCHEDULE = {
    durationHours: 3.5,
    announceBeforeMinutes: 15,
    rotationOrder: ["standard", "firewall", "memory_leak", "encrypted", "lag_spike", "void", "temporal"],
}
```

**Modifier Mechanics**:
- Rotation is time-based and global (all players share the same modifier)
- Upcoming change announced 15 minutes before the switch
- Effects include input delay, random pauses, vision mask, and speed-linked scoring

### Failure Feedback Configuration

```typescript
FAILURE_FEEDBACK = {
    displayMetrics: [
        { metric: "pointsToNextMilestone", color: "red" },
        { metric: "layerProgress", color: "yellow" },
        { metric: "personalBest", color: "blue" },
        { metric: "leaderboardProximity", color: "purple" },
        { metric: "riskReward", color: "orange" },
    ],
    celebrationMetrics: [
        "Best run this week",
        "New personal best enemy kills",
        "Highest corruption survived",
        "New personal best combo",
    ],
    scoreMilestones: [10000, 50000, 100000],
}
```

**Feedback Mechanics**:
- Game over UI pulls run metrics from Phaser registry (`runMetrics`)
- Weekly leaderboard proximity uses `fetchWeeklyLeaderboard()`
- Personal bests are persisted in achievement state and updated after display

### Kernel Configuration

```typescript
PLAYER_KERNELS = {
    sentinel_standard: {
        name: "Azure Core",
        description: "Balanced speed and firepower - Blue variant",
        baseSpeed: 1.0,
        fireRate: 1.0,
        unlocked: true,
        unlockCondition: "default",
        spriteVariant: "blue", // Maps to heroGrade1Blue
    },
    sentinel_speed: {
        name: "Violet Interceptor",
        description: "30% faster movement, 20% slower fire rate - Purple variant",
        baseSpeed: 1.3,
        fireRate: 1.2,
        unlocked: false,
        unlockCondition: "reach_layer_3",
        spriteVariant: "purple", // Maps to heroGrade2Purple
    },
    sentinel_firepower: {
        name: "Crimson Artillery",
        description: "40% faster fire rate, 15% slower movement - Red variant",
        baseSpeed: 0.85,
        fireRate: 0.6,
        unlocked: false,
        unlockCondition: "accumulate_1000_kills",
        spriteVariant: "red", // Maps to heroGrade3Red
    },
    sentinel_tanky: {
        name: "Amber Guardian",
        description: "20% more health per life, 20% slower speed - Orange variant",
        baseSpeed: 0.8,
        fireRate: 1.0,
        healthPerLife: 1.2,
        unlocked: false,
        unlockCondition: "survive_100_hits",
        spriteVariant: "orange", // Maps to heroGrade4Orange
    },
    sentinel_precision: {
        name: "Alabaster Sniper",
        description: "Bullets pierce through enemies, 50% slower fire rate - White variant",
        baseSpeed: 1.0,
        fireRate: 2.0,
        bulletPiercing: true,
        unlocked: false,
        unlockCondition: "achieve_90%_accuracy",
        spriteVariant: "white", // Maps to heroGrade5White
    },
}
```

**Kernel Mechanics**:
- Selected on landing page and applied at run start only
- **Kernels are now primarily cosmetic variants** - they map to colored hero sprite variants
- Speed multiplier scales player movement
- Fire rate multiplier scales `PLAYER_CONFIG.fireRate`
- Tanky kernel uses fractional damage accumulator to reduce life loss
- Precision kernel enables bullet piercing
- Each kernel maps to a specific colored hero sprite variant (blue, purple, red, orange, white)
- The actual hero sprite displayed combines the current hero grade (1-5) with the kernel's colored variant

### Hero Grade System Configuration

**Location**: `src/services/heroGradeService.ts`

```typescript
HERO_GRADES = {
    1: {
        grade: 1,
        name: "Initiate Sentinel",
        description: "The beginning of your journey",
        unlockCondition: { type: "default", value: 0 },
        specialFeature: {
            name: "Basic Training",
            description: "Standard capabilities",
            speedBonus: 0,
            fireRateBonus: 0,
            healthBonus: 1.0,
            damageBonus: 1.0,
        },
    },
    2: {
        grade: 2,
        name: "Veteran Sentinel",
        description: "Proven in combat",
        unlockCondition: { type: "playtime", value: 3600000 }, // 1 hour
        specialFeature: {
            name: "Combat Experience",
            description: "+10% movement speed",
            speedBonus: 0.1,
            fireRateBonus: 0,
            healthBonus: 1.0,
            damageBonus: 1.0,
        },
    },
    3: {
        grade: 3,
        name: "Elite Sentinel",
        description: "Master of the battlefield",
        unlockCondition: { type: "kills", value: 5000 }, // 5000 kills
        specialFeature: {
            name: "Rapid Fire",
            description: "+20% fire rate",
            speedBonus: 0.1,
            fireRateBonus: 0.2,
            healthBonus: 1.0,
            damageBonus: 1.0,
        },
    },
    4: {
        grade: 4,
        name: "Legendary Sentinel",
        description: "A force to be reckoned with",
        unlockCondition: { type: "score", value: 100000 }, // 100k score
        specialFeature: {
            name: "Enhanced Resilience",
            description: "+1 health per life, +15% damage",
            speedBonus: 0.1,
            fireRateBonus: 0.2,
            healthBonus: 1.2,
            damageBonus: 1.15,
        },
    },
    5: {
        grade: 5,
        name: "Transcendent Sentinel",
        description: "Beyond mortal limits",
        unlockCondition: { type: "layers", value: 6 }, // Reach layer 6
        specialFeature: {
            name: "Mastery",
            description: "+25% speed, +30% fire rate, +1.5x health, +25% damage",
            speedBonus: 0.25,
            fireRateBonus: 0.3,
            healthBonus: 1.5,
            damageBonus: 1.25,
            specialAbility: "Bullet piercing",
        },
    },
}
```

**Hero Grade Mechanics**:
- **Hero grades represent skill levels** - unlockable as you play more
- Grade 1 is unlocked by default
- Grades 2-5 unlock based on lifetime stats (playtime, kills, score, deepest layer)
- Each grade provides permanent bonuses to speed, fire rate, health, and damage
- Grade 5 enables bullet piercing as a special ability
- Hero grades are checked and unlocked at the end of each run via `checkAndUnlockHeroGrades()`
- The current hero grade determines the base sprite (heroGrade1-5)
- The selected kernel determines the colored variant (blue, purple, red, orange, white)
- Combined sprite key: `heroGrade{grade}{Color}` (e.g., `heroGrade1Blue`, `heroGrade3Red`)

**Service Functions**:
- `getCurrentHeroGrade()`: Returns the highest unlocked grade
- `getHeroGradeConfig(grade)`: Returns configuration for a specific grade
- `checkAndUnlockHeroGrades(stats)`: Checks lifetime stats and unlocks new grades
- `setCurrentHeroGrade(grade)`: Sets the active hero grade
- `isHeroGradeUnlocked(grade)`: Checks if a grade is unlocked

### Sensory Escalation Configuration

```typescript
SENSORY_ESCALATION = {
    musicTempo: { baseBeatsPerMinute: 120, increasePerMinute: 2, maxBeatsPerMinute: 160 },
    screenEffects: {
        baseGridOpacity: 1.0,
        scanlineIntensity: { layer1: 0.0, layer3: 0.1, layer5: 0.3, layer6: 0.5 },
        screenDistortion: { layer1: 0.0, layer3: 0.05, layer5: 0.15, layer6: 0.25 },
    },
    uiGlitching: {
        enabledAt: "layer_4",
        glitchIntensity: { low: 0.1, medium: 0.3, high: 0.6 },
    },
    hapticFeedback: {
        onEnemyKill: { duration: 50, intensity: 0.6 },
        onBossDefeat: { duration: 300, intensity: 1.0 },
        onPowerUpCollect: { duration: 100, intensity: 0.8 },
        onDamage: { duration: 200, intensity: 0.9 },
        onCorruptionCritical: { duration: 1000, pattern: "pulse" },
    },
}
```

**Sensory Mechanics**:
- GameScene updates scanlines, distortion, pulses, and BPM each frame
- UI glitch intensity is pushed via registry key `uiGlitchIntensity`
- Haptics use `navigator.vibrate()` with optional pulse patterns

### Customizable Settings Configuration

```typescript
CUSTOMIZABLE_SETTINGS = {
    difficulty: {
        easyMode: { enemySpeedReduction: 0.8, spawnRateReduction: 0.7 },
        hardMode: { enemySpeedIncrease: 1.3, spawnRateIncrease: 1.5 },
    },
    accessibility: {
        colorBlindMode: true,
        highContrast: true,
        dyslexiaFont: true,
        reduceMotion: true,
        reduceFlash: true,
    },
    visual: {
        uiScale: [0.5, 1.0, 1.5, 2.0],
        uiOpacity: [0.5, 1.0],
        screenShakeIntensity: [0.0, 0.5, 1.0],
        gridIntensity: [0.3, 0.7, 1.0],
    },
}
```

**Settings Mechanics**:
- Settings persisted in localStorage via `settingsService`
- Applied at game start via `GameScene.applyGameplaySettings()`
- Difficulty modes affect enemy speed and spawn rates
- Accessibility options modify visual/audio feedback
- Visual settings adjust UI scaling and effects intensity

### Mid-Run Challenges Configuration

```typescript
MID_RUN_CHALLENGES = {
    challenges: [
        { id: "no_shoot_20s", description: "Survive 20 seconds without shooting" },
        { id: "clean_10_enemies", description: "Destroy 10 enemies without taking damage" },
        { id: "survive_corruption_zone", description: "Stay in 80%+ corruption area for 15 seconds" },
        { id: "defeat_5_blue", description: "Defeat 5 blue enemies in 30 seconds" },
        { id: "chain_combo", description: "Maintain 3.0x+ combo for 30 seconds" },
        { id: "dodge_25_bullets", description: "Dodge 25 enemy bullets without taking damage" },
    ],
    triggerIntervals: {
        firstChallenge: 60000,
        subsequentChallenges: 120000,
        minTimeBetweenChallenges: 45000,
    },
    display: {
        announcementCard: true,
        progressBar: true,
        celebrationOnCompletion: true,
    },
}
```

**Challenge Mechanics**:
- Triggered after an initial delay, then every interval without overlap
- Per-challenge trackers stored in `GameScene` and progress pushed to registry
- Rewards can be instant (score/lives) or timed modifiers

### Achievement Configuration

```typescript
ACHIEVEMENTS = {
    tier1_basic: [{ id: "first_blood", reward: "badge_first_blood" }],
    tier2_intermediate: [{ id: "5x_combo", reward: "badge_flow_master" }],
    tier3_advanced: [{ id: "prestige_1", reward: "cosmetic_prestige_glow" }],
    tier4_legendary: [{ id: "1m_points", reward: "badge_grid_slayer" }],
}
```

**Achievement Mechanics**:
- Progress tracked per run and persisted in localStorage
- Unlocks fire announcements and update pause menu progress
- Cosmetics are selectable on the Hall of Fame page

**Key Mechanics**:
- `healthMultiplier`: Applied to all enemy health when spawning
- `bossSpeedMultiplier`: Applied to boss base speed per layer
- `spawnRateMultiplier`: Applied to spawn timer intervals
- `scoreThreshold`: Score required to trigger graduation boss
- `gridColor`: Background grid line color (visual indicator)

### Spawn Configuration

```typescript
SPAWN_CONFIG = {
    initialDelay: 1500,           // First enemy spawn delay (ms)
    minInterval: 800,             // Minimum spawn interval (ms)
    maxInterval: 2000,             // Maximum spawn interval (ms)
    difficultyIncrease: 0.93,      // Spawn rate multiplier per spawn
    maxEnemies: 20,                // Max active enemies on screen
    baseMaxEnemies: 30,            // Base max enemies (scales with layer)
}
```

**Spawn Rate Calculation**:
```typescript
baseInterval = Phaser.Math.Between(minInterval, maxInterval);
adjustedInterval = baseInterval / (spawnRateMultiplier * difficultyIncrease^spawnCount);
```

### Power-Up Configuration

```typescript
POWERUP_CONFIG = {
    spawnChance: 0.15,            // 15% chance from purple/red enemies (reduced from 25%)
    livesSpawnChance: 0.12,        // 12% chance for lives from all enemies (reduced from 35%)
    firepowerSpawnChance: 0.05,    // 5% chance for firepower (reduced from 8%)
    invisibilitySpawnChance: 0.10, // 10% chance for invisibility (reduced from 15%)
    types: {
        speed: {
            key: "power_up",
            duration: 10000,       // 10 seconds
            speedMultiplier: 1.5,  // 1.5x movement speed
        },
        fireRate: {
            key: "power_up_2",
            duration: 10000,
            fireRateMultiplier: 0.5, // 0.5x fire rate (faster)
        },
        score: {
            key: "orb",
            duration: 15000,
            scoreMultiplier: 2,    // 2x score
        },
        autoShoot: {
            key: "power_up",
            duration: 5000,        // 5 seconds
        },
        lives: {
            key: "orb",
            livesGranted: 2,       // +2 lives
        },
        firepower: {
            key: "power_up_2",
            duration: 15000,
            fireRateMultiplier: 1.0,
            firepowerLevel: 0.5,   // +0.5 per power-up (2 for 1 level)
        },
        invisibility: {
            key: "power_up",
            duration: 10000,       // 10 seconds invincibility
        },
    },
}
```

### UI Configuration

```typescript
UI_CONFIG = {
    logoFont: "Bungee",            // Retro brutalist font
    menuFont: "Rajdhani",          // Geometric font
    scoreFont: "Share Tech Mono",   // Monospace tech font
    bodyFont: "JetBrains Mono",    // Clean monospace
    neonGreen: "#00ff00",
    fontSize: {
        small: 12,
        medium: 16,
        large: 24,
        xlarge: 32,
    },
}
```

### Mobile Configuration

```typescript
MOBILE_SCALE = isMobileDevice() ? 0.5 : 1.0;

// Mobile detection
function isMobileDevice(): boolean {
    return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
        navigator.userAgent
    ) || window.innerWidth <= 768;
}
```

---

## 📖 Story & Narrative System

### Overview

The story system provides narrative context and character interactions throughout the game. It tracks story milestones, displays dialogue, and guides players through the narrative arc from basic Sentinel to Prime Sentinel.

### Architecture

```
┌─────────────────────────────────────────┐
│         Story Service                   │
│  - Milestone tracking                   │
│  - State management                     │
│  - Progression logic                    │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│         Story Content                    │
│  - storyArcs.ts (narrative structure)   │
│  - characters.ts (dialogue & characters)│
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│         Dialogue Manager                 │
│  - Display dialogue boxes                │
│  - Handle user interaction               │
│  - Priority management                   │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│         GameScene Integration            │
│  - Story triggers at key events          │
│  - Milestone completion                  │
└─────────────────────────────────────────┘
```

### Story Service (`src/services/storyService.ts`)

**Purpose**: Tracks story progression, milestones, and state.

**Key Functions**:
- `getStoryMilestones()`: Returns all story milestones
- `getMilestoneForProgress()`: Gets milestone for current prestige/layer
- `shouldTriggerMilestone()`: Checks if milestone should trigger
- `completeMilestone()`: Marks milestone as completed
- `updateStoryState()`: Updates current prestige/layer state
- `getStoryArcName()`: Gets story arc name for prestige level

**Storage**: Milestones and state are persisted in localStorage.

### Story Content

**Story Arcs** (`src/game/lore/storyArcs.ts`):
- Defines 5 story arcs: The Entry, The Awakening, The Revelation, The Confrontation, Prime Sentinel
- Maps prestige ranges to story arcs
- Tracks avatar unlocks per arc

**Characters** (`src/game/lore/characters.ts`):
- Defines 4 characters: White Sentinel, Prime Sentinel, Player Sentinel, Zrechostikal
- Contains all dialogue lines with IDs
- Character metadata (role, voice, color)

### Dialogue Manager (`src/game/dialogue/DialogueManager.ts`)

**Purpose**: Manages dialogue display and interaction.

**Features**:
- Dialogue box UI with character name and text
- Auto-advance based on dialogue length
- Click-to-skip functionality
- Priority system (low, medium, high, critical)
- Pauses game for critical dialogues
- Character-specific color coding

**Usage**:
```typescript
dialogueManager.showDialogue('white_sentinel_mission_brief', {
    skipOnClick: true,
    priority: 'high',
    onComplete: () => {
        // Handle completion
    },
});
```

### GameScene Integration

**Story Triggers**:
1. **Game Start**: Triggers `white_sentinel_mission_brief` on scene create
2. **Layer Completion**: Triggers layer complete dialogue after boss defeat
3. **Prestige Milestone**: Triggers prestige dialogue in `enterPrestigeMode()`
4. **Boss Defeat**: Triggers boss defeat dialogue when graduation boss is killed
5. **Final Boss**: Special trigger for Prestige 8, Layer 6

**Implementation**:
```typescript
// In GameScene.ts
private triggerStoryDialogue(type: 'game_start' | 'layer_complete' | ...): void {
    const milestone = getMilestoneForProgress(this.prestigeLevel, this.currentLayer, type);
    if (milestone && shouldTriggerMilestone(this.prestigeLevel, this.currentLayer, type)) {
        const dialogueManager = uiScene.dialogueManager;
        dialogueManager.showDialogue(milestone.dialogueId, {
            onComplete: () => completeMilestone(milestone.id),
        });
    }
}
```

### Story Milestones

Milestones are defined with:
- `id`: Unique identifier
- `prestige`: Prestige level (0-8)
- `layer`: Layer number (1-6)
- `type`: Milestone type (game_start, layer_complete, prestige_milestone, boss_defeat, final_boss)
- `character`: Character who speaks
- `dialogueId`: Dialogue to display
- `completed`: Completion status

### Story Progression Flow

1. **Game Start** → White Sentinel mission brief
2. **Layer 1 Complete** → White Sentinel encouragement
3. **Prestige 1** → White Sentinel progression dialogue
4. **Prestige 2** → White Sentinel awakening dialogue
5. **Prestige 3** → Prime Sentinel first contact
6. **Prestige 4-5** → Prime Sentinel revelation dialogues
7. **Prestige 6-7** → Prime Sentinel confrontation dialogues
8. **Prestige 8** → Prime Sentinel final briefing
9. **Final Boss** → Zrechostikal taunt → Prime Sentinel victory

### UIScene Integration

DialogueManager is initialized in UIScene's `create()` method and destroyed in `shutdown()`. GameScene accesses it via scene reference to trigger dialogues.

## 🎮 Game Systems

### Player System

**Location**: `GameScene.ts`

**Properties**:
- `player`: Phaser.Physics.Arcade.Sprite
- `speedMultiplier`: Applied to base speed from power-ups
- `isInvisible`: Boolean flag for invisibility power-up
- `lives`: Current lives count

**Movement**:
```typescript
// Desktop: WASD or Arrow Keys
// Mobile: Virtual joystick (multi-touch enabled)
// Sensitivity: registry key `joystickSensitivity` (0.5x - 2.0x), stored in localStorage
// Speed: PLAYER_CONFIG.speed * speedMultiplier
```

**Shooting**:
```typescript
// Manual: Spacebar or mouse click (desktop)
// Mobile: Fire button held down
// Auto: When autoShootEnabled flag is true
// Fire Rate: PLAYER_CONFIG.fireRate / fireRateMultiplier
// Bullet Count: 1 + Math.floor(firepowerLevel)
```

**Collision**:
- Player-enemy collision: Loses 1 life, enemy survives
- Invincibility period: 1000ms after taking damage
- Invisibility: Prevents all damage

### Enemy System

**Location**: `GameScene.ts`

**Spawn Logic**:
```typescript
// Weighted random selection based on layer
// Formation wave spawns based on difficulty phase and formation chance
// Health scaled by: baseHealth * layerConfig.healthMultiplier
// Spawns from right side only
// Moves toward player with slight randomness
```

**Enemy Types**:
- **Regular Enemies**: Green, Yellow, Blue, Purple
- **Synergy Enemies**: Shield drones, echo decoys, buff nodes, fragmenters
- **Bosses**: Red enemies (spawned separately)
- **Graduation Bosses**: Special bosses for layer progression

**Enemy Sprite System**:
- **Dynamic Sprite Selection**: Enemies use different sprites based on type, boss status, and layer/prestige
- **Sprite Naming**: `{color}{Type}{variant}` (e.g., `greenPawn1`, `yellowBoss2`, `bluePawn3`)
- **Pawn Variants**: Regular enemies use pawn sprites (1-3 variants based on layer complexity)
- **Boss Variants**: Bosses use boss sprites (1-3 variants based on prestige level)
- **Prestige-Based Variants**: 
  - Prestige 0-1: Variant 1
  - Prestige 2-3: Variant 2
  - Prestige 4+: Variant 3
- **Layer-Based Variants** (for pawns):
  - Layer 1-2: Variant 1
  - Layer 3-4: Variant 2
  - Layer 5+: Variant 3
- **Special Cases**:
  - Yellow enemies only have variants 1-2 (no variant 3)
  - Yellow final boss uses `yellowFinalBoss` sprite for high layers
  - Red bosses use legacy sprite system (`finalBoss`, `mediumFinalBoss`, `miniFinalBoss`)

**Boss Spawning**:
```typescript
// Regular Boss: Random chance based on layerConfig.bossChance
// Graduation Boss: Spawns when score threshold reached
// Graduation Boss: 1.5x size (reduced from 3x), 10x health multiplier
// Graduation Boss Assault: 15 seconds assault phase, 3 seconds rest (increased from 10s/5s)
// Graduation Boss Sprite: Selected based on layer and prestige level
//   - Layer 1 → Green boss (variant based on prestige)
//   - Layer 2 → Yellow boss (variant based on prestige)
//   - Layer 3 → Blue boss (variant based on prestige)
//   - Layer 4 → Purple boss (variant based on prestige)
//   - Layer 5 → Green boss (wraps, variant based on prestige)
//   - Layer 6 → Yellow boss (wraps, variant based on prestige)
```

**Boss Shockwave System**:
- **Graduation and Final Bosses** can fire blue shockwaves
- **Shockwave Appearance**: Blue wavy zigzag line that moves like a bullet
- **Shockwave Behavior**: Travels toward player, can be dodged
- **Stun Effect**: On hit, player is stunned for 3 seconds
- **Stun Mechanics**:
  - Player cannot move or shoot while stunned
  - Visual feedback: "STUNNED!" floating text
  - Player velocity set to 0
- **Boss Bullet Lethality**: 
  - Graduation and final boss bullets are 3x more lethal than regular enemy bullets
  - Lethality increases as game progresses (scales with layer and prestige)

**Enemy Behavior**:
- **Movement**: Pursuit + predictive movement in later phases
- **Graduation Boss Movement**: Bounces off all walls (including right edge)
- **Shooting**: Blue enemies shoot every 1.5 seconds; coordinated fire syncs in phase 3+
- **Graduation Boss Assault Phases**: 15 seconds of aggressive shooting (3-bullet spread), 3 seconds rest (increased assault duration)
- **Space Denial**: Graduation bosses add spread bursts in later phases
- **Synergy Effects**:
  - **Shield Drones (yellowShield)**: 
    - Shield radius: 100 (halved from 200) - more dangerous proximity
    - Proximity damage: Deals 1 life of damage on contact (500ms interval)
    - Visual indicator: Red pulsing aura (instead of yellow) to indicate danger
    - Still reduces damage for nearby enemies by 50%
  - Buff nodes increase nearby fire rate and damage
  - Fragmenters split into greens on death
  - Echo enemies spawn decoy after-images
- **Health Bars**: Dynamic health bars above all enemies
- **Destruction**: Destroyed when health reaches 0 or goes off-screen right

### Bullet System

**Location**: `GameScene.ts`

**Player Bullets**:
- **Group**: `bullets` (Phaser.Physics.Arcade.Group)
- **Max Size**: 100 (supports multiple bullets per shot)
- **Speed**: PLAYER_CONFIG.bulletSpeed (600)
- **Direction**: Forward with optional spread at higher firepower
- **Multi-shot**: Based on `firepowerLevel` (0.5 increments)

**Enemy Bullets**:
- **Group**: `enemyBullets` (Phaser.Physics.Arcade.Group)
- **Max Size**: 30
- **Speed**: ENEMY_CONFIG.blue.bulletSpeed (250)
- **Direction**: Toward player
- **Shooter**: Blue enemies and graduation bosses

### Power-Up System

**Location**: `GameScene.ts`

**Spawn Logic**:
```typescript
// From enemies: 15% chance from purple/red enemies (reduced from 25%)
// Lives: 12% chance from all enemies (reduced from 35%)
// Firepower: 5% chance from all enemies (reduced from 8%)
// Invisibility: 10% chance from all enemies (reduced from 15%)
// Other: Random from remaining types
```

**Power-Up Types**:
- **Speed**: Increases `speedMultiplier` to 1.5
- **Fire Rate**: Sets `fireRateMultiplier` to 0.5
- **Score**: Sets `scoreMultiplier` to 2
- **Auto-Shoot**: Sets `autoShootEnabled` to true
- **Lives**: Adds 2 to `lives` count (capped at MAX_LIVES = 20)
- **Firepower**: Increases `firepowerLevel` by 0.5
- **Invisibility**: Sets `isInvisible` to true, player alpha to 0.3

**Power-Up Degradation System**:
- **Mechanic**: Taking damage from enemies reduces firepower upgrades
- **Trigger**: Every 2 hits from enemy bullets triggers degradation
- **Degradation Effects**:
  - Reduces `firepowerLevel` by 0.5 (one upgrade worth)
  - Increases `fireRateMultiplier` by 10% (makes firing slower)
  - Maximum `fireRateMultiplier` cap: 2.0
- **Visual Feedback**: "UPGRADE DEGRADED!" floating text on degradation
- **Tracking**: 
  - `totalFirepowerUpgrades`: Total upgrades collected
  - `enemyBulletHits`: Counter for degradation trigger
  - `baseFireRateMultiplier`: Base fire rate before degradation
- **Reset**: All degradation variables reset on game restart

**Lives Cap**:
- Maximum lives: 20 (4 orbs × 5 lives per orb)
- Enforced when collecting Life Orbs and challenge rewards
- Prevents unlimited life accumulation

**Timer Management**:
```typescript
// Power-up timers stored in Map<string, TimerEvent>
// Auto-cleanup on expiration
// Despawn timer: 6 seconds for uncollected power-ups
// Fade-out: Starts at 5 seconds
```

### Scoring System

**Location**: `GameScene.ts`

**Score Calculation**:
```typescript
basePoints = enemy.points;
// addScore is called with basePoints * comboMultiplier
adjustedPoints = Math.floor(basePoints * comboMultiplier * scoreMultiplier * corruptionMultiplier);
totalScore += adjustedPoints;
```

**Combo System**:
```typescript
// Starts at 1.0x
// Increases by 0.1x per enemy destroyed
// Resets to 1.0x on player hit
// Slowly decays after 10s without scoring (combo *= 0.99 per update tick)
```

**Layer Progression**:
```typescript
// Checks score against LAYER_CONFIG thresholds
// If threshold reached and no graduation boss active:
//   - Spawns graduation boss
//   - Sets pendingLayer
// On graduation boss defeat:
//   - Updates currentLayer
//   - Updates deepestLayer
//   - Resumes normal spawning
// On Layer 6 graduation boss defeat:
//   - Enters prestige mode and loops back to Layer 1
```

### Lives System

**Location**: `GameScene.ts`

**Mechanics**:
- **Starting Lives**: 1 (PLAYER_CONFIG.initialLives)
- **Life Orbs**: Grant +2 lives each (no cap)
- **Damage**: Lose 1 life on enemy collision
- **Game Over**: When lives === 0
- **Invincibility**: 1000ms after taking damage

---

## 🎬 Scene Architecture

### BootScene

**Purpose**: Asset loading

**Key Methods**:
- `preload()`: Loads all sprites, fonts, assets
- `create()`: Starts GameScene and launches UIScene

**Assets Loaded**:
- Player sprites: `hero`, `hero_2`, `hero_3`, `sidekick`, `hero_sidekick_2`
- Enemy sprites: All enemy types and variants
- Bullet sprites: `greenBullet1`, `greenBullet2`, `yellowBullet`, `blueBullet`
- Explosion sprites: `smallFire`, `mediumFire`, `bigFire`, `greenFire`
- Power-up sprites: `power_up`, `power_up_2`, `orb`
- Boss sprites: All boss variants

### GameScene

**Purpose**: Main gameplay

**Key Properties**:
- `player`: Player sprite
- `bullets`: Player bullet group
- `enemyBullets`: Enemy bullet group
- `enemies`: Enemy group
- `powerUps`: Power-up group
- `explosions`: Explosion group
- `score`, `lives`, `currentLayer`, etc.

**Key Methods**:
- `create()`: Initializes game, shows instruction modal
- `update()`: Main game loop
- `spawnEnemy()`: Spawns enemies based on layer
- `spawnBoss()`: Spawns regular bosses
- `spawnGraduationBoss()`: Spawns layer progression bosses
- `shoot()`: Player shooting logic
- `handleBulletEnemyCollision()`: Bullet-enemy collision
- `handlePlayerEnemyCollision()`: Player-enemy collision
- `handlePlayerPowerUpCollision()`: Power-up collection
- `addScore()`: Score calculation and layer progression
- `updateLayer()`: Layer progression logic
- `drawBackgroundGrid()`: Background rendering
- `drawProgressBar()`: Progress bar rendering
- `createEnemyHealthBar()`: Health bar creation
- `updateEnemyHealthBar()`: Health bar updates
- `showAnnouncement()`: Announcement cards
- `showInstructionModal()`: Game start instructions

**Update Loop**:
```typescript
update() {
    if (gameOver || isPaused) return;
    
    // Handle input
    handlePlayerMovement();
    
    // Auto-shoot if enabled; otherwise use mobile fire button or desktop input
    if (autoShootEnabled || fireButtonHeld || spaceKeyDown || pointerDown) {
        shoot();
    }
    
    // Update enemies
    enemies.children.entries.forEach(enemy => {
        // Bounce logic
        // Shooting logic (blue enemies)
        // Health bar position updates
        // Off-screen cleanup
    });
    
    // Update power-ups
    // Update bullets
    // Update explosions
}
```

### UIScene

**Purpose**: UI overlay

**Key Properties**:
- `scoreText`, `comboText`, `layerText`: UI text elements
- `livesOrb`: Lives orb indicator graphic
- `gameOverContainer`: Game over modal
- `pauseContainer`: Pause modal
- `settingsContainer`: Joystick settings panel
- `leaderboardPanel`: Leaderboard display (auto-hide timer)
- `pauseButton`: Pause button

**Key Methods**:
- `create()`: Initializes UI elements
- `updateScore()`: Updates score display
- `updateCombo()`: Updates combo display
- `updateLayer()`: Updates layer display
- `updateLives()`: Updates lives display
- `updateRunStats()`: Updates session stats HUD
- `onGameOver()`: Shows game over modal
- `onPauseChanged()`: Shows/hides pause modal
- `showLeaderboard()`: Displays leaderboard (auto-hides after delay)
- `createLeaderboardPanel()`: Creates leaderboard UI
- `createSettingsOverlay()`: Creates joystick sensitivity settings
- `adjustSensitivity()`: Updates sensitivity and localStorage
- `createPauseButton()`: Creates pause button
- `createButton()`: Button creation helper
- `createShockBombMeter()`: Creates shock bomb meter UI
- `createGodModeMeter()`: Creates god mode meter UI
- `renderShockBombFill()`: Updates shock bomb meter fill
- `renderGodModeFill()`: Updates god mode meter fill

### Floating Combat Text

**Location**: `GameScene.ts`

**Behavior**:
- Damage numbers are spawned on enemy hit
- Critical hits use larger font and brighter color (bosses or high combo)
- Combo pings appear on each kill
- Score milestones show centered banner text
- Power-up degradation shows "UPGRADE DEGRADED!" text
- Stun effects show "STUNNED!" text in cyan
- Shield damage shows "SHIELD DAMAGE!" text in red

### White Sentinel Guide System

**Location**: `TooltipManager.ts` and `GameScene.ts`

**Purpose**: In-game guide character that delivers tooltips and guidance

**Implementation**:
- **Sprite**: `whiteSentinel` (60x60px image)
- **Introduction**: Introduced at game start (500ms delay) with "WHITE SENTINEL ONLINE" text
- **Tooltip Integration**: 
  - White Sentinel sprite appears in every tooltip (left side)
  - Tooltip width increased to 300px to accommodate sentinel
  - Pulsing cyan glow effect around sentinel
  - Text positioned to the right of the sentinel
- **Tooltip Messages**: All tooltip messages rewritten from White Sentinel's perspective
  - Example: "I'm tracking your combo multiplier, Commander. Destroy enemies without taking damage to build it up for massive scores!"
- **Visual Effects**:
  - Pulsing glow animation (alpha 0.3-0.6, 1500ms cycle)
  - Blend mode: ADD for glow effect
  - Depth: Above tooltip background, below text

### Layer Background System

**Location**: `GameScene.ts`

**Purpose**: Layer-specific background images for visual variety

**Implementation**:
- **Background Images**: 
  - Layer 1: No background (grid only)
  - Layer 2: `layerFirewall` (Firewall layer)
  - Layer 3: `layerSecurityCore` (Security Core layer)
  - Layer 4: `layerCorruptedAI` (Corrupted AI layer)
  - Layer 5: `layerKernelBreach` (Kernel Breach layer)
  - Layer 6: `layerSystemCollapse` (System Collapse layer)
- **Background Properties**:
  - Depth: -1000 (behind everything)
  - Alpha: 0.3 (semi-transparent)
  - Blend Mode: NORMAL
  - Scroll Factor: 0 (fixed position)
- **Dark Overlay**:
  - 70% black overlay on top of background (depth: -999)
  - Increases "blackness" for better contrast
  - Blend Mode: NORMAL
  - Scroll Factor: 0 (fixed position)
- **Prestige Display**:
  - `layerPrestige` image briefly appears when entering prestige mode
  - Fade in (500ms), hold (2000ms), fade out (500ms)
  - Alpha: 0.6 during display
  - Overlay effect, then destroyed
- **Player Visibility Safeguard**:
  - Player explicitly set to `alpha: 1` and `depth: 100` when backgrounds are active
  - Continuous check in update loop to ensure player remains visible

**Registry Listeners**:
```typescript
registry.events.on('changedata-score', updateScore);
registry.events.on('changedata-comboMultiplier', updateCombo);
registry.events.on('changedata-layerName', updateLayer);
registry.events.on('changedata-lives', updateLives);
registry.events.on('changedata-gameOver', onGameOver);
registry.events.on('changedata-isPaused', onPauseChanged);
```

---

## 💥 Physics & Collisions

### Physics Engine

**Type**: Phaser Arcade Physics

**Configuration**:
```typescript
physics: {
    default: "arcade",
    arcade: {
        gravity: { x: 0, y: 0 },  // No gravity
        debug: false,              // Debug mode off
    },
}
```

### Collision Groups

1. **Player ↔ Enemies**: `physics.add.overlap(player, enemies)`
2. **Bullets ↔ Enemies**: `physics.add.overlap(bullets, enemies)`
3. **Player ↔ Enemy Bullets**: `physics.add.overlap(player, enemyBullets)`
4. **Player ↔ Power-ups**: `physics.add.overlap(player, powerUps)`

### Collision Handlers

**Bullet-Enemy Collision**:
```typescript
handleBulletEnemyCollision(bullet, enemy) {
    // Remove bullet
    // Reduce enemy health
    // Update health bar
    // If health <= 0: destroy enemy, add score, spawn power-up
    // If graduation boss: advance layer
}
```

**Player-Enemy Collision**:
```typescript
handlePlayerEnemyCollision(player, enemy) {
    // Check invincibility period
    // Check invisibility
    // Call takeDamage()
    // Enemy survives (doesn't die)
}
```

**Player-Power-up Collision**:
```typescript
handlePlayerPowerUpCollision(player, powerUp) {
    // Get power-up type
    // Apply effect based on type
    // Set timer for temporary effects
    // Destroy power-up
}
```

### Boundary Behavior

- **Player**: `setCollideWorldBounds(true)` - Stays on screen
- **Enemies**: Bounce off top, bottom, left walls; destroyed off right
- **Bullets**: Destroyed when off-screen
- **Power-ups**: Destroyed after 6 seconds if uncollected

---

## 📊 State Management

### Phaser Registry

**Purpose**: Cross-scene state communication

**Registry Keys** (see [DATASTRUCTURES.md](./DATASTRUCTURES.md) for full list):
- `score`: Current score
- `comboMultiplier`: Current combo multiplier
- `layerName`: Current layer name
- `currentLayer`: Current layer number
- `lives`: Current lives count
- `healthBars`: Current health bars (segment count)
- `maxHealthBars`: Max health bars this run (5 or 6 with pregame upgrade)
- `gameOver`: Game over flag
- `pregameSessionEffects`: Session-only upgrade effects (from PregameUpgradesModal)
- `finalScore`: Final score on game over
- `deepestLayer`: Deepest layer reached
- `isPaused`: Pause state
- `walletAddress`: Connected wallet address
- `joystickSensitivity`: Mobile joystick sensitivity (0.5x - 2.0x)
- `prestigeLevel`: Current prestige cycle
- `prestigeScoreMultiplier`: Current prestige score multiplier
- `prestigeDifficultyMultiplier`: Current prestige difficulty multiplier
- `prestigeChampion`: Boolean for Prestige 10 badge
- `corruption`: Current corruption level (0-100)
- `overclockActive`: Boolean for active overclock
- `overclockProgress`: Remaining duration (0-1)
- `overclockCooldown`: Remaining cooldown (0-1)
- `overclockCharges`: Remaining activations
- `shockBombProgress`: Shock bomb meter fill (0-1)
- `shockBombReady`: Boolean for shock bomb ready state
- `godModeProgress`: God mode meter fill (0-1)
- `godModeReady`: Boolean for god mode ready state
- `godModeActive`: Boolean for active god mode
- `challengeActive`: Whether a micro-challenge is live
- `challengeTitle`: UI banner title
- `challengeDescription`: UI banner description
- `challengeProgress`: Progress (0-1)
- `uiGlitchIntensity`: HUD glitch intensity (0-1)
- `musicBpm`: Current music tempo target (for future audio sync)
- `runStats`: Live session stats (survival time, accuracy, dodges, etc.)

**Usage**:
```typescript
// Set value
registry.set("score", newScore);

// Get value
const score = registry.get("score");

// Listen to changes
registry.events.on('changedata-score', callback);
```

### GameScene State

**Properties**:
- `score`, `lives`, `currentLayer`, `deepestLayer`
- `prestigeLevel`, `prestigeScoreMultiplier`, `prestigeDifficultyMultiplier`
- `corruption`, `currentCorruptionTier`
- `comboMultiplier`, `speedMultiplier`, `fireRateMultiplier`, `scoreMultiplier`
- `autoShootEnabled`, `isInvisible`, `firepowerLevel`
- `gameOver`, `isPaused`, `graduationBossActive`, `pendingLayer`
- `powerUpTimers`: Map of active power-up timers

### React State

**LandingPage**:
- `leaderboard`: Leaderboard data
- `currentWeek`: Current ISO week number
- `showWalletModal`: Wallet modal visibility
- `showStoryModal`: Story modal visibility

**GamePage**:
- `gameRef`: Reference to Phaser game instance
- Exposes `returnToMenu` function to Phaser
- Passes `gameplaySettings`, `coins`, `pregameSessionEffects` (from `location.state?.pregameUpgrades`) into registry on init

### Data Structures Reference

For a full list of **localStorage keys**, **Phaser Registry keys**, **service types**, and **data flow** (React → GamePage → Registry → GameScene), see **[DATASTRUCTURES.md](./DATASTRUCTURES.md)**.

---

## 🎨 Asset Management

### Sprite Loading

**Location**: `BootScene.ts`

**Sprite Paths**: 
- Hero sprites: `/hero/` directory
- Enemy sprites: `/green-enemies/`, `/yellow-enemies/`, `/blue-enemies/`, `/purple-enemies/` directories
- Legacy sprites: `/sprites/` directory (fallback)
- Background images: `/scenes/` directory
- Guide character: `/white-sentinel.png`

**Hero Sprite Keys**:
- Base grades: `heroGrade1`, `heroGrade2`, `heroGrade3`, `heroGrade4`, `heroGrade5`
- Colored variants: `heroGrade1Blue`, `heroGrade2Purple`, `heroGrade3Red`, `heroGrade4Orange`, `heroGrade5White`
- Legacy (fallback): `hero`, `heroVanguard`, `heroGhost`, `heroDrone`, `heroGodMode`

**Enemy Sprite Keys**:
- **Green**: `greenPawn1`, `greenPawn2`, `greenPawn3`, `greenBoss1`, `greenBoss2`, `greenBoss3`
- **Yellow**: `yellowPawn1`, `yellowPawn2`, `yellowBoss1`, `yellowBoss2`, `yellowFinalBoss`
- **Blue**: `bluePawn1`, `bluePawn2`, `bluePawn3`, `blueBoss1`, `blueBoss2`, `blueBoss3`
- **Purple**: `purplePawn1`, `purplePawn2`, `purplePawn3`, `purpleBoss1`, `purpleBoss2`, `purpleBoss3`
- **Legacy (fallback)**: `enemyGreen`, `enemyYellow`, `enemyBlue`, `enemyPurple`, `enemyPurpleBoss`, `miniFinalBoss`, `mediumFinalBoss`, `finalBoss`

**Other Sprite Keys**:
- Bullets: `greenBullet1`, `greenBullet2`, `yellowBullet`, `blueBullet`
- Explosions: `smallFire`, `mediumFire`, `bigFire`, `greenFire`
- Power-ups: `power_up`, `power_up_2`, `orb`
- Guide: `whiteSentinel`
- Backgrounds: `layerFirewall`, `layerSecurityCore`, `layerCorruptedAI`, `layerKernelBreach`, `layerSystemCollapse`, `layerPrestige`

### Sprite Scaling

**Base Scale**: 0.5 (50% of original size)
**Mobile Scale**: `MOBILE_SCALE` (0.5 on mobile, 1.0 on desktop)
**Final Scale**: `baseScale * MOBILE_SCALE`

**Examples**:
- Player: `0.5 * MOBILE_SCALE`
- Enemies: `0.5 * MOBILE_SCALE`
- Bullets: `0.3 * MOBILE_SCALE`
- Power-ups: `0.4 * MOBILE_SCALE`
- Bosses: `0.6 * MOBILE_SCALE` (regular), `0.7 * 1.5 * MOBILE_SCALE` (graduation - reduced from 3x)

### Font Loading

**Location**: `src/index.css`

**Fonts**:
- Bungee (logoFont)
- Rajdhani (menuFont)
- Share Tech Mono (scoreFont)
- JetBrains Mono (bodyFont)

**Usage**: Loaded via Google Fonts `@import`

---

## ⚡ Performance Optimization

### Object Pooling

**Bullets**: Phaser Groups with `maxSize` limit
- Player bullets: 100 max
- Enemy bullets: 30 max

**Enemies**: Dynamic group, cleaned up on destruction

**Power-ups**: Dynamic group, auto-despawn after 6 seconds

### Rendering Optimization

- **Background Grid**: Redrawn only on layer change
- **Health Bars**: Updated only when health changes
- **Progress Bar**: Redrawn on score changes
- **UI Elements**: Static, updated via registry listeners

### Mobile Optimizations

- **Sprite Scaling**: 50% size on mobile
- **UI Scaling**: 60-80% size on mobile
- **Reduced Effects**: Lower shadow/glow intensity
- **Touch Controls**: Simplified input handling

### Memory Management

- **Destroy on Off-screen**: Enemies destroyed when off-screen right
- **Timer Cleanup**: Power-up timers cleaned up on expiration
- **Graphics Cleanup**: Health bars destroyed with enemies
- **Event Cleanup**: Event listeners removed on scene shutdown

---

## 📱 Mobile Support

### Mobile Detection

```typescript
function isMobileDevice(): boolean {
    return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
        navigator.userAgent
    ) || window.innerWidth <= 768;
}
```

### Mobile Scaling

**MOBILE_SCALE**: 0.5 on mobile, 1.0 on desktop

**Applied To**:
- All sprite scales
- UI font sizes
- UI element positions
- Button sizes

### Touch Controls

**Implementation**: `GameScene.ts`

**Touch Events**:
- `pointerdown`: Capture joystick or fire button pointer
- `pointermove`: Update joystick vector
- `pointerup`: Reset joystick or stop firing

**Behavior**:
- Player moves based on joystick vector
- Fire button enables continuous firing
- Multi-touch allows moving and firing simultaneously

**Settings**:
- Joystick sensitivity is adjustable (0.5x - 2.0x) and persisted in localStorage
- Movement speed: Same as keyboard input

### Mobile UI

**Scaling**:
- Score: 56px → 33.6px (60% scale)
- Combo: 24px → 14.4px
- Layer: 12px → 7.2px
- Lives: Orb indicators scale with UI (no numeric text)

**Opacity**: 85-90% on mobile to reduce obstruction

**Buttons**: Scaled to 70-80% size

---

## 🔌 Integration Points

### React ↔ Phaser

**React → Phaser**:
```typescript
// GamePage.tsx
const gameRef = useRef<Phaser.Game | null>(null);

// Expose function to Phaser
(window as any).returnToMenu = () => {
    navigate('/');
};
```

**Phaser → React**:
```typescript
// GameScene.ts
const returnToMenu = (window as any).returnToMenu;
if (returnToMenu) returnToMenu();
```

### Player Identity

**Anonymous Mode** (all players):
- Anonymous ID stored in localStorage: `neon_sentinel_anonymous_id`
- Score submission uses anonymous ID for leaderboard tracking
- Leaderboard shows "Anonymous" for player names

**Onboarding State**:
- Story modal seen: `neon-sentinel-story-modal-seen`
- Joystick sensitivity: `neon-sentinel-joystick-sensitivity`

### Score Service

**Location**: `src/services/scoreService.ts`

**Functions**:
- `submitScore(score, walletAddress?, deepestLayer?, prestigeLevel?, runMetrics?, modifierKey?)`: Submit score with run metrics + modifier
- `fetchWeeklyLeaderboard()`: Basic weekly score leaderboard for in-game UI
- `fetchWeeklyChallengeLeaderboard()`: Weekly leaderboard for modifier runs
- `fetchWeeklyCategoryLeaderboard(category)`: Weekly leaderboard by category
- `fetchAllTimeCategoryLeaderboard(category)`: All-time leaderboard by category
- `getFeaturedWeeklyCategories(week, count)`: Rotation helper for featured categories
- `getCurrentISOWeek()`: Get current ISO week number

**Storage**: localStorage (mock implementation)

**Weekly Reset**: Based on ISO week number

### Achievement Service

**Location**: `src/services/achievementService.ts`

**Responsibilities**:
- Persist unlocked achievements and progress
- Track lifetime totals (score/playtime)
- Provide unlocked badges/cosmetics and selection
- Manage hero and skin unlocks
- Track profile stats and best runs

### Coin Service

**Location**: `src/services/coinService.ts`

**Responsibilities**:
- Daily coin system (3 coins per day)
- Coin consumption for special features
- Coin tracking and persistence
- Daily reset at midnight

**Functions**:
- `getAvailableCoins()`: Get current coin count
- `consumeCoins(cost)`: Spend coins (returns success/failure)
- `addCoins(amount)`: Add coins to balance
- `getDailyCoinCount()`: Get daily coin allocation

### Pregame Upgrade Service

**Location**: `src/services/pregameUpgradeService.ts`

**Responsibilities**:
- Define session-only upgrades (extra health, max health cap, bullet damage, fire rate, power-up duration, movement speed)
- Merge selected upgrade IDs into a single `PregameSessionEffects` object for the game
- No persistence: selection is passed via React Router state to GamePage, then into Phaser registry as `pregameSessionEffects`

**Flow**: LandingPage "Start Game" → PregameUpgradesModal → user selects upgrades and "Launch" → `navigate('/play', { state: { pregameUpgrades: ids } })` → GamePage calls `mergePregameEffects(ids)` and `game.registry.set('pregameSessionEffects', effects)` → GameScene applies effects in `applyPregameSessionEffects()` (max/initial health bars, damage/fire rate/powerup duration/speed multipliers).

### Ability Service

**Location**: `src/services/abilityService.ts`

**Responsibilities**:
- Check unlock status for Shock Bomb and God Mode
- Calculate unlock progress and remaining score needed
- Uses lifetime score from achievement service

**Functions**:
- `isShockBombUnlocked()`: Check if Shock Bomb is unlocked (10,000 lifetime score)
- `isGodModeUnlocked()`: Check if God Mode is unlocked (25,000 lifetime score)
- `getShockBombUnlockProgress()`: Get unlock progress (0-1)
- `getGodModeUnlockProgress()`: Get unlock progress (0-1)
- `getShockBombRemainingScore()`: Get remaining score needed
- `getGodModeRemainingScore()`: Get remaining score needed

### Session Reward Service

**Location**: `src/services/sessionRewardService.ts`

**Responsibilities**:
- Track session start/end times
- Update lifetime playtime
- Manage session-based rewards

### Settings Service

**Location**: `src/services/settingsService.ts`

**Responsibilities**:
- Persist gameplay settings (difficulty, accessibility, visual)
- Load/save user preferences
- Apply settings to game configuration

**Settings Types**:
- `difficulty`: Easy/Hard mode modifiers
- `accessibility`: Color blind, high contrast, dyslexia font, reduced motion/flash
- `visual`: UI scale, opacity, screen shake, grid intensity

---

## 🏗️ Build & Deployment

### Build Commands

```bash
# Development
yarn dev

# Production build
yarn build

# Preview production build
yarn preview
```

### Build Output

**Location**: `dist/`

**Structure**:
- `index.html`: Main HTML file
- `assets/`: Bundled JS/CSS files
- `sprites/`: Sprite files (copied from public)

### Vite Configuration

**Key Settings**:
- React plugin
- TypeScript support
- PostCSS for Tailwind
- Asset handling for SVGs
- PWA manifest + service worker via `vite-plugin-pwa`
- Dev server allowlist for ngrok

### PWA Support

- Service worker registered in `src/main.tsx` via `virtual:pwa-register`
- Auto-update enabled with `registerType: 'autoUpdate'`
- Icons and manifest defined in `vite.config.ts`

### Environment Variables

No required environment variables for basic operation.

---

## 🐛 Debugging

### Phaser Debug Mode

**Enable**: Set `debug: true` in physics config

**Features**:
- Collision box visualization
- Velocity vectors
- Body bounds

### Console Logging

**Key Log Points**:
- Layer progression
- Boss spawning
- Score submission
- Power-up collection

### Registry Inspection

```typescript
// In browser console
const game = window.gameInstance;
const registry = game.scene.scenes[1].registry;
console.log(registry.getAll());
```

---

## 📝 Code Style

### TypeScript

- **Strict Mode**: Enabled
- **Type Safety**: All types explicitly defined
- **Interfaces**: Used for complex objects

### Naming Conventions

- **Classes**: PascalCase (`GameScene`)
- **Methods**: camelCase (`spawnEnemy`)
- **Constants**: UPPER_SNAKE_CASE (`PLAYER_CONFIG`)
- **Private Properties**: camelCase with `private` keyword

### File Organization

- **One class per file**: Each scene in separate file
- **Config centralized**: All config in `config.ts`
- **Services separated**: Business logic in `services/`

---

## 🔄 Future Enhancements

### Potential Improvements

1. **Backend Integration**: Replace localStorage with real API
2. **Multiplayer**: Add co-op or competitive modes
3. **Achievements**: Unlock system for milestones
4. **Sound Effects**: Audio feedback for actions
5. **Particle Effects**: Enhanced visual effects
6. **Save System**: Save progress between sessions
7. **Replay System**: Record and replay games
8. **Tournament Mode**: Time-limited competitions

---

## 📚 Additional Resources

### Phaser 3 Documentation
- https://photonstorm.github.io/phaser3-docs/

### React Documentation
- https://react.dev/

### Dynamic Labs Documentation
- https://docs.dynamic.xyz/

### TypeScript Documentation
- https://www.typescriptlang.org/docs/

---

*Last Updated: Game Version 2.0 - 2026-01-27 (Hero Grade System & Enemy Sprite Overhaul)*
*Maintained by: Neon Sentinel Development Team*

---

## 🆕 Recent Updates (v2.0)

### Hero Grade System
- **New System**: Unlockable hero grades (1-5) representing skill progression
- **Colored Variants**: Kernels now map to colored sprite variants (blue, purple, red, orange, white)
- **Permanent Bonuses**: Each grade provides speed, fire rate, health, and damage bonuses
- **Unlock Conditions**: Based on lifetime playtime, kills, score, and deepest layer reached

### Enemy Sprite System
- **Dynamic Sprites**: Enemies now use different sprites based on type, boss status, layer, and prestige
- **Pawn/Boss Variants**: Separate sprites for regular enemies (pawns) and bosses
- **Complexity Levels**: 3 variants per color (1-3) reflecting game progression
- **Prestige Integration**: Boss variants change based on prestige level (2 prestiges per variant)

### Boss Mechanics Overhaul
- **Reduced Scaling**: Graduation bosses now 1.5x size (reduced from 3x)
- **Shockwave System**: Graduation and final bosses can fire blue shockwaves
- **Stun Mechanic**: Player stunned for 3 seconds on shockwave hit (cannot move or shoot)
- **Increased Lethality**: Boss bullets are 3x more lethal, scaling with progression

### Power-Up Degradation
- **New System**: Taking damage reduces firepower upgrades
- **Degradation Rate**: Every 2 enemy bullet hits reduces firepower by 0.5 and increases fire rate by 10%
- **Visual Feedback**: "UPGRADE DEGRADED!" floating text

### Yellow Shield Enemy Update
- **Reduced Shield Radius**: 100 (halved from 200)
- **Proximity Damage**: Deals 1 life of damage on contact (500ms interval)
- **Visual Indicator**: Red pulsing aura (instead of yellow) to indicate danger

### White Sentinel Guide
- **In-Game Guide**: White Sentinel character integrated into all tooltips
- **Introduction**: Introduced at game start as player's guide
- **Tooltip Redesign**: All tooltips rewritten from White Sentinel's perspective

### Layer Backgrounds
- **Visual Variety**: Each layer (2-6) has its own background image
- **Dark Overlay**: 70% black overlay for better contrast
- **Prestige Display**: Brief prestige layer image on prestige entry
