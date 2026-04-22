-- InsectLimit Mod - Performance & Intelligent Combat Fixes
-- Version: 2.7.7 (Vanilla Aggression Fidelity & Scout Escape Logic)
-- Author: 镜影若滴

local package = ...

---------------------------------------------------------------------------
-- 0. 文件级辅助函数 (File-Level Helpers)
---------------------------------------------------------------------------

-- 检查当前季节是否允许虫群活跃
local function IsBugActiveSeason()
	return math.abs(Map.GetYearSeason() - 0.5) < 0.25
end

-- 【核心修复】：目标合法性筛选器
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

-- 获取玩家阵营统计
local function GetPlayerStats()
	local active_count, total_count = 0, 0
	for _, faction in ipairs(Map.GetFactions()) do
		if faction.is_player_controlled then
			total_count = total_count + 1
			if faction.num_entities > 0 then active_count = active_count + 1 end
		end
	end
	return math.max(1, active_count), math.max(1, total_count)
end

---------------------------------------------------------------------------
-- 1. 全局普查系统 (Diagnostic Heartbeat)
---------------------------------------------------------------------------
function Delay.DiagnosticHeartbeat(arg)
	local bugs = GetBugsFaction()
	if not bugs then return end

	local ents = bugs.entities
	local total = #ents
	local bot_count, perish_count = 0, 0

	for i = 1, total do
		local e = ents[i]
		if e and e.exists then
			if e.has_movement and not e.is_construction then
				bot_count = bot_count + 1
				-- 自动清理低血量感染单位
				if e.state_custom_1 and e.max_health <= 80 then
					e:Destroy(false)
					perish_count = perish_count + 1
				end
			end
		end
	end

	bugs.extra_data.unit_count = bot_count
	bugs.extra_data.asset_count = total

	local active_pc, total_pc = GetPlayerStats()
	local abs_limit = 12000 + (active_pc - 1) * 3000
	local soft_limit = 4000 + (active_pc - 1) * 1500
	local scout_limit = 6000 + (active_pc - 1) * 2000

	-- 实时状态播报
	print(string.format("[InsectLimit] Heartbeat -> Players: %d/%d | BOTS: %d/%d (Soft: %d, Scout: %d) | Assets: %d",
		active_pc, total_pc, bot_count, abs_limit, soft_limit, scout_limit, total))

	Map.Delay("DiagnosticHeartbeat", 150)
end

function package:init()
	print("[InsectLimit] Initializing v2.7.7 - Vanilla Aggression & Scout Escape Logic...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] CRITICAL ERROR: Bug components missing!")
		return
	end

	---------------------------------------------------------------------------
	-- 2. 进攻组件 Hook (战斗状态保护 & 180s 侦察虫容错)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data

			-- 战斗保护：交火中不计时
			if comp.is_working or owner.is_damaged then ed.failed_move_ticks = nil end

			-- 病毒致命处决
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

			-- 卡死判定
			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			if is_stuck then
				if not ed.failed_move_ticks then
					ed.failed_move_ticks = Map.GetTick() + 900
				elseif ed.failed_move_ticks < Map.GetTick() then
					ed.failed_move_ticks = nil
					-- 侦察虫卡死处决
					if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end

					-- 战斗单位寻家
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

	function Delay.BugForcePerish(arg)
		local e = arg.entity
		if e and e.exists then
			if e.is_placed then e:PlayEffect("fx_digital") end
			e:Destroy(false)
		end
	end

	---------------------------------------------------------------------------
	-- 3. 大型蜂巢逻辑 (动态 CD & 全图扩张指南针)
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local active_pc, _ = GetPlayerStats()
		local scaled_cooldown = math.floor(750 / active_pc)
		local last_swarm = Map.GetSave().last_swarm or 0
		local time_since_action = Map.GetTick() - last_swarm
		if time_since_action < scaled_cooldown then
			return comp:SetStateSleep(scaled_cooldown - time_since_action + 1)
		end

		local bugs_faction = GetBugsFaction()
		local ed_faction = bugs_faction.extra_data
		if not ed_faction.heartbeat_started then
			ed_faction.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		local abs_limit = 12000 + (active_pc - 1) * 3000
		local scout_limit = 6000 + (active_pc - 1) * 2000
		local unit_count = ed_faction.unit_count or 0

		if unit_count > abs_limit then return comp:SetStateSleep(5000) end

		local ed_hive = comp.extra_data
		if not ed_hive.extra_spawned then ed_hive.extra_spawned = 0 end
		ed_hive.extra_spawned = ed_hive.extra_spawned + 1

		if ed_hive.extra_spawned > 10 then
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

			-- 侦察派遣
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
				Map.GetSave().last_swarm = Map.GetTick()
				return comp:SetStateSleep(math.random(4000, 8000))

			-- 局部入侵
			elseif closest_faction_250 then
				local settings = Map.GetSettings()
				if (settings.peaceful == 3 or closest_dist_250 <= 60) then
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
		return comp:SetStateSleep(math.random(300, 600))
	end

	---------------------------------------------------------------------------
	-- 4. 归巢逻辑增强 (智能重选 & 筑巢果断性修复)
	---------------------------------------------------------------------------
	local c_bug_homeless = data.components.c_bug_homeless
	if c_bug_homeless then
		local old_homeless_update = c_bug_homeless.on_update
		c_bug_homeless.on_update = function(self, comp, cause)
			local owner, ed = comp.owner, comp.extra_data
			if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end

			-- 【核心修复】：实时校验当前家。如果当前锁定的家满了，立刻换家，不准死守门口
			local currHome = owner:GetRegisterEntity(FRAMEREG_GOTO)
			if currHome then
				local is_full = true
				if currHome.exists and currHome.faction.id == "bugs" then
					for _, v in ipairs(currHome.slots) do
						if v.type == "bughole" and v.entity == nil then is_full = false break end
					end
				end
				if is_full then
					owner:SetRegister(FRAMEREG_GOTO, nil)
					currHome = nil
				end
			end

			-- 对接成功重置记录
			if owner.is_docked then
				ed.bad_homes, ed.penalty_level = nil, nil
				Map.Defer(function() if comp.exists then comp:Destroy() end end)
				return
			end

			-- 路径阻断黑名单 (仅针对 >5格外的死路)
			if owner.state_path_blocked then
				local target_home = owner:GetRegisterEntity(FRAMEREG_GOTO)
				if target_home and target_home.faction.id == "bugs" then
					if owner:GetRangeTo(target_home) >= 5 then
						ed.bad_homes = ed.bad_homes or {}
						ed.bad_homes[target_home.key] = Map.GetTick() + 1250
						owner:SetRegister(FRAMEREG_GOTO, nil)
					end
				end
			end

			if owner:GetRegisterEntity(FRAMEREG_GOTO) then return comp:SetStateSleep(30) end

			-- 【找家策略】：寻找15格内“有空位且可抵达”的蜂巢
			local newhome = Map.FindClosestEntity(owner, 15, function(e)
				if (e.id == "f_bug_hive" or e.id == "f_bug_hive_large") then
					if ed.bad_homes and ed.bad_homes[e.key] and ed.bad_homes[e.key] > Map.GetTick() then return false end
					for _, v in ipairs(e.slots) do
						if v.type == "bughole" and v.entity == nil then return true end
					end
				end
			end, FF_OPERATING | FF_OWNFACTION)

			if newhome then
				owner:SetRegisterEntity(FRAMEREG_GOTO, newhome)
				return comp:SetStateSleep(20)
			end

			-- 【筑巢逻辑还原】：若周围 15 格完全找不到“可进的家”，果断筑巢，不再原地发呆
			if ed.extrawait then ed.extrawait = nil return comp:SetStateSleep(math.random(10, 40)) end

			local foundlarge = Map.FindClosestEntity(owner, 8, function(e) return e.id == "f_bug_hive_large" end, FF_OWNFACTION)
			Map.Defer(function()
				if comp.exists then
					-- 通知邻居等待，防止重叠 (Vanilla extrawait)
					Map.FindClosestEntity(owner, 4, function(friend)
						local c = friend:FindComponent("c_bug_homeless")
						if c then c.extra_data.extrawait = true end
					end, FF_OPERATING | FF_OWNFACTION)
					local hive_type = (math.random() > 0.8 and not foundlarge) and "f_bug_hive_large" or "f_bug_hive"
					local home = Map.CreateEntity(GetBugsFaction(), hive_type)
					home:Place(owner.location)
					owner:SetRegisterEntity(FRAMEREG_GOTO, home)
					comp:Destroy()
				end
			end)
		end
	end

	---------------------------------------------------------------------------
	-- 5. 侦察 AI (增强游荡范围，避免夹击卡死)
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
			-- 【扩张修复】：调回官方原版密度标准：30格内若巢穴少于2个，允许筑巢
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
				-- 【引导优化】：步长提升，模拟大跨度侦察
				local dx = math.min(math.max((tloc.x - loc.x) // 3, -80), 80)
				local dy = math.min(math.max((tloc.y - loc.y) // 3, -80), 80)
				loc.x, loc.y = loc.x + dx + math.random(-10, 10), loc.y + dy + math.random(-10, 10)
			else
				-- 【脱困优化】：随机游荡半径提升至 30 格，帮助虫子跳出蜂巢夹击区域
				loc.x, loc.y = loc.x + math.random(-30, 30), loc.y + math.random(-30, 30)
			end
			data.state = "idle"
			return comp:RequestStateMove(loc, 1)
		end
	end

	-- Apply All Hooks
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.7.7: Expansion Logic Refined & Stuck-Breaker Enhanced.")
end
