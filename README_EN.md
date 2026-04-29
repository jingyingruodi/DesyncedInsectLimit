# Desynced Swarm AI Behavior Optimization & Dynamic Unit Cap Expansion Mod (InsectLimit Mod)

This mod aims to preserve the original swarm ecosystem and sense of pressure as much as possible,
while systematically fixing multiple underlying flaws in the vanilla swarm AI behavior system,
and adding dynamic performance protection mechanisms along with expanded unit caps.

Dedicated servers using the **Swarming** swarm hostility setting are recommended to install this mod, in order to fix issues caused by vanilla bugs and significantly improve late-game performance and stability.

## 📖 Core Changes & Optimizations (Compared to Vanilla)

### This mod performs a deep reconstruction and systematic optimization of vanilla swarm behavior

It resolves issues such as ultra long-distance cross-map pathfinding, mindless traffic blocking, uncontrolled late-game wave scaling, swarms becoming inactive for long periods in multiplayer, losing aggression, and abnormal clustering.

### 1. Attack Range Limiting & Pathfinding Optimization (Reworked)

- **Intercepts “cross-map assault” behavior**: Fixes the flaw where vanilla swarm AI forcibly targets the player's main base. In vanilla, if a player unit appears near a hive, the swarm may attempt to attack across the entire map even if the main base is thousands of tiles away, causing extremely high pathfinding overhead.
- **250-tile smart cutoff**: This mod introduces a distance cutoff system. When an attack is triggered, if the player's main base is more than 250 tiles away, the swarm will automatically switch to attacking nearby **active player units** that triggered it.
- **Scout navigation exemption**: While combat distance is limited, scout units are not subject to a maximum range restriction. Scouts can still travel 250+ tiles for long-range infiltration and expansion, preserving the swarm's strategic reach.

### 2. AI Target Selection & Decision Logic Rework

- **Blocks invalid attack behavior**: Vanilla AI may incorrectly target “building blueprints” as primary attack targets. Since these cannot be destroyed, large numbers of units gather at the target indefinitely. This mod prevents such behavior and ensures targets are attackable player entities.
- **Separated scout and attack decisions**: Scout cooldowns and attack cooldowns are handled independently, preventing one action type from blocking all swarm decisions.
- **Linked assault limit**: Hive-linked attacks are limited to a maximum of 5 nearby hives responding at the same time, preventing excessive wave sizes in extreme situations.

### 3. Return-to-Hive Logic & Performance Improvements

- **Improved return sensitivity**: Further optimizes post-combat return-to-hive behavior and introduces smarter self-recovery logic for stuck units, slightly improving path congestion in complex terrain.
- **Nest-building concurrency limit**: Limits nest-building actions to a maximum of 5 swarm units per tick, reducing burst load.
- **Floating cooldown concurrency optimization**: Adds random variance to hive decision cooldown timers, reducing synchronized spikes while creating a slight chaotic/randomized effect.

### 4. Dynamic Multiplayer Scaling

- **Swarm action cooldown rework**: Replaces the global cooldown for hive attacks and scouting with **an independent global cooldown for each player faction**. This also prevents situations in multiplayer where some players are not attacked for long periods, or are attacked too frequently.
- **Dynamic swarm unit cap scaling**: Unit cap quotas expand based on the **total number of players** to maintain world pressure.

## ⚙ Default Dynamic Caps (Single Player)

- Soft Reduction Threshold: 3000
- Scout Threshold: 6000
- Maximum Unit Cap: 12000

In multiplayer, caps automatically scale upward with player count.

## 🛠 Installation

1. Place the mod folder or compressed archive into the game's `Content/mods/` directory.
2. Enable `InsectLimit` in the mod menu.

## 📄 License

This project is open-source under the [MIT License](LICENSE).