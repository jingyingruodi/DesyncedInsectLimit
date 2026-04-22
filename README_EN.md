# Desynced Insect Limit Mod

An optimization mod designed to fix vanilla AI defects, optimize lifecycles, and introduce dynamic scaling based on active players.

## 📖 Key Features (v2.7.15 Final Stable)

### 1. Behavioral Decoupling Throttling System (New!)
- **Triple Independent Cooldowns**: Fully decoupled the global cooldowns for "Dispatching Scouts", "Initiating Incursions", and "Natural Hive Expansion".
- **Parallel Decision Making**: Different hives can now perform different tasks simultaneously, eliminating the sluggishness caused by a single shared global timer.
- **Dynamic Scaling**: All throttling frequencies automatically scale based on the number of **active player factions**; more players mean a more aggressive swarm.

### 2. Dynamic Expandable Limit System
- **Adaptive Hard Cap**: Base 12,000 active combat units, with +3,000 for each **active player**.
- **Dynamic Soft Limit**: Base 4,000 units, scales with player count; exceeds this and spawn rates are halved to maintain server UPS.
- **Status Broadcast**: Background logs now display real-time status: `Players: Alive/Total | BOTS: Current/Cap`.

### 3. Intelligent Expansion & Navigation Fixes
- **Frontline Unit Locking**: Scouts dynamically lock onto the **physically nearest** player assets instead of just the home base, countering "Mobile Base" strategies.
- **Precision Pathfinding**: Unlocked scout limits to support 700+ grid infiltrations with a 180s (900 ticks) stuck-tolerance mechanism.
- **Anti-Cycle Homing Fix**: Blocked hive paths (cliffs/walls) trigger a 250s blacklist, forcing units to seek alternative routes.

### 4. Lifecycle & Performance Optimization
- **Precise Combat Detection**: Reconfigured stuck-detection logic. Units only reset their stuck-timers when actually firing or taking damage, solving the "Idle at Low Health" bug where units would permanently occupy population slots.
- **Target Validity Enforcement**: Filters out blueprints, resource nodes, and neutral explorables to prevent unit piling at invalid locations.
- **30s Efficient Census**: Uses 150-tick low-frequency caching, maintaining O(1) complexity for unit counting.

## 🛠 Installation
1. Place the mod folder into the game's `Content/mods/` directory.
2. Enable `InsectLimit` in the in-game Mod menu.

## 📄 License
This project is open-source under the [MIT License](LICENSE).
