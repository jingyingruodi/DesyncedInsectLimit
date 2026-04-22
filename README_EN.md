# Desynced Insect Limit Mod

An optimization mod designed to fix vanilla AI defects, optimize lifecycles, and introduce dynamic scaling based on active players.

## 📖 Key Features (v2.7.2 Final)

### 1. Dynamic Expandable Limit System
- **Adaptive Hard Cap**: Base 12,000 active combat units, with +3,000 for each **active player faction**.
- **Dynamic Soft Limit**: Base 4,000 units, scales with player count; exceeds this and spawn rates are halved to maintain UPS.
- **Dynamic Scout Threshold**: Base 6,000 units, ensuring consistent hive expansion in reasonable ranges.
- **Status Broadcast**: The console now displays `Players: Alive/Total`, allowing for precise server load monitoring.

### 2. Intelligent Expansion & Navigation Fixes
- **Frontline Unit Locking**: Scouts no longer exclusively target the player's home base. They dynamically lock onto the **physically nearest** player unit for expansion, effectively countering "Mobile Base" evasion tactics.
- **Beyond-Visual-Range (BVR) Navigation**: Unlocked scout pathing limits to support precise 700+ grid infiltrations, while combat swarms maintain a 250-grid truncation to protect performance.
- **180s Scout Patience**: Increased the stuck timeout for scouts to 180 seconds (900 ticks), significantly improving the success rate of long-distance nesting missions around player fortifications.

### 3. Lifecycle & Performance Optimization
- **Efficient Scout Management**: Scouts are auto-destroyed after 180s if stuck and are strictly prohibited from returning to hives, freeing up slots for combat units.
- **Anti-Cycle Homing Fix**: If a unit's path to a hive is blocked (e.g., by cliffs or walls), that hive is blacklisted for 250s, forcing the unit to find a different exit.
- **30s Ultra-Efficient Census**: Uses 150-tick low-frequency caching, reducing unit counting overhead to O(1).
- **Target Validity Enforcement**: Filters out blueprints, resource nodes, and neutral explorables at the logic level to prevent unit piling.

### 4. Production-Grade Stability
- **Full Sovereignty Override**: Key spawning logic is rewritten to prevent interference from hidden vanilla variables.
- **Bilingual Documentation**: Code is fully annotated in both Chinese and English for easier maintenance.

## 🛠 Installation
1. Place the mod folder into the game's `Content/mods/` directory.
2. Enable `InsectLimit` in the in-game Mod menu.

## 📄 License
This project is open-source under the [MIT License](LICENSE).
