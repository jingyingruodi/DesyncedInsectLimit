# Desynced Swarm Limit Mod (Insect Limit Mod)

A logic modification mod (Addon) specifically designed to improve the multiplayer server experience.

## 📖 Background
In the original logic of "Desynced", the total number of swarm units (Bugs) has a hard cap (4,000 units), and the spawn rate significantly decreases when the total count exceeds 2,000 units.
While this is sufficient for single-player mode, in multiplayer servers where multiple players share this limit, the "bugs per capita" becomes extremely low. In some cases, bugs accumulating in other areas can prevent new spawns near active players, severely impacting the fun of multiplayer defensive gameplay.

## ✨ Features
By precision-overriding the bug spawner and expansion AI logic, this mod significantly increases multiplayer capacity while maintaining vanilla difficulty balance:
- **Absolute Cap Increase**: Raised the maximum unit count from **4,000** to **30,000**, ensuring everyone has something to fight even with many players.
- **Spawn Wave Optimization**: Optimized the threshold where spawn amounts begin to decrease from **2,000** to **4,000**, balancing performance and intensity.
- **Expansion Range Relaxation**: Increased the threshold for scouts establishing new hives to **10,000**, allowing the swarm to distribute across a much larger portion of the map.
- **Smart Anti-Clumping AI**: Introduced a settlement quota control (maximum 3 hives within a 35-tile radius) to prevent scouts from nesting too densely in one spot, which could lead to performance issues.
- **Vanilla Bugfix**: Fixed a notorious original bug where the swarm would lock onto and infinitely siege "Construction Blueprints", leading to massive unit pile-ups.
- **Server Compatibility**: Pure logic modification with no UI components. Fully supports Dedicated Servers and automatic synchronization.

## 🛠 Installation
1. Download the project files.
2. Place the project folder (or the packaged `InsectLimit.zip`) into the game's `Content/mods/` directory.
3. Start the game and enable it in the Mods menu.
4. **Server Deployment**: Simply place the ZIP package into the server's `mods` directory.

## ⚠️ Notes
- 30,000 units is a theoretical limit; actual performance depends on your server's CPU capability.
- This mod only modifies population caps and distribution logic; it does not change individual bug stats (HP, Attack).

## 📄 License
This project is open-source under the [MIT License](LICENSE).

## 🤝 Contribution & Feedback
Feel free to submit an Issue or Pull Request on GitHub.
