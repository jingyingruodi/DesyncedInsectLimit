# 关于《Desynced》原版虫群 AI 逻辑缺陷诊断与优化建议 (v2.7.21)
# Swarm AI Logic Diagnostics & Enhancement Report

---

## 中文版 (Chinese Version)

### 1. 跨图寻路导致的性能黑洞 (Long-Distance Pathing Overhead)
*   **诊断**：原版 AI 在发起入侵波次时，即便诱发活跃的玩家单位就在眼前，其逻辑也会强制锁定玩家阵营的 `home_entity`（主基地）。若主基地远在数千格之外，大量单位会开启全图寻路，导致极高的路径计算开销和服务器 UPS 剧烈抖动。
*   **优化**：引入 250 格距离截断机制。若目标主基地超出范围，则自动切换至“就近打击”模式，攻击触发其活跃的周边目标。同时，确保侦察虫不受此限制，以维持正常的战略扩张。

### 2. 目标合法性筛选缺失导致性能崩溃 (Target Validity Issue)
*   **诊断**：原版 AI 未对目标状态进行校验，常锁定“建筑蓝图”、“矿点”或“中立遗迹”作为主攻目标。由于这些实体无法被摧毁，导致大量单位在目标点堆积且不进入攻击循环，造成无意义的性能开销。
*   **优化**：本模组引入了底层筛选，确保入侵目标必须是已部署且可被破坏的玩家实体。

### 3. 全局决策锁导致的反应滞后 (Global CD Bottleneck)
*   **诊断**：原版将“派遣侦察”、“发起进攻”与“自然扩张”强行共用一个全局冷却计时器。在大型地图下，不同行为之间产生严重的互斥竞争。
*   **优化**：解耦派遣、进攻、扩张的全局锁。实现三路独立限速，显著提升了虫群的并行决策效率。

---

## English Version

### 1. Performance Black-hole via Long-Distance Pathing
*   **Diagnosis**: Vanilla AI forces incursion waves to target the player faction's `home_entity`, even if the assets triggering the hive's aggression are thousands of grids away. This results in hundreds of units attempting cross-map pathfinding, causing severe server-side stuttering.
*   **Optimization**: Implemented a 250-grid truncation. If the home base is out of range, units fallback to "Nearby Attack" mode against the triggering units. Scouts are excluded from this limit to preserve strategic expansion depth.

### 2. Lack of Target Validity Filtering
*   **Diagnosis**: Vanilla AI often targets "Blueprints", "Explorables", or "Resources". Since these cannot be destroyed, units pile up indefinitely, crashing performance.
*   **Fix**: Introduced logic-level filtering to ensure swarms only target deployed and destructible entities.

### 3. Shared Global Cooldown Bottleneck
*   **Diagnosis**: A single shared cooldown for all swarm behaviors causes tactical responsiveness to plummet in multiplayer.
*   **Optimization**: Decoupled cooling timers for scouting, attacking, and expansion, allowing independent and parallel decision-making across all hives.
