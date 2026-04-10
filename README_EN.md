# Desynced Insect Limit Mod

A performance optimization and AI-fix mod designed to enhance multiplayer and large-scale gameplay by refining swarm logic and population management.

## 📖 Background
In Desynced's vanilla logic, the swarm has several AI defects (e.g., besieging blueprints, map-wide marches) and a very low global population limit (4,000 entities). In multiplayer, this shared limit results in an inactive swarm during late-game stages, significantly diminishing the challenge of defensive gameplay.

## ✨ Features (v2.5.2)
Rebuilt on a stable logic foundation, this mod achieves a perfect balance between intelligence and performance:

- **AI Defect Fixes**:
  - **Target Validity Verification**: Resolves the bug where swarms would endlessly attack "Blueprints", "Explorables", or "Dropped Items".
  - **Stealth Adaptation**: If a player's home base is cloaked, the swarm intelligently shifts focus to nearby visible active units instead of idling.
  - **Distance Truncation**: Fixes the "Long-Distance Trek" bug. If the primary target is too far (>250 grids), the swarm will attack the nearest player assets instead of marching across the entire map.

- **Extreme Performance Optimization**:
  - **30s Global Census Heartbeat**: Implements a low-frequency statistical caching mechanism, reducing swarm counting overhead to O(1) complexity.
  - **Sampled Target Search**: Hive targeting algorithms now use random sampling instead of full-map scans, significantly reducing server load.

- **Scale & Quota Enhancements**:
  - **Limit Increase**: Maximum combat unit capacity raised to **30,000** active units.
  - **Spawn Rate Retention**: The threshold where spawn rates begin to decline has been increased from 2,000 to **4,000**.
  - **Expansion Policy**: The entity limit for dispatching scouts to build new hives has been increased to **10,000**.
  - **Unit-Only Census Philosophy**: The limit **only counts active combat units**. Hive structures no longer consume the spawn quota, ensuring consistent offensive pressure as the swarm expands.
  - **Automated Virus Recycling**: Refined the shutdown and perish countdown for low-tier infected units to auto-clear invalid entities.

- **Server Compatibility**: Pure logic modification, fully compatible with Dedicated Servers and automatic synchronization.

## 🛠 Installation
1. Download the project files.
2. Place the mod folder (or the packaged Zip compressed file) into the `Desynced/Content/mods/` directory.
3. Enable the mod in the in-game Mod menu.

## ⚠️ Notes
- **TPS Adaptation**: Optimized specifically for the game's 5 TPS (5 ticks per second) environment.
- **Performance Tip**: 30,000 is a theoretical maximum; actual performance depends on the server's CPU capability.

## 📄 License
Licensed under the [MIT License](LICENSE).
