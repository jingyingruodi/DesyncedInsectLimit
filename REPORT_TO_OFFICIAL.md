# 关于《Desynced》虫群 AI 机制诊断与多人环境优化建议 (v2.8.7)
# Swarm AI System Diagnostics & Multiplayer Enhancement Report

---

## 中文版 (Chinese Version)

## 前言

首先需要说明，《Desynced》原版虫群 AI 并非完全停滞不前。随着版本更新，原版已经修复或缓解了部分早期问题，整体表现较早期版本已有明显改善。

本报告针对当前版本仍然存在、且在多人服务器或长期存档环境中更容易被放大的机制性问题进行分析，并给出 v2.8.7 模组所采用的优化方案。

本模组的目标不是削弱虫群，而是在尽量保留原版虫群生态、压迫感与进攻节奏的前提下，补足多人环境设计缺口，并提升后期稳定性与运行质量。

---

## 1. 当前版本仍存在的异常聚怪目标问题
### (Remaining Invalid Target Clustering Issue)

### 诊断：

相较早期版本，原版目标筛选已有进步，当前版本大多数明显异常目标已不会被虫群持续锁定。

但仍存在一个典型问题：

- **建筑蓝图（Construction Blueprint）**

蓝图目标处于未完成施工状态，通常无法正常被摧毁或无法有效完成攻击流程。虫群大量单位若锁定此类目标，仍可能出现：

- 长时间聚集堵塞
- 攻击循环异常
- 局部路径拥堵
- 无意义单位堆积

### 优化：

v2.8.7 增加合法目标过滤，仅允许以下对象进入攻击目标池：

- 玩家有效资产
- 非隐形目标
- 非无敌目标
- 非施工状态对象

从根源避免蓝图类目标继续诱发异常聚怪。

---

## 2. 原版全局冷却机制缺乏多人设计适配
### (Vanilla Shared Global Cooldown Lacks Multiplayer Awareness)

### 诊断：

原版虫群高层行为（如进攻、侦察等）主要依赖共享型全局冷却机制。

在单人环境中问题不明显，但在多人环境下会产生天然缺陷：

- 玩家 A 被攻击后，占用了全局攻击窗口
- 玩家 B 即使满足条件，也可能长期不会被袭击
- 某玩家频繁成为目标
- 某玩家长期处于安全状态

本质原因是：

> 原版冷却系统按“虫群整体”设计，而不是按“多玩家目标分配”设计。

### 优化：

v2.8.7 将虫群进攻与侦察行为改为：

### 每个玩家势力独立拥有：

- 攻击全局冷却记录
- 侦察全局冷却记录

即：

- A 玩家刚被袭击，不影响 B 玩家进入候选队列
- B 玩家进入冷却，不影响 C 玩家被侦察
- 多人环境攻击机会更加均衡

这使虫群行为从“单目标全局轮转”，升级为“多目标并行调度”。

---

## 3. 多人服务器中的虫群长期停摆问题
### (Long-Term Swarm Inactivity in Multiplayer)

### 诊断：

多人服务器中虫群长期停摆的主要诱因，通常并非单纯的冷却逻辑，而是原版 AI 在异常情况下容易出现大量单位聚集卡死、持续寻路失败或围堵无效目标等现象。

这些失控单位会快速堆积，使虫群总数量提前触及全局单位上限。一旦达到上限，新波次生成、侦察派遣与自然扩张都会被抑制，最终表现为：

- 长时间不主动进攻
- 很少侦察扩张
- 世界仍有虫群存在，但行为极度消极
- 后期地图生态停滞

### 优化：

v2.8.7 通过多层机制解决该问题：

- 合法目标筛选，减少围攻无效目标导致的堆积
- 250 格攻击截断，降低超远距离寻路堵塞
- 卡死单位自愈与归巢回收逻辑
- 动态软上限（Soft Limit）机制，在接近上限时自动削减波次规模，而非瞬间停摆

使虫群在高负载多人环境下更容易维持持续活动，而不是因单位塞满后整体冻结。

---

## 4. 进攻距离截断与跨图寻路优化
### (Attack Range Cutoff & Cross-Map Pathing Fix)

### 诊断：

当玩家单位靠近虫巢唤醒进攻行为时，原版会锁定远处主基地，导致过远距离的跨图进攻。

多人地图中该问题更明显：

- 距离更远
- 路线更复杂
- 路径计算量更高

### 优化：

引入 **250 格攻击截断机制**：

- 250 格内正常进攻主基地
- 超出后转为攻击附近活跃玩家单位

侦察虫仍可跨远距离移动，以保留战略扩张功能。

---

## 5. 动态单位上限与服务器稳定性保护
### (Dynamic Population Caps)

### 诊断：

多人环境下虫群单位数量可能快速膨胀，原版缺乏足够的长期人口调控机制。

表现为：

- 波次过大
- 路径压力升高
- CPU 持续增长
- 后期性能下降

### 优化：

v2.8.7 引入三层动态控制：

- **削弱阈值（Soft Limit）**：波次规模开始缩减
- **侦察阈值（Scout Limit）**：暂停侦察新增
- **绝对上限（Absolute Limit）**：暂停大型虫巢出兵

并随玩家数量自动增长。

---

## 6. 异常单位自愈与长期运行保护
### (Self-Recovery for Broken Units)

### 优化：

针对长期卡住单位：

- 长期寻路失败自动重置
- 无法恢复单位自动回收
- 战后自动归巢整理

适合长期运行服务器存档。

---

## 7. 总结
### (Summary)

v2.8.7 的重点并非单纯增强虫群数量，而是补足原版在多人游戏设计上的天然缺口：

- 共享 CD 导致的目标分配问题
- 单位远离基地下虫群产生远距离寻路问题
- 聚怪卡死导致单位上限停摆问题
- 长期服务器存档性能衰减问题

最终实现：

- 更公平的多人袭击分布
- 更稳定的后期表现
- 更持续的虫群活跃度
- 更符合多人服务器生态的 AI 行为系统

---

---

## English Version

## Preface

First, it should be stated that the vanilla Swarm AI in *Desynced* has not remained completely stagnant.  
With ongoing updates, the developers have already fixed or mitigated several early issues, and the overall behavior is noticeably improved compared to older versions.

This report focuses on systemic issues that still remain in the current version, especially those that become more apparent in multiplayer servers or long-running save files, and presents the optimization solutions adopted in the v2.8.7 mod.

The goal of this mod is **not** to weaken the Swarm, but to preserve its original ecosystem, pressure, and attack pacing as much as possible, while filling multiplayer design gaps and improving late-game stability and runtime quality.

---

## 1. Remaining Invalid Target Clustering Issue

### Diagnosis:

Compared to earlier versions, vanilla target filtering has improved. Most obviously invalid targets are no longer continuously prioritized by the Swarm.

However, one typical issue still remains:

- **Construction Blueprints**

Blueprint targets are unfinished construction objects that usually cannot be properly destroyed or cannot complete a valid combat cycle.

When large numbers of Swarm units lock onto such targets, the following may still occur:

- Long-term clustering and blockage
- Broken attack loops
- Local path congestion
- Meaningless unit pileups

### Optimization:

v2.8.7 adds legal target filtering and only allows the following objects into the attack target pool:

- Valid player-owned assets
- Non-stealthed targets
- Non-immortal targets
- Non-construction-state objects

This prevents blueprint-type targets from continuing to trigger abnormal clustering behavior at the source.

---

## 2. Vanilla Shared Global Cooldown Lacks Multiplayer Awareness

### Diagnosis:

Vanilla high-level Swarm behaviors (such as attacks and scouting) mainly rely on a shared global cooldown system.

In single-player this is less noticeable, but in multiplayer it creates inherent flaws:

- After Player A is attacked, the global attack window is consumed
- Player B may remain untouched for a long time even if conditions are met
- Certain players are targeted too frequently
- Certain players remain safe for extended periods

The root cause is:

> The vanilla cooldown system was designed around the Swarm as one whole faction, not around multi-player target distribution.

### Optimization:

v2.8.7 changes Swarm attack and scouting logic so that:

### Each player faction independently owns:

- Attack cooldown records
- Scout cooldown records

Meaning:

- If Player A was just attacked, Player B can still enter the candidate queue
- If Player B is on cooldown, Player C can still be scouted
- Attack opportunities become significantly more balanced in multiplayer

This upgrades Swarm behavior from **single-target global rotation** into **multi-target parallel scheduling**.

---

## 3. Long-Term Swarm Inactivity in Multiplayer

### Diagnosis:

On multiplayer servers, long-term Swarm inactivity is usually not caused by cooldown logic alone.

The more common reason is that vanilla AI can enter abnormal states where large numbers of units become clustered, path repeatedly fails, or units endlessly surround invalid targets.

These broken units quickly accumulate and cause the Swarm population to prematurely hit the global unit cap.

Once the cap is reached, new attack waves, scouting deployments, and natural expansion become suppressed, resulting in:

- Long periods without offensive actions
- Rare scouting or expansion
- Swarm still exists in the world, but behaves passively
- Late-game ecosystem stagnation

### Optimization:

v2.8.7 addresses this through multiple systems:

- Legal target filtering to reduce pileups on invalid targets
- 250-range attack cutoff to reduce extreme long-distance path blockage
- Self-recovery and return-home logic for stuck units
- Dynamic Soft Limit system that gradually reduces wave size near cap instead of hard-freezing activity

This allows the Swarm to remain active under heavy multiplayer load instead of freezing after population saturation.

---

## 4. Attack Range Cutoff & Cross-Map Pathing Fix

### Diagnosis:

When player units approach a hive and trigger aggression, vanilla logic may target a faraway home base, causing extreme cross-map assaults.

This issue becomes worse on multiplayer maps:

- Longer distances
- More complex routes
- Higher pathfinding workload

### Optimization:

Introduced a **250-range attack cutoff system**:

- Within 250 range: normal attacks on the home base
- Beyond 250 range: switch to nearby active player targets instead

Scout units are still allowed to travel long distances to preserve strategic expansion behavior.

---

## 5. Dynamic Population Caps & Server Stability Protection

### Diagnosis:

In multiplayer, Swarm population can grow rapidly, while vanilla lacks sufficient long-term population regulation.

Typical results:

- Oversized attack waves
- Increased pathfinding pressure
- Sustained CPU load growth
- Late-game performance decline

### Optimization:

v2.8.7 introduces three layers of dynamic control:

- **Soft Limit**: attack wave sizes begin to scale down
- **Scout Limit**: new scout deployments are paused
- **Absolute Limit**: large hives stop spawning attack forces

All limits automatically scale with player count.

---

## 6. Broken Unit Self-Recovery & Long-Term Runtime Protection

### Optimization:

For units stuck over long periods:

- Repeated pathing failure triggers reset logic
- Unrecoverable units are recycled automatically
- Post-combat units return home automatically

Well suited for persistent long-running server saves.

---

## 7. Summary

The focus of v2.8.7 is not simply increasing Swarm numbers, but filling natural design gaps in vanilla multiplayer gameplay:

- Shared cooldown target distribution issues
- Long-distance pathing caused by remote player bases
- Population-cap paralysis caused by clustered stuck units
- Performance degradation in long-running servers

Final results:

- Fairer multiplayer attack distribution
- More stable late-game behavior
- More persistent Swarm activity
- An AI system better suited for multiplayer server ecosystems