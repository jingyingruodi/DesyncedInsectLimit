-- InsectLimit Mod - Performance & Faithful Expansion Logic
-- Version: 2.5.4 (Stable Base - Fully Annotated)
-- Author: 镜影若滴

local package = ...

function package:init()
	print("[InsectLimit] Initializing v2.5.4 - Base Stability Version...")

	-- Get references to vanilla bug components
	-- 获取原版虫群核心组件引用
	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	-- Safety check for component existence
	-- 确保核心组件存在，防止游戏更新导致组件丢失引起的崩溃
	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] CRITICAL ERROR: Bug components missing!")
		return
	end

	---------------------------------------------------------------------------
	-- 1. 全局普查系统 (Diagnostic Heartbeat)
	-- Frequency: Every 30 seconds (150 ticks)
	-- Purpose: Count active units and clean up infected units with low health.
	-- 功能：每30秒执行一次，统计活跃单位数，并处决低血量的病毒感染单位（性能优化）。
	---------------------------------------------------------------------------
	function Delay.DiagnosticHeartbeat(arg)
		local bugs = GetBugsFaction()
		if not bugs then return end

		local ents = bugs.entities
		local total = #ents
		local bot_count = 0
		local perish_count = 0

		for i = 1, total do
			local e = ents[i]
			if e and e.exists then
				-- Count only units with movement (exclude buildings/hives)
				-- 仅统计具有移动能力的活跃单位（排除虫穴和建筑）
				if e.has_movement and not e.is_construction then
					bot_count = bot_count + 1

					-- [Virus Execution] Based on max_health logic
					-- [病毒处决] 针对特定状态且最大血量较低的单位进行清理
					if e.state_custom_1 and e.max_health <= 80 then
						e:Destroy(false)
						perish_count = perish_count + 1
					end
				end
			end
		end

		-- Store census results in extra_data for O(1) access by spawners
		-- 将普查结果存入 extra_data，供生成器以 O(1) 开销调用
		bugs.extra_data.unit_count = bot_count
		bugs.extra_data.asset_count = total

		-- Census Console Broadcast (Important for server monitoring)
		-- 普查后台播报（对服务器监控至关重要）
		print(string.format("[InsectLimit] Heartbeat -> REAL BOTS: %d | Total Assets: %d | Virus Perished: %d", bot_count, total, perish_count))

		Map.Delay("DiagnosticHeartbeat", 150)
	end

	---------------------------------------------------------------------------
	-- 2. 辅助判定逻辑 (Helper Functions)
	---------------------------------------------------------------------------

	-- Checks if the current season allows bug aggression
	-- 检查当前季节是否允许虫群活跃（通常为夏季/特定光照周期）
	local function IsBugActiveSeason()
		return math.abs(Map.GetYearSeason() - 0.5) < 0.25
	end

	-- 【核心修复】：目标合法性筛选 (Target Validity Filter)
	-- Prevents bugs from targeting invulnerable or non-player entities.
	-- 核心逻辑：防止虫群锁定无敌物体、蓝图或非玩家所属的遗迹。
	local function IsAttackable(e)
		if not e or not e.exists then return false end

		-- Resolve target entity (handle docked units)
		-- 解析目标实体（处理停靠在车库内的单位）
		local target = e.is_placed and e or e.docked_garage
		if not target or not target.is_placed or e.id == "f_empty" then return false end

		local def = target.def
		if target.stealth then return false end -- Skip cloaked units (尊重隐身玩法)
		if target.is_construction then return false end -- Skip blueprints (忽略蓝图)
		if def.immortal then return false end -- Skip immortal entities (忽略无敌物体)

		-- [v2.5.4 Aligned]: Only attack player-owned explorables.
		-- 适配官方逻辑：仅当探索项属于玩家时才发起攻击，防止在中立遗迹堆积。
		if def.is_explorable and not target.faction.is_player_controlled then
			return false
		end

		-- Filter out mission items, drops and resources
		-- 过滤任务目标、掉落物和资源矿点
		if def.size == "Mission" then return false end
		if def.type == "DroppedItem" then return false end
		if def.type == "Resource" then return false end

		return true
	end

	---------------------------------------------------------------------------
	-- 3. 通用行为逻辑 (Combat & Stuck Handling)
	-- Shared logic for bug attack components.
	-- 功能：处理攻击组件的通用逻辑，包括卡死判定和“无家可归”状态转换。
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data

			-- [Virus Death Mark] Immediate shutdown for units marked for death.
			-- [病毒死亡标记] 对标记处决的单位进行停机处理。
			if owner.state_custom_1 and owner.max_health <= 80 and not IsFlyingUnit(owner) then
				if not ed.virus_marked_for_death then
					ed.virus_marked_for_death = true
					owner:Cancel()
					owner.powered_down = true
					if owner.is_placed then owner:PlayEffect("fx_glitch2") end
					Map.Delay("BugForcePerish", 150, { entity = owner })
				end
				return true
			end

			-- [Stuck Detection] Triggered by path blocking or infection.
			-- [卡死检测] 检测到路径阻断或特定状态。
			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			if is_stuck then
				if not ed.failed_move_ticks then
					ed.failed_move_ticks = Map.GetTick() + 600 -- 120s threshold
				elseif ed.failed_move_ticks < Map.GetTick() then
					-- Threshold reached: Switch to "Homeless" logic to find a new hive.
					-- 最终超时：停止攻击，转化为“寻家”状态（归巢逻辑）。
					ed.failed_move_ticks = nil
					if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
					if not owner:FindComponent("c_bug_homeless") then
						Map.Defer(function()
							if comp.exists then
								local new_homeless = (owner.health > 200) and owner:AddComponent("c_bug_homeless")
								if new_homeless then new_homeless:Activate() else owner:Destroy() end
							end
						end)
					end
					return
				end
			else
				-- Reset stuck timer if unit starts moving again
				-- 如果单位恢复移动，重置卡死计时器
				if not owner.state_path_blocked and owner.is_moving then ed.failed_move_ticks = nil end
			end
		end
		-- Fallback to vanilla turret update logic
		-- 返回执行原版炮塔更新逻辑
		return data.components.c_turret.on_update(self, comp, cause)
	end

	function Delay.BugForcePerish(arg)
		local e = arg.entity
		if e and e.exists then
			if e.is_placed then e:PlayEffect("fx_digital") end
			e:Destroy(false)
		end
	end

	---------------------------------------------------------------------------
	-- 4. 蜂巢生产与入侵截断 (Hive Production & Distance Truncation)
	-- Handles unit spawning limit and initiates attacks based on proximity.
	-- 功能：处理虫群单位上限，并基于 250 格距离判定发起入侵攻击。
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_faction = GetBugsFaction()
		local ed = bugs_faction.extra_data

		-- Start heartbeat if not already running
		-- 若普查心跳未启动，则执行初始化
		if not ed.heartbeat_started then
			ed.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		-- Population Limit: Count only active bots, not all assets (Faithful Expansion).
		-- 数量限制：仅基于活跃单位统计而非全资产（防止虫穴过多挤占刷怪配额）。
		local unit_count = ed.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
		local settings = Map.GetSettings()

		-- Global unit hard-cap
		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000) end

		-- Global invasion cooldown
		local last_swarm = Map.GetSave().last_swarm or 0
		if Map.GetTick() - last_swarm < 750 then return comp:SetStateSleep(100) end

		-- Target Search Loop
		-- 搜索最近的目标阵营和单位
		local closest_distance, closest_faction, towards = 9999999, nil, nil
		for _, faction in ipairs(Map.GetFactions()) do
			if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
				local entities = faction.entities
				local test_unit, tries = nil, 0
				-- Randomly sample 15 entities to find a valid attackable target
				-- 随机采样15个实体以寻找合法的可攻击目标
				while tries < 15 do
					local ent = entities[math.random(1, #entities)]
					if ent and ent.exists then
						if IsAttackable(ent) then test_unit = ent break end
					end
					tries = tries + 1
				end
				if test_unit then
					local d = comp.owner:GetRangeTo(test_unit)
					-- 250 Grid Cut-off: Ignore targets beyond this distance.
					-- 250格截断：忽略超出此范围的目标，减少全图寻路开销。
					if d < 250 and d < closest_distance then closest_distance, closest_faction, towards = d, faction, test_unit end
				end
			end
		end

		if closest_faction then
			local difficulty = settings.difficulty or 1.0

			-- [Scout Logic] Spawn a scout if unit count is low and target is far.
			-- [侦察逻辑] 若单位数较少且目标较远，生成侦察虫进行扩张。
			if (unit_count < (10000 * pc * difficulty)) and (closest_distance > 150) then
				if math.random() > 0.6 then
					Map.Defer(function() if not comp.owner.exists then return end
						local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
						scout:Place(comp.owner)
						local harvest_comp = scout:FindComponent("c_bug_harvest")
						if harvest_comp then
							harvest_comp.extra_data.home = comp.owner
							if towards and towards.exists then harvest_comp.extra_data.towards = Tool.Copy(towards.location) end
						end
					end)
				end
				return comp:SetStateSleep(math.random(4000, 8000))

			-- [Invasion Trigger] Initiate swarm attack.
			-- [入侵触发] 在特定条件下（激进模式或近距离）发起大规模进攻。
			elseif (settings.peaceful == 3 or closest_distance <= 60) and closest_distance < 250 then
				if not IsBugActiveSeason() and math.random() > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end

				-- Smart Target Selection: Prefer home_entity if valid, fallback to trigger unit.
				-- 智能目标选择：若主基地合法且在250格内则选为主目标，否则攻击诱发单位。
				local attack_target = closest_faction.home_entity
				if not IsAttackable(attack_target) or comp.owner:GetRangeTo(attack_target) > 250 then
					attack_target = towards
				end

				if attack_target and attack_target.exists then
					Map.GetSave().last_swarm = Map.GetTick()
					Map.Defer(function() if comp.exists and attack_target.exists then
						data.components.c_bug_spawn:on_trigger_action(comp, attack_target, true)
					end end)
				end
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	---------------------------------------------------------------------------
	-- 5. 侦察 AI (Scout AI Logic)
	-- Controls silica harvesting and new hive deployment.
	-- 功能：控制侦察虫采集硅石并寻找合适地点部署新虫穴。
	---------------------------------------------------------------------------
	c_bug_harvest.on_update = function(self, comp, cause)
		local owner, data = comp.owner, comp.extra_data
		local target, home = data.target, data.home

		-- Scout perishes if home hive is lost
		-- 归巢点丢失则侦察虫销毁
		if not home or not home.exists then
			Map.Defer(function() if owner.exists then owner:Destroy() end end)
			return comp:SetStateSleep(1)
		end

		if target and not target.exists then
			data.state, data.target = "wander", nil
			return comp:SetStateSleep(1)
		end
		if owner.is_moving then return comp:SetStateSleep(20 + math.random(1, 10)) end

		local state = data.state or "idle"
		if state == "idle" then
			-- Search for Silica resource far from home hive
			-- 搜索远离当前蜂巢的硅石资源
			target = Map.FindClosestEntity(owner, 8, function(e)
				if IsResource(e) and GetResourceHarvestItemId(e) == "silica" and e:GetRangeTo(home) > 20 then return true end
				return false
			end, FF_RESOURCE)

			if target then
				data.target, data.state = target, "deploy"
			else
				-- Starve and perish if silica is not found after 50 wander attempts
				-- 50次游荡后未找到资源则判定为“饥饿”销毁
				data.state, data.wandertimes = "wander", (data.wandertimes or 0) + 1
				if data.wandertimes > 50 then Map.Defer(function() if owner.exists then owner:Destroy() end end) return comp:SetStateSleep(1) end
			end
		elseif state == "deploy" then
			-- Move to target silica and check for local hive density
			-- 移动至目标地点并检查周围30格内的蜂巢密度
			if not owner.state_path_blocked then
				if comp:RequestStateMove(target, 3) then return end
			end
			data.target = nil

			local hive_count = 0
			Map.FindClosestEntity(owner, 30, function(e)
				if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then
					hive_count = hive_count + 1
					if hive_count >= 2 then return true end
				end
			end, FF_OPERATING | FF_OWNFACTION)

			-- Prevent overcrowding: Only deploy if fewer than 2 hives are nearby
			-- 密度控制：仅当周围蜂巢少于2个时才部署新蜂巢
			if hive_count >= 2 then
				data.state = "wander"
				return comp:SetStateSleep(200 + math.random(1, 50))
			end

			Map.Defer(function()
				if comp.exists then
					-- Deploy new hive and consume scout
					local newhome = Map.CreateEntity(GetBugsFaction(), (math.random() > 0.8) and "f_bug_hive" or "f_bug_hive_large")
					newhome:Place(owner.location)
					owner:Destroy()
				end
			end)
			return comp:SetStateSleep(10 + math.random(1, 10))
		elseif state == "wander" then
			-- Random movement or directed wander towards a known target
			-- 随机移动或朝已知敌方方向移动以探测
			local loc = Tool.Copy(owner.location)
			if data.towards and (data.towards.x ~= 0 or data.towards.y ~= 0) then
				local tloc = data.towards
				local dx = math.min(math.max((tloc.x - loc.x) // 3, -50), 50)
				local dy = math.min(math.max((tloc.y - loc.y) // 3, -50), 50)
				loc.x, loc.y = loc.x + dx + math.random(-5, 5), loc.y + dy + math.random(-5, 5)
			else
				loc.x, loc.y = loc.x + math.random(-15, 15), loc.y + math.random(-15, 15)
			end
			data.state = "idle"
			return comp:RequestStateMove(loc, 1)
		end
	end

	-- Apply hooks to all bug attack variants
	-- 应用挂钩至所有虫群攻击变体
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.5.4: Fully Annotated Stable Version Deployed.")
end
