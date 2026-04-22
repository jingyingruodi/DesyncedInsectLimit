-- InsectLimit Mod - Performance & Intelligent Combat Fixes
-- Version: 2.6.9 (Complete Vanilla Pacing Fidelity)
-- Author: 镜影若滴

local package = ...

---------------------------------------------------------------------------
-- 0. 文件级辅助函数 (File-Level Helpers)
---------------------------------------------------------------------------

-- 检查当前季节是否允许虫群活跃
local function IsBugActiveSeason()
	return math.abs(Map.GetYearSeason() - 0.5) < 0.25
end

-- 目标合法性筛选器
local function IsAttackable(e)
	if not e or not e.exists then return false end
	local target = e.is_placed and e or e.docked_garage
	if not target or not target.is_placed or e.id == "f_empty" then return false end

	local def = target.def
	if target.stealth or target.is_construction or def.immortal then return false end

	-- 仅攻击属于玩家的探索项
	if def.is_explorable and not target.faction.is_player_controlled then
		return false
	end

	if def.size == "Mission" or def.type == "DroppedItem" or def.type == "Resource" then return false end
	return true
end

---------------------------------------------------------------------------
-- 1. 全局普查系统 (Diagnostic Heartbeat)
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
			-- 仅统计移动战斗单位
			if e.has_movement and not e.is_construction then
				bot_count = bot_count + 1
				-- 自动清理无效感染单位
				if e.state_custom_1 and e.max_health <= 80 then
					e:Destroy(false)
					perish_count = perish_count + 1
				end
			end
		end
	end

	-- 缓存数据
	bugs.extra_data.unit_count = bot_count
	bugs.extra_data.asset_count = total

	-- 动态上限参数
	local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
	local abs_limit = 12000 + (pc - 1) * 3000
	local soft_limit = 4000 + (pc - 1) * 1500
	local scout_limit = 6000 + (pc - 1) * 2000

	-- 播报
	print(string.format("[InsectLimit] Heartbeat -> BOTS: %d/%d (Soft: %d, Scout: %d) | Assets: %d | Virus Perished: %d",
		bot_count, abs_limit, soft_limit, scout_limit, total, perish_count))

	Map.Delay("DiagnosticHeartbeat", 150)
end

function package:init()
	print("[InsectLimit] Initializing v2.6.9 - Total Vanilla Pacing Fidelity Deployed...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] CRITICAL ERROR: Bug components missing!")
		return
	end

	---------------------------------------------------------------------------
	-- 2. 进攻组件 Hook (侦察虫生命周期)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data

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

			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			if is_stuck then
				if not ed.failed_move_ticks then
					ed.failed_move_ticks = Map.GetTick() + 600
				elseif ed.failed_move_ticks < Map.GetTick() then
					local stuck_ticks = 600 - (ed.failed_move_ticks - Map.GetTick())
					-- 侦察虫卡死处决
					if owner:FindComponent("c_bug_harvest") then
						if stuck_ticks >= 300 then owner:Destroy(false) return else return true end
					end

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
				if not owner.state_path_blocked and owner.is_moving then ed.failed_move_ticks = nil end
			end
		end
		return data.components.c_turret.on_update(self, comp, cause)
	end

	---------------------------------------------------------------------------
	-- 3. 大型蜂巢核心逻辑 (严格遵循原版限速机制)
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		-- 【核心限速 A】：全局冷静期 (Global Silence)
		-- 严格对齐原版 750 ticks 的全图公共 CD
		local last_swarm = Map.GetSave().last_swarm or 0
		local time_since_swarm = Map.GetTick() - last_swarm
		if time_since_swarm < 750 then
			return comp:SetStateSleep(750 - time_since_swarm + 1)
		end

		local bugs_faction = GetBugsFaction()
		local ed_faction = bugs_faction.extra_data

		if not ed_faction.heartbeat_started then
			ed_faction.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		-- 获取动态上限 (统统按照战斗单位算)
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
		local abs_limit = 12000 + (pc - 1) * 3000
		local scout_limit = 6000 + (pc - 1) * 2000
		local unit_count = ed_faction.unit_count or 0

		-- 兵力饱和判定
		if unit_count > abs_limit then return comp:SetStateSleep(5000) end

		-- 【核心限速 B】：个体预热计数器 (Individual Warm-up)
		-- 每个蜂巢必须独立完成 10 次成功心跳
		local ed_hive = comp.extra_data
		if not ed_hive.extra_spawned then ed_hive.extra_spawned = 0 end
		ed_hive.extra_spawned = ed_hive.extra_spawned + 1

		if ed_hive.extra_spawned > 10 then
			local rnd = math.random()

			--行为分支 1：自我扩张（建立新的近程虫穴）
			if rnd < 0.2 then
				local hive_count = 0
				Map.FindClosestEntity(comp.owner, 10, function(e)
					if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then hive_count = hive_count + 1 end
				end, FF_OPERATING | FF_OWNFACTION)

				if hive_count < 5 then
					Map.Defer(function()
						if comp.exists then
							local newhome = Map.CreateEntity(bugs_faction, "f_bug_hive")
							newhome:Place(comp.owner.location)
							ed_hive.extra_spawned = 0
						end
					end)
				end

			-- 行为分支 2：远距离派遣或局部进攻
			elseif rnd > 0.3 then
				-- 目标搜索
				local closest_dist_any, closest_dist_250 = 9999999, 9999999
				local towards_any, towards_250 = nil, nil
				local closest_faction_250 = nil

				for _, faction in ipairs(Map.GetFactions()) do
					if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
						local entities = faction.entities
						local test_unit, tries = nil, 0
						while tries < 15 do
							local ent = entities[math.random(1, #entities)]
							if ent and ent.exists and IsAttackable(ent) then test_unit = ent break end
							tries = tries + 1
						end
						if test_unit then
							local d = comp.owner:GetRangeTo(test_unit)
							if d < closest_dist_any then closest_dist_any, towards_any = d, test_unit end
							if d < 250 and d < closest_dist_250 then
								closest_dist_250, towards_250, closest_faction_250 = d, test_unit, faction
							end
						end
					end
				end

				-- 扩张判定 (使用向导)
				if unit_count < scout_limit and towards_any and closest_dist_any > 100 then
					if math.random() > 0.6 then
						Map.Defer(function() if not comp.owner.exists then return end
							local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
							scout:Place(comp.owner)
							local h = scout:FindComponent("c_bug_harvest")
							if h then
								h.extra_data.home = comp.owner
								h.extra_data.towards = Tool.Copy(towards_any.location)
							end
						end)
					end
					ed_hive.extra_spawned = 0
					-- 只有在尝试扩张后更新全局 last_swarm，并进入长眠
					Map.GetSave().last_swarm = Map.GetTick()
					return comp:SetStateSleep(math.random(4000, 8000))

				-- 入侵判定
				elseif closest_faction_250 then
					local settings = Map.GetSettings()
					if (settings.peaceful == 3 or closest_dist_250 <= 60) and closest_dist_250 < 250 then
						if not IsBugActiveSeason() and math.random() > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end
						local attack_target = closest_faction_250.home_entity
						if not IsAttackable(attack_target) or comp.owner:GetRangeTo(attack_target) > 250 then
							attack_target = towards_250
						end
						if attack_target and attack_target.exists then
							Map.GetSave().last_swarm = Map.GetTick()
							Map.Defer(function() if comp.exists and attack_target.exists then
								data.components.c_bug_spawn:on_trigger_action(comp, attack_target, true)
								ed_hive.extra_spawned = 0
							end end)
						end
					end
				end
			end
		end

		-- 常规轮询频率，对齐原版
		return comp:SetStateSleep(math.random(300, 600))
	end

	---------------------------------------------------------------------------
	-- 4. 软上限削弱 Hook
	---------------------------------------------------------------------------
	local old_spawn_action = c_bug_spawn.on_trigger_action
	c_bug_spawn.on_trigger_action = function(self, comp, target, force)
		local unit_count = GetBugsFaction().extra_data.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
		local soft_limit = 4000 + (pc - 1) * 1500
		if unit_count > soft_limit then force = false end
		return old_spawn_action(self, comp, target, force)
	end

	---------------------------------------------------------------------------
	-- 5. 归巢管理 (侦察虫处决)
	---------------------------------------------------------------------------
	local c_bug_homeless = data.components.c_bug_homeless
	if c_bug_homeless then
		local old_homeless_update = c_bug_homeless.on_update
		c_bug_homeless.on_update = function(self, comp, cause)
			if comp.owner:FindComponent("c_bug_harvest") then comp.owner:Destroy(false) return end
			return old_homeless_update(self, comp, cause)
		end
	end

	---------------------------------------------------------------------------
	-- 6. 侦察 AI (同步官方原版 30格密度)
	---------------------------------------------------------------------------
	c_bug_harvest.on_update = function(self, comp, cause)
		local owner, data = comp.owner, comp.extra_data
		local target, home = data.target, data.home
		if not home or not home.exists then Map.Defer(function() if owner.exists then owner:Destroy() end end) return comp:SetStateSleep(1) end
		if target and not target.exists then data.state, data.target = "wander", nil return comp:SetStateSleep(1) end
		if owner.is_moving then return comp:SetStateSleep(25) end
		local state = data.state or "idle"
		if state == "idle" then
			target = Map.FindClosestEntity(owner, 8, function(e)
				if IsResource(e) and GetResourceHarvestItemId(e) == "silica" and e:GetRangeTo(home) > 20 then return true end
				return false
			end, FF_RESOURCE)
			if target then data.target, data.state = target, "deploy"
			else
				data.state, data.wandertimes = "wander", (data.wandertimes or 0) + 1
				if data.wandertimes > 50 then Map.Defer(function() if owner.exists then owner:Destroy() end end) return comp:SetStateSleep(1) end
			end
		elseif state == "deploy" then
			if not owner.state_path_blocked then if comp:RequestStateMove(target, 3) then return end end
			data.target = nil
			local hive_count = 0
			Map.FindClosestEntity(owner, 30, function(e)
				if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then hive_count = hive_count + 1 if hive_count >= 2 then return true end end
			end, FF_OPERATING | FF_OWNFACTION)
			if hive_count >= 2 then data.state = "wander" return comp:SetStateSleep(200) end
			Map.Defer(function()
				if comp.exists then
					local newhome = Map.CreateEntity(GetBugsFaction(), (math.random() > 0.8) and "f_bug_hive" or "f_bug_hive_large")
					newhome:Place(owner.location)
					owner:Destroy()
				end
			end)
			return comp:SetStateSleep(15)
		elseif state == "wander" then
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

	-- Apply hooks
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.6.9: Vanilla Fidelity Gained. Global Throttling active.")
end
