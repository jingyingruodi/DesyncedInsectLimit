下·# 关于《Desynced》原版虫群 AI 逻辑缺陷诊断与优化建议 (v2.7.32)
# Swarm AI Logic Diagnostics & Enhancement Report

---

## 中文版 (Chinese Version)

### 1. 跨图寻路导致的性能黑洞 (Long-Distance Pathing Overhead)
*   **诊断**：原版 AI 在发起入侵波次时，即便诱发活跃的玩家单位就在眼前，其逻辑也会强制锁定玩家阵营的 `home_entity`（主基地）。若主基地远在数千格之外，大量单位会开启全图寻路，导致极高的路径计算开销和服务器 UPS 剧烈抖动。
*   **优化**：引入 250 格距离截断机制。若目标主基地超出范围，则自动切换至“就近打击”模式，攻击触发其活跃的周边目标。同时，确保侦察虫不受此限制，以维持正常的战略扩张。

### 2. 目标合法性筛选缺失 (Target Validity Issue)
*   **诊断**：原版 AI 常锁定“建筑蓝图”作为主攻目标。由于这些实体无法被摧毁，导致大量单位在目标点堆积且不进入攻击循环，造成无意义的性能开销。
*   **优化**：引入底层 `IsAttackable` 筛选，确保入侵目标必须是已部署且可被破坏的玩家实体。

### 3. 全局决策锁导致的反应滞后 (Global Cooldown Bottleneck)
*   **诊断**：原版将“派遣侦察”、“发起进攻”与“自然扩张”共用一个全局冷却计时器。在大型地图下，不同行为之间产生严重的互斥竞争。
*   **优化**：解耦派遣、进攻、扩张的全局锁。实现三路独立限速，显著提升了虫群的并行决策效率。

### 4. 分布式压力均衡与寻敌性能优化 (Aggression Polling Optimization)
*   **诊断**：原版 AI 采用全势力遍历逻辑。虽然公平，但在多人高压服务器（31 势力、数万单位）下，每秒成百上千次的势力全扫描会产生显著的计算堆叠。此前模组尝试将其改为“首个目标即截断”以压榨性能，却意外导致了虫群偏向于锁定数组首位势力的副作用。
*   **优化**：v2.7.32 引入了“时空联合偏移环形扫描”。它保留了高性能的“首个合法目标即截断”机制，但通过蜂巢唯一 ID 与游戏刻（Tick）动态计算搜索起点和方向。这在维持极高性能的同时，实现了多人模式下侵略性的物理级平摊。

---

## English Version

### 1. Performance Black-hole via Long-Distance Pathing
*   **Diagnosis**: Vanilla AI forces incursion waves to target the player faction's `home_entity`, even if the assets triggering the hive's aggression are thousands of grids away. This results in hundreds of units attempting cross-map pathfinding, causing severe server-side stuttering.
*   **Optimization**: Implemented a 250-grid truncation. If the home base is out of range, units fallback to "Nearby Attack" mode. Scouts are excluded from this limit to preserve strategic expansion depth.

### 2. Target Validity Filtering
*   **Diagnosis**: Vanilla AI often targets "Blueprints" as its main attack target. Since these cannot be destroyed, units pile up indefinitely, crashing performance.
*   **Fix**: Introduced the `IsAttackable` filter to ensure swarms only target deployed and destructible entities.

### 3. Shared Global Cooldown Bottleneck
*   **Diagnosis**: Scouting, Attacking, and Expansion share a single branch of logic in vanilla. In large-scale games, these behaviors compete for execution, leading to tactical unresponsiveness.
*   **Optimization**: Decoupled cooling timers for scouting, attacking, and expansion, allowing independent and parallel decision-making across all hives.

### 4. Distributed Aggression Balancing & Polling Performance
*   **Diagnosis**: Vanilla AI uses a full-faction iteration logic. While fair, it creates significant computational overhead in high-load multiplayer environments (31 factions, 20k+ assets). Previous mod versions optimized this via "early-exit polling" to save CPU cycles, which inadvertently caused all aggression to focus on the first available player.
*   **Optimization**: v2.7.32 introduces the "Spatiotemporal Offset Ring Scan." It maintains the high-performance "Early-Exit" mechanism while using the Hive's unique ID and current Tick to randomize search start-points and directions. This achieves strategic fairness across all players without sacrificing CPU efficiency.
