-- InsectLimit Mod - Performance & Intelligent Combat Fixes
-- Version: 2.7.21 (Logic Alignment: Total vs Active Players)
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

-- 获取玩家统计 (活跃/总数)
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

	-- 【逻辑对齐】：
	-- 上限配额 (Capacities) 统一按总人数 (total_pc) 计算。
	-- 性能阈值 (Throttling) 统一按存活人数 (active_pc) 计算。
	local abs_limit = 12000 + (total_pc - 1) * 3000
	local soft_limit = 4000 + (active_pc - 1) * 1500
	local scout_limit = 6000 + (active_pc - 1) * 2000

	-- 播报
	print(string.format("[InsectLimit] Heartbeat -> Players: %d/%d (Alive/Total) | BOTS: %d/%d (Soft: %d, Scout: %d) | Assets: %d",
		active_pc, total_pc, bot_count, abs_limit, soft_limit, scout_limit, total))

	Map.Delay("DiagnosticHeartbeat", 150)
end

-- 【关键机制】：病毒致死处决执行器
function Delay.BugForcePerish(arg)
	local e = arg.entity
	if e and e.exists then
		if e.is_placed then e:PlayEffect("fx_digital") end
		e:Destroy(false)
	end
end

function package:init()
	print("[InsectLimit] Initializing v2.7.21 Final - Multi-Dimensional Scaling Deployed...")

	local components = data.components
	local c_bug_spawn = components.c_bug_spawn
	local c_bug_spawner_large = components.c_bug_spawner_large
	local c_bug_harvest = components.c_bug_harvest
	local c_trilobyte_attack = components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] CRITICAL ERROR: Bug components missing!")
		return
	end

	---------------------------------------------------------------------------
	-- 2. 进攻组件 Hook (精准战斗判定)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data

			-- 【核心修复】：精准战斗判定
			local current_health = owner.health
			local took_damage = ed.last_health and (current_health < ed.last_health)
			if comp.is_working or took_damage then
				ed.failed_move_ticks = nil
			end
			ed.last_health = current_health

			-- 病毒处决
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
					ed.failed_move_ticks = Map.GetTick() + 600
				elseif ed.failed_move_ticks < Map.GetTick() then
					ed.failed_move_ticks = nil
					if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end
					if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
					if not owner:FindComponent("c_bug_homeless") then
						Map.Defer(function()
							if comp.exists and not owner:FindComponent("c_bug_homeless") then
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
	-- 3. 大型蜂巢逻辑 (三项独立限速通道)
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_f = GetBugsFaction()
		if not bugs_f.extra_data.heartbeat_started then
			bugs_f.extra_data.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		local active_pc, total_pc = GetPlayerStats()
		-- 频率锁基于存活玩家 (active_pc)，保护服务器性能
		local scaled_cd = math.floor(750 / active_pc)
		local unit_count = bugs_f.extra_data.unit_count or 0
		-- 容量锁基于总玩家 (total_pc)，维持世界强度
		local abs_limit = 12000 + (total_pc - 1) * 3000
		local scout_limit = 6000 + (total_pc - 1) * 2000

		if unit_count > abs_limit then return comp:SetStateSleep(5000) end

		local ed_hive = comp.extra_data
		if not ed_hive.extra_spawned then ed_hive.extra_spawned = 0 end
		ed_hive.extra_spawned = ed_hive.extra_spawned + 1

		if ed_hive.extra_spawned > 10 then
			local tick = Map.GetTick()
			local save = Map.GetSave()
			local rnd = math.random()

			local dist_any, dist_250 = 9999999, 9999999
			local towards_any, towards_250, closest_faction_250 = nil, nil, nil

			for _, faction in ipairs(Map.GetFactions()) do
				if faction.is_player_controlled and faction.num_entities > 0 and bugs_f:GetTrust(faction) == "ENEMY" then
					local entities = faction.entities
					local test_unit, tries = nil, 0
					while tries < 15 do
						local ent = entities[math.random(1, #entities)]
						if ent and ent.exists and IsAttackable(ent) then test_unit = ent break end
						tries = tries + 1
					end
					if test_unit then
						local d = comp.owner:GetRangeTo(test_unit)
						if d < dist_any then dist_any, towards_any = d, test_unit end
						if d < 250 and d < dist_250 then dist_250, towards_250, closest_faction_250 = d, test_unit, faction end
					end
				end
			end

			-- ---【1】：派遣侦察虫 (基于活跃人数频率) ---
			if (tick - (save.last_scout_tick or 0)) > scaled_cd then
				if unit_count < scout_limit and towards_any and dist_any > 100 then
					if rnd > 0.6 then
						save.last_scout_tick = tick
						ed_hive.extra_spawned = 0
						Map.Defer(function() if not comp.owner.exists then return end
							local scout = Map.CreateEntity(bugs_f, "f_triloscout")
							scout:Place(comp.owner)
							local h = scout:FindComponent("c_bug_harvest")
							if h then h.extra_data.home = comp.owner h.extra_data.towards = Tool.Copy(towards_any.location) end
						end)
						return comp:SetStateSleep(math.random(4000, 8000))
					end
				end
			end

			-- ---【2】：发起进攻 (基于活跃人数频率) ---
			if (tick - (save.last_attack_tick or 0)) > (scaled_cd * 0.8) then
				if closest_faction_250 then
					local settings = Map.GetSettings()
					if (settings.peaceful == 3 or dist_250 <= 60) then
						if not IsBugActiveSeason() and rnd > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end
						local target = closest_faction_250.home_entity
						if not IsAttackable(target) or comp.owner:GetRangeTo(target) > 250 then target = towards_250 end
						if target and target.exists then
							save.last_attack_tick = tick
							ed_hive.extra_spawned = 0
							Map.Defer(function() if comp.exists and target.exists then
								data.components.c_bug_spawn:on_trigger_action(comp, target, true)
							end end)
							return comp:SetStateSleep(math.random(2000, 4000))
						end
					end
				end
			end

			-- ---【3】：蜂巢扩张 (基于活跃人数频率) ---
			if (tick - (save.last_nest_tick or 0)) > (scaled_cd * 1.5) then
				if rnd < 0.2 then
					local found = Map.FindClosestEntity(comp.owner, 10, function(e)
						if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then return true end
					end, FF_OPERATING|FF_OWNFACTION)
					if not found then
						save.last_nest_tick = tick
						ed_hive.extra_spawned = 0
						Map.Defer(function() if comp.exists then
							Map.CreateEntity(bugs_f, "f_bug_hive"):Place(comp.owner.location)
						end end)
						return comp:SetStateSleep(math.random(1000, 2000))
					end
				end
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	---------------------------------------------------------------------------
	-- 4. 归巢逻辑优化 (复刻原版战斗任务优先级判定)
	---------------------------------------------------------------------------
	local c_bug_homeless = components.c_bug_homeless
	if c_bug_homeless then
		c_bug_homeless.on_update = function(self, comp, cause)
			local owner, ed = comp.owner, comp.extra_data
			if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end

			-- 【核心复刻】：战斗任务优先。单位正在战斗或奔向前线时，归巢逻辑强制闭嘴。
			local attack_comp = owner:FindComponent("c_turret", true)
			if attack_comp and not owner.state_path_blocked then
				local ent = attack_comp:GetRegisterEntity(1) or attack_comp:GetRegisterEntity(2)
				local coord = attack_comp:GetRegisterCoord(1)
				if attack_comp.is_working or ent or (coord and not owner:IsInRangeOf(coord, 5)) then
					return comp:SetStateSleep(300)
				end
			end

			if owner.is_docked then
				ed.bad_homes, ed.penalty_level, ed.last_health = nil, nil, nil
				Map.Defer(function() if comp.exists then comp:Destroy() end end)
				return
			end

			-- 归巢黑名单
			if owner.state_path_blocked then
				local target_home = owner:GetRegisterEntity(FRAMEREG_GOTO)
				if target_home and target_home.faction.id == "bugs" and owner:GetRangeTo(target_home) >= 5 then
					ed.bad_homes = ed.bad_homes or {}
					ed.bad_homes[target_home.key] = Map.GetTick() + 1250
					owner:SetRegister(FRAMEREG_GOTO, nil)
				end
			end

			if owner:GetRegisterEntity(FRAMEREG_GOTO) then return comp:SetStateSleep(30) end

			local newhome = Map.FindClosestEntity(owner, 15, function(e)
				if (e.id == "f_bug_hive" or e.id == "f_bug_hive_large") then
					if ed.bad_homes and ed.bad_homes[e.key] and ed.bad_homes[e.key] > Map.GetTick() then return false end
					for _, v in ipairs(e.slots) do if v.type == "bughole" and v.entity == nil then return true end end
				end
			end, FF_OPERATING | FF_OWNFACTION)

			if newhome then owner:SetRegisterEntity(FRAMEREG_GOTO, newhome) return comp:SetStateSleep(20) end

			-- 筑巢速率名额限制
			local tick = Map.GetTick()
			local bugs_ed = GetBugsFaction().extra_data
			if bugs_ed.last_nest_tick_homeless == tick then
				if (bugs_ed.nest_count_this_tick or 0) >= 2 then return comp:SetStateSleep(math.random(5, 10)) end
				bugs_ed.nest_count_this_tick = bugs_ed.nest_count_this_tick + 1
			else
				bugs_ed.last_nest_tick_homeless = tick
				bugs_ed.nest_count_this_tick = 1
			end

			if ed.extrawait then ed.extrawait = nil return comp:SetStateSleep(math.random(10, 40)) end
			local foundlarge = Map.FindClosestEntity(owner, 8, function(e) return e.id == "f_bug_hive_large" end, FF_OWNFACTION)
			Map.Defer(function()
				if comp.exists then
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
	-- 5. 侦察 AI (同步原版密度 & 全局扩张锁)
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
			Map.FindClosestEntity(owner, 20, function(e)
				if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then hive_count = hive_count + 1 if hive_count >= 4 then return true end end
			end, FF_OPERATING | FF_OWNFACTION)
			if hive_count >= 4 then data.state = "wander" return comp:SetStateSleep(200) end

			-- 侦察虫扩张受 save.last_nest_tick 全局战略锁控制
			local save = Map.GetSave()
			if (Map.GetTick() - (save.last_nest_tick or 0)) < 100 then data.state = "wander" return comp:SetStateSleep(100) end

			Map.Defer(function()
				if comp.exists then
					save.last_nest_tick = Map.GetTick()
					local newhome = Map.CreateEntity(GetBugsFaction(), (math.random() > 0.8) and "f_bug_hive" or "f_bug_hive_large")
					newhome:Place(owner.location)
					owner:Destroy()
				end
			end)
			return comp:SetStateSleep(15)
		elseif state == "wander" then
			local loc = Tool.Copy(owner.location)
			if data.towards then
				local tloc = data.towards
				local dx = math.min(math.max((tloc.x - loc.x) // 2, -80), 80)
				local dy = math.min(math.max((tloc.y - loc.y) // 2, -80), 80)
				loc.x, loc.y = loc.x + dx + math.random(-15, 15), loc.y + dy + math.random(-15, 15)
			else
				loc.x, loc.y = loc.x + math.random(-50, 50), loc.y + math.random(-50, 50)
			end
			data.state = "idle"
			return comp:RequestStateMove(loc, 1)
		end
	end

	-- Apply All Attack Hooks
	local hooks = {
		"c_trilobyte_attack", "c_trilobyte_attack_t2", "c_trilobyte_attack_t3",
		"c_trilobyte_attack1", "c_trilobyte_attack2", "c_trilobyte_attack3", "c_trilobyte_attack4",
		"c_wasp_attack1", "c_tripodonte1", "c_tetrapuss_attack1", "c_larva_attack1", "c_larva_attack2"
	}
	for _, n in ipairs(hooks) do if components[n] then components[n].on_update = BugAttackUpdate end end

	print("[InsectLimit] v2.7.21 Aligned - Dynamic Multi-Scaling Deployed.")
end
