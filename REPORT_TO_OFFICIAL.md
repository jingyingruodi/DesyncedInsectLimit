# 关于《Desynced》原版虫群 AI 逻辑缺陷及修复建议报告
# Report on Original Swarm AI Defects and Fixes in Desynced

---

## 中文版 (Chinese Version)

### 1. 目标合法性检查缺失 (Target Validity Issue)
*   **缺陷**：原版 AI 在发起进攻时未对目标实体进行状态校验。它会错误地锁定“建筑蓝图 (Constructions)”、“可探索项 (Explorables)”或“掉落物 (Dropped Items)”作为主攻目标。由于这些实体无法被常规武器“消灭”，导致大量虫群单位在目标点堆积且不进入攻击循环，造成无意义的性能开销。
*   **修复**：本模组引入了严格筛选机制，确保虫群仅针对已部署且非隐身的合法玩家实体发起入侵。

### 2. 隐身基地逃避判定 (Stealth Home Base Exploit)
*   **缺陷**：原版逻辑强制锁定玩家阵营的 `home_entity`。若玩家将主基地隐身，虫群逻辑会因为目标“不可见”而导致整个阵营的入侵 AI 失效，即便周边有大量暴露的采集站或机器人。
*   **修复**：重构逻辑后，当主基地隐身或不合法时，虫群会自动切换至“就近打击”模式，寻找附近可见的合法目标。

### 3. “千里奔袭”Bug (Long-Distance Trek Bug)
*   **缺陷**：当蜂巢 250 格内出现任何玩家单位时会激活进攻，但目标会被硬性设定为玩家主基地。若主基地远在地图另一端，虫群会发起跨越全图的长途跋涉，导致严重的路径查找开销且进攻效率极低。
*   **修复**：引入了 **250 格距离截断机制**。若目标基地超出此范围，虫子将直接转为打击诱发其活跃的周边单位，拒绝无效的远距离行军。

### 4. 统计口径导致的生态位挤占 (Census Philosophy Issue)
*   **缺陷**：原版逻辑在计算单位上限时，采用的是全量统计（虫穴 + 战斗单位）。这导致了一个逻辑悖论：建立的虫穴越多，剩余刷怪配额就越少。在大后期，密集的巢穴会挤占所有生成空间，导致虫群空有规模却无进攻力。
*   **修复**：本模组上限**仅计算非建筑的活跃单位**。虫穴不应占用战斗配额，确保了无论虫群扩张到何种规模，始终能保持稳定的进攻烈度。

---

## English Version

### 1. Lack of Target Validity Filtering
*   **Issue**: The vanilla AI fails to validate target entities before initiating an invasion. It often targets "Constructions (Blueprints)", "Explorables", or "Dropped Items". Since these cannot be "destroyed" by weapons, units pile up indefinitely at the location without entering combat cycles, causing significant performance degradation.
*   **Fix**: Introduced a strict filtering mechanism to ensure the swarm only targets deployed, visible, and valid player entities.

### 2. Stealth Home Base Exploit
*   **Issue**: Vanilla logic hard-locks the player faction's `home_entity` as the primary target. If a player cloaks their base, the entire faction’s invasion AI effectively stalls, even if other units or bots are fully exposed nearby.
*   **Fix**: Refactored the logic to fallback into "Nearby Attack" mode if the home base is cloaked or invalid, targeting the nearest visible player assets within 250 grids.

### 3. The "Long-Distance Trek" Bug
*   **Issue**: Incursions are triggered when a player unit enters a 250-grid radius of a hive, but the AI hard-codes the target to the player's home base. If the base is far away, the swarm embarks on a map-wide march, leading to massive pathfinding overhead and zero tactical efficiency.
*   **Fix**: Implemented a **250-grid distance truncation**. If the target base exceeds this range, the swarm immediately re-targets nearby assets that initially triggered the aggression.

### 4. Census Philosophy & Ecological Displacement
*   **Issue**: Vanilla logic calculates the population limit using a "Total Assets" approach (Hives + Units). The more the swarm expands and builds hives, the less "quota" remains for spawning actual combat units. In late-game, dense hive clusters effectively choke out the spawn rate.
*   **Fix**: The population limit in this mod **only applies to non-structure, active units**. Hives should not consume combat unit quotas, ensuring consistent offensive pressure regardless of the swarm's geographical footprint.
