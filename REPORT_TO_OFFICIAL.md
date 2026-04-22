# 关于《Desynced》原版虫群 AI 逻辑缺陷及修复建议报告 (v2.7.15)
# Report on Swarm AI Defects and Enhancements in Desynced

---

## 中文版 (Chinese Version)

### 1. 目标合法性检查缺失 (Target Validity Issue)
*   **缺陷**：原版 AI 会锁定“建筑蓝图”、“可探索项”或“资源点”作为主攻目标。由于这些实体无法被摧毁，导致虫群在目标点堆积且不进入攻击循环，造成无意义的性能开销。
*   **修复**：引入了严格筛选机制，确保虫群仅针对已部署且非隐身的合法玩家实体发起入侵。

### 2. 精准战斗判定与卡死处理 (Precise Combat Detection)
*   **缺陷**：原版虫群在路经受阻或残血脱战后容易进入永久“发呆”状态。
*   **修复**：本模组重构了 `on_update` 判定。只有当单位真正进行射击，或者本周期内血量确实减少时，才重置卡死计时。这确保了真正处于战斗中的单位不会被误判，而卡死或发呆的单位能及时解脱归巢。

### 3. 全局行为限速解耦 (Behavioral Decoupling)
*   **缺陷**：原版（及本模组旧版）将侦察虫派遣、进攻波次、自然扩张共用同一个 `last_swarm` 全局冷却。这导致在大规模地图或多玩家环境下，虫群反应极度迟钝。
*   **修复**：将三种核心行为的 Cooldown 完全分离（`last_attack` / `last_scout` / `last_nest`）。不同蜂巢可以同时执行不同任务，显著提升了 AI 的并行决策能力。

### 4. 统计口径与生态位优化 (Census Philosophy)
*   **缺陷**：原版计算上限时包含虫穴。导致虫穴越多，刷怪量越少。
*   **修复**：上限仅计算非建筑的活跃战斗单位，确保无论虫群扩张到何种规模，始终能保持稳定的进攻烈度。

---

## English Version

### 1. Lack of Target Validity Filtering
*   **Issue**: Vanilla AI targets "Blueprints", "Explorables", or "Resources". Since these cannot be destroyed by weapons, units pile up indefinitely, causing performance degradation.
*   **Fix**: Introduced a strict filtering mechanism to ensure the swarm only targets deployed, visible, and valid player entities.

### 2. Precise Combat Detection & Stuck-Recovery
*   **Issue**: Units often enter a permanent "idle" state after combat or when pathing is blocked.
*   **Fix**: Refactored the update logic. Stuck timers are only reset if a unit is actively firing or taking damage. This prevents active units from being misidentified as stuck while ensuring truly idle units return to hives or self-destruct to free up population slots.

### 3. Global Behavioral Decoupling
*   **Issue**: Sharing a single `last_swarm` timer for scouting, attacking, and expanding causes the swarm to be unresponsive in large-scale or multiplayer sessions.
*   **Fix**: Decoupled the three core behaviors with independent global cooldowns (`last_attack`, `last_scout`, `last_nest`). This allows simultaneous activities across different hives, greatly enhancing the swarm's tactical flexibility.

### 4. Census Philosophy & Ecological Displacement
*   **Issue**: Vanilla logic includes hives in the population count, meaning more expansion leads to fewer combat units.
*   **Fix**: The population limit now only applies to active non-structure units, ensuring consistent offensive pressure regardless of the swarm's geographical footprint.
