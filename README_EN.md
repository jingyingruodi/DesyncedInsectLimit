# Desynced Insect Limit Mod

This mod enhances the swarm AI by fixing core logic defects, decoupling global decision-making, and introducing dynamic player-based scaling to improve late-game performance and multiplayer balance.

## 📖 Key Enhancements (Compared to Vanilla)

### 1. Incursion Distance Truncation (Pathing Optimization)
- **Eliminated Long-Distance Marching**: Fixed a vanilla defect where swarms would hard-lock onto the player's home base regardless of distance. In vanilla, if a unit enters a hive's range, the entire swarm might attempt to pathfind across thousands of grids, causing massive CPU overhead.
- **250-Grid Smart Truncation**: This mod implements a 250-grid limit for combat incursions. If the target home base is beyond this range, the swarm automatically re-targets the **nearest visible player unit** instead.
- **Strategic Scout Freedom**: While combat ranges are restricted, scouts retain full-map navigation (up to 700+ grids) to ensure natural expansion and strategic depth are maintained.

### 2. Target Validity Filtering (Anti-Piling Core)
- **Blocked Invalid Targets**: Prevents vanilla AI from targeting blueprints, resource nodes, or neutral explorables. This eliminates the "unit piling" bug where swarms would cluster around indestructible targets and crash server performance.

### 3. Enhanced Homing & Pathing Stability
- **Combat-Task Prioritization**: Replicated and refined the task-locking logic to correctly suppress nesting/homing while units are actively fighting or charging toward frontlines.
- **Improved Homing Responsiveness**: Reduced post-combat idle time and introduced smarter self-healing for units stuck near cliffs or player fortifications.

### 4. Decision Logic & Multiplayer Scaling
- **Global Behavioral Decoupling**: Fully decoupled global cooldowns for scouting, attacking, and expansion, allowing hives to make independent decisions in parallel.
- **Dynamic Dual-Scaling**: Population caps scale based on **Total Player Count** (persistence), while decision frequencies scale based on **Active Players** (UPS protection).

## 🛠 Installation
1. Place the mod folder into the game's `Content/mods/` directory.
2. Enable `InsectLimit` in the in-game Mod menu.

## 📄 License
This project is open-source under the [MIT License](LICENSE).
