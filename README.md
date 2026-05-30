## 中文版 (Chinese Version)

# Desynced 虫群AI行为优化与动态上限扩展模组 (InsectLimit Mod)

本模组在尽量保持原版虫群生态与压迫感的前提下，
系统性修复原版虫群AI行为机制的多项底层缺陷，
并加入动态性能保护机制与单位上限扩展。

建议虫群敌意等级为**群聚**的专用服务器安装本模组，以修复原版bug带来的问题与显著改善后期性能与稳定性。

## 📖 核心改动与优化 (相较于原版)

### 该模组对原版虫群行为进行了深度重构和系统性的优化
解决超远距离跨图寻路、无脑堵路、多人游戏中虫群长期停摆、失去攻击性、异常聚集等问题。

### 1. 进攻距离截断与寻路优化(重构)
- **拦截“千里奔袭”行为**：修复了原版虫群AI强制锁定玩家主基地作为目标的缺陷。在原版中，若玩家单位在虫巢附近出现，即便主基地远在数千格之外，虫群也会尝试跨越全图发起进攻，造成极高的路径计算开销。
- **250格智能截断**：本模组引入了距离截断机制。当进攻发起时，若玩家主基地超出 250 格，虫群将自动转为打击触发其活跃的**就近玩家单位**。
- **侦察导航解禁**：在限制战斗距离的同时，未限制侦察虫上限距离。侦察虫依然可以跨越 250+ 格的距离进行远距离渗透与扩张，确保虫群的战略纵深。

### 2. AI目标选择、行为决策重构
- **拦截无效攻击行为**：原版 AI 会错误地锁定“建筑蓝图”作为主攻目标。由于这些目标无法被摧毁，导致大量单位在目标点无限期堆积（聚怪），本模组拦截了此类行为，确保目标是可被攻击的玩家实体。
- **虫群侦察进攻决策分离**：侦察冷却与进攻冷却独立冷却时间。避免原版一个行为阻塞全部虫群决策的问题。
- **进攻联动限制**：虫巢联动进攻限制为最多5个附近虫巢同时响应。能避免极端情况下进攻波次过多虫子的情况。

### 3. 归巢逻辑增强与性能优化改善
- **归巢灵敏度优化**：进一步优化了单位在战后的归巢触发逻辑，引入了更智能的卡死自愈逻辑，轻微改善了复杂地形下的路径卡顿。
- **筑巢并发限制**：限制了每tick只能有5个虫群单位进行筑巢行为。降低并发压力。

### 4. 多人环境动态适配
- **虫群行动CD重构**：将虫巢进攻与侦察的全局CD替换为对**每个玩家势力单独一个全局CD**。同时也避免多人环境下部分玩家长期不会被虫群袭击或者被过于频繁的被袭击的问题。
- **虫群单位上限动态缩放**：单位上限配额按**总玩家数**扩展以维持世界强度。

### 5. 距离衰减进攻成功率 (v2.9 新增)
- **进攻概率随距离线性衰减**：50格内发起进攻**100%成功**；250格处仅剩**5%成功率**。失败不消耗全局CD，虫巢进入下一蓄能周期。
- **效果**：稀疏分布的远距离虫巢进攻频率自然降低，密集近身蜂巢压迫感不变——使虫群行为节奏更贴合原版体验。

### 6. 侦察扩张动态抑制 (v2.9 新增)
- **自调节负反馈机制**：每次进攻成功后，该玩家势力侦察CD获得 **+800 tick 抑制值**（上限1400），随时间以 **1/tick 速率自然衰减**。
- **进攻越频繁 → 侦察扩张越消极**：能有效改善一边对玩家疯狂猛攻一边疯狂扩张的情况，优化玩家体验。
- **不会瘫痪**：侦察基础CD 700t，最大CD 2100t（约7分钟），即使饱和进攻下侦察依然周期性发生。
- **多人完全独立**：每个玩家势力各自维护独立的抑制值，互不干扰。
- 
## ⚙ 默认动态上限（单人）

- 削弱上限：3000
- 侦察上限：6000
- 单位上限：12000
多人时上限随玩家数量自动增长。

## 🛠 安装方法
1. 将模组文件夹或是压缩包放入游戏的 `Content/mods/` 目录下。
2. 在模组菜单中启用 `InsectLimit`。

## 📄 许可证
本项目采用 [MIT License](LICENSE) 协议开源。

---

## English Version

# Desynced Swarm AI Behavior Optimization & Dynamic Unit Cap Expansion Mod (InsectLimit Mod)

This mod aims to preserve the original swarm ecosystem and sense of pressure as much as possible,
while systematically fixing multiple underlying flaws in the vanilla swarm AI behavior system,
and adding dynamic performance protection mechanisms along with expanded unit caps.

Dedicated servers using the **Swarming** swarm hostility setting are recommended to install this mod, in order to fix issues caused by vanilla bugs and significantly improve late-game performance and stability.

## 📖 Core Changes & Optimizations (Compared to Vanilla)

### This mod performs a deep reconstruction and systematic optimization of vanilla swarm behavior

It resolves issues such as ultra long-distance cross-map pathfinding, mindless traffic blocking, swarms becoming inactive for long periods in multiplayer, losing aggression, and abnormal clustering.

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

### 4. Dynamic Multiplayer Scaling

- **Swarm action cooldown rework**: Replaces the global cooldown for hive attacks and scouting with **an independent global cooldown for each player faction**. This also prevents situations in multiplayer where some players are not attacked for long periods, or are attacked too frequently.
- **Dynamic swarm unit cap scaling**: Unit cap quotas expand based on the **total number of players** to maintain world pressure.

### 5. Distance-Based Attack Success Rate (v2.9 New)

- **Attack probability decays linearly with distance**: Within 50 tiles → **100% success**; at 250 tiles → only **5% success**. Failed attempts do not consume the global cooldown; the hive returns to its charge cycle.
- **Effect**: Sparse distant hives attack less frequently, while dense nearby hives retain full pressure — bringing swarm pacing closer to vanilla.

### 6. Dynamic Scout Expansion Suppression (v2.9 New)

- **Self-regulating negative feedback**: Each successful attack adds **+800 ticks of suppression** (cap 1400) to that faction's scout cooldown, which naturally decays at **1/tick**.
- **More attacks → slower expansion**: Effectively curbs the scenario where swarms simultaneously relentlessly assault a player while aggressively expanding, improving the overall player experience.
- **Never paralyzed**: Scout base CD is 700t, maximum 2100t (~7 min). Even under saturation attacks, scouting still occurs periodically.
- **Fully independent per player**: Each player faction maintains its own suppression value with zero cross-interference.

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