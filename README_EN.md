# Desynced Insect Limit Mod

This mod enhances the swarm AI by fixing core logic defects, decoupling global decision-making, and introducing dynamic player-based scaling to improve late-game performance and multiplayer balance.

## 📖 Key Enhancements (Compared to Vanilla)

### 1. Incursion Distance Truncation & Pathing Optimization
- **Eliminated "Long-Distance Marching"**: Fixed a vanilla defect where swarms would hard-lock onto the player's home base regardless of distance. In vanilla, if a unit enters a hive's range, the entire swarm might attempt to pathfind across thousands of grids, causing massive CPU overhead.
- **250-Grid Smart Truncation**: Implements a 250-grid limit for combat incursions. If the target home base is beyond this range, the swarm automatically re-targets the **nearest visible player unit** that triggered the aggression.
- **Strategic Scout Freedom**: While combat ranges are restricted, scouts retain unlocked pathfinding limits (700+ grids) to ensure natural expansion and strategic depth are maintained.

### 2. Target Validity Filtering (Anti-Piling Core)
- **Blocked Invalid Targets**: Prevents vanilla AI from targeting "Blueprints" or other indestructible objects. This eliminates the "unit piling" bug where swarms would cluster around invalid targets indefinitely, crushing server performance.
- **Strict Logic Interception**: Ensures swarms only initiate incursions against deployed and destructible player entities.

### 3. Enhanced Homing & Stuck-Recovery
- **Improved Homing Responsiveness**: Refined the triggering logic for units returning home after a task is cleared, reducing unnecessary idle time.
- **Pathing Self-Healing**: Introduced smarter stuck-detection and recovery for units navigating complex terrain (cliffs/walls), slightly alleviating the stuttering issues associated with vanilla swarm movement.

### 4. Adaptive Multiplayer Scaling
- **Global Behavioral Decoupling**: Fully decoupled the global shared cooldown for scouting, attacking, and expansion. Independent decision-making across hives significantly increases AI responsiveness in multiplayer.
- **Dual-Scaling Weight System**: 
  - **Population Capacities**: Scale based on **Total Player Count** to maintain the world's intended challenge level even if players are offline.
  - **Decision Frequency**: Throttling cooldowns scale based on **Active Player Count** to balance attack intensity and protect server performance (UPS).

## 🛠 Installation
1. Place the mod folder into the game's `Content/mods/` directory.
2. Enable `InsectLimit` in the in-game Mod menu.

## 📄 License
This project is open-source under the [MIT License](LICENSE).
