# Desynced Insect Limit Mod

An optimization mod designed to fix vanilla AI defects, optimize swarming lifecycles, and introduce dynamic scaling based on player activity.

## 📖 Key Features (v2.7.20 Aligned Final)

### 1. Behavioral Decoupling & Faithful Logic (New!)
- **Triple Independent Cooldowns**: Fully decoupled the global cooldowns for "Scouting", "Attacking", and "Expansion". Hives can now perform these activities in parallel.
- **Dynamic Player Scaling**: Throttling frequencies scale based on the number of **active players** (UPS protection), while population caps scale based on **total player count** (world difficulty persistence).

### 2. Intelligent Expansion & Navigation Fixes
- **Frontline Unit Locking**: Scouts dynamically lock onto the **physically nearest** player assets instead of just the home base, countering "Mobile Base" strategies.
- **Precision Pathfinding**: Unlocked scout limits to support 700+ grid infiltrations with a 180s (900 ticks) stuck-tolerance mechanism.
- **Anti-Cycle Homing Fix**: Blocked hive paths (cliffs/walls) trigger a 250s blacklist, forcing units to seek alternative routes.

### 3. Lifecycle & Performance Optimization
- **Precise Combat Detection**: Reconfigured stuck-detection logic. Units only reset their stuck-timers when actually firing or taking damage, solving the "Idle at Low Health" bug where units would permanently occupy population slots.
- **Target Validity Enforcement**: Filters out blueprints, resource nodes, and neutral explorables to prevent unit piling at invalid locations.
- **30s Efficient Census**: Uses 150-tick low-frequency caching, maintaining O(1) complexity for unit counting even with thousands of units.

### 4. Status Dashboard
- **Real-time Monitoring**: The background log now displays a heartbeat every 30s: `Players: Active/Total | BOTS: Current/Cap | Assets: Total`.

## 🛠 Installation
1. Place the mod folder into the game's `Content/mods/` directory.
2. Enable `InsectLimit` in the in-game Mod menu.

## 📄 License
This project is open-source under the [MIT License](LICENSE).
