-- InsectLimit Mod - Performance & Intelligent Combat Fixes
-- Version: 2.7.35 (Safety Reinforced & Expansion Fix)
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
-- 解决了原版 AI 攻击蓝图导致单位堆积的致命 Bug
local function IsAttackable(e)
	if not e or not e.exists then return false end
	local target = e.is_placed and e or e.docked_garage
	if not target or not target.is_placed or e.id == "f_empty" then return false end
	local def = target.def
	if target.stealth or target.is_construction or def.immortal then return false end
	if def.is_explorable and not target.faction.is_player_controlled then return false end
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
	-- 保护：确保不会出现除以 0
	return math.max(1, active_count), math.max(1, total_count)
end

---------------------------------------------------------------------------
-- 1. 全局普查系统 (Diagnostic Heartbeat)
---------------------------------------------------------------------------
function Delay.DiagnosticHeartbeat(arg)
	local bugs = GetBugsFaction()
	if not bugs then
		Map.Delay("DiagnosticHeartbeat", 10)
		return
	end

	-- 【救档核心：线程自动融合逻辑】
	-- 如果当前 Tick 已经有统计完成了，说明是重复拉起的线程，立即终止循环。
	local tick = Map.GetTick()
	local bugs_ed = bugs.extra_data
	if bugs_ed.last_hb_run_tick == tick then return end
	bugs_ed.last_hb_run_tick = tick

	local ents = bugs.entities
	local total_assets = #ents
	local bot_count = 0
	for i = 1, total_assets do
		local e = ents[i]
		if e and e.exists and e.has_movement and not e.is_construction then
			bot_count = bot_count + 1
			if e.state_custom_1 and e.max_health <= 80 then e:Destroy(false) end
		end
	end

	bugs_ed.unit_count = bot_count
	local active_pc, total_pc = GetPlayerStats()

	-- 【逻辑对齐】：上限配额严格基于总人数 (total_pc)，频率缩放基于活跃人数 (active_pc)。
	-- abs_limit是绝对单位上限，soft_limit是削弱闸值(指超过这个值开始削减波次强度减少单位数量)，scout_limit是派遣侦察虫筑巢行动活跃的上限。scaled_cd指全局CD(tick)。
	local abs_limit = 12000 + (total_pc - 1) * 3000
	local soft_limit = 4000 + (total_pc - 1) * 1500
	local scout_limit = 6000 + (total_pc - 1) * 2000

	-- 同步动态上限至 extra_data
	bugs_ed.abs_limit = abs_limit
	bugs_ed.soft_limit = soft_limit
	bugs_ed.scout_limit = scout_limit

	local scaled_cd = 200 + math.floor(500 / active_pc)

	-- 【对齐播报】：Players: 活跃/总数 (Alive/Total) | BOTS: 当前/上限 (Soft, Scout) | Assets: 总资产
	print(string.format("[InsectLimit] Heartbeat -> Players: %d/%d (Alive/Total) | BOTS: %d/%d (Soft: %d, Scout: %d) | Assets: %d | CD: %d",
		active_pc, total_pc, bot_count, abs_limit, soft_limit, scout_limit, total_assets, scaled_cd))
	Map.Delay("DiagnosticHeartbeat", 150)
end

-- 【关键机制】：病毒致死处决执行器
function Delay.BugForcePerish(arg)
	local e = arg.entity
	if e and e.exists then if e.is_placed then e:PlayEffect("fx_digital") end e:Destroy(false) end
end

---------------------------------------------------------------------------
-- 2. 系统注入启动器
---------------------------------------------------------------------------
function MapMsg.OnTick()
	if _G.InsectLimitActive then return end
	local bugs = GetBugsFaction()
	if bugs then
		_G.InsectLimitActive = true
		local ed = bugs.extra_data
		if not ed.heartbeat_active and not ed.heartbeat_started then
			ed.heartbeat_active = true
			print("[InsectLimit] SYSTEM STARTUP -> Diagnostic Heartbeat bootstrapped via MapMsg.OnTick")
			Map.Delay("DiagnosticHeartbeat", 5)
		end
	end
end

function package:init()
	print("[InsectLimit] Initializing v2.7.35 - Safety Gatecheck & Expansion Fix Deployed...")

	local components = data.components

	-- 进攻组件 Hook
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data
			local cur_h = owner.health
			if comp.is_working or (ed.last_health and cur_h < ed.last_health) then ed.failed_move_ticks = nil end
			ed.last_health = cur_h

			if owner.state_custom_1 and owner.max_health <= 80 and not IsFlyingUnit(owner) then
				if not ed.virus_marked_for_death then
					ed.virus_marked_for_death = true
					owner:Cancel() owner.powered_down = true
					if owner.is_placed then owner:PlayEffect("fx_glitch2") end
					Map.Delay("BugForcePerish", 150, { entity = owner })
				end
				return true
			end

			-- 180s 容错判定
			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			if is_stuck then
				if not ed.failed_move_ticks then ed.failed_move_ticks = Map.GetTick() + 900
				elseif ed.failed_move_ticks < Map.GetTick() then
					ed.failed_move_ticks = nil
					-- 侦察虫直接销毁
					if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end

					-- 战斗单位解脱并重新寻巢
					if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
					Map.Defer(function() if owner.exists and not owner:FindComponent("c_bug_homeless") then
						local h = (owner.health > 200) and owner:AddComponent("c_bug_homeless")
						if h then h:Activate() else owner:Destroy() end
					end end)
					return
				end
			else
				if not owner.state_path_blocked and owner.is_moving then ed.failed_move_ticks = nil end
			end
		end
		return data.components.c_turret.on_update(self, comp, cause)
	end

	-- 【波次产生器】：完全克隆并修复原版逻辑中的削弱不匹配问题
	components.c_bug_spawn.on_trigger_action = function (self, comp, other_entity, force)
		local bugs_f = comp.faction
		if bugs_f.is_player_controlled then Map.Defer(function() if comp.exists then comp:Destroy() end end) return end

		-- 激活周围巢穴
		if comp.id == "c_bug_spawner_large" then
			Map.FindClosestEntity(comp.owner, 10, function(e)
				if e.id ~= "f_bug_hive" then return end
				local c = e:FindComponent("c_bug_spawn")
				if c then self:on_trigger_action(c, other_entity, force) end
			end, FF_OPERATING)
		end

		if not other_entity.faction.is_player_controlled or bugs_f:GetTrust(other_entity) ~= "ENEMY" or other_entity.stealth then return end

		local ed = comp.extra_data
		if not ed.bugs then ed.bugs, ed.spawned, ed.lvl, ed.extra_spawned = {}, Map.GetTick() - 901, 0, 0 end
		for i=#ed.bugs,1,-1 do if not ed.bugs[i].exists then table.remove(ed.bugs, i) end end

		if #ed.bugs > 0 then
			for _,bug in ipairs(ed.bugs) do
				bug:FindComponent("c_turret", true):SetRegisterCoord(1, other_entity.location)
				if force and not bug:FindComponent("c_bug_homeless") then bug:SetRegisterEntity(FRAMEREG_GOTO, nil) bug:AddComponent("c_bug_homeless", "hidden") end
			end
			return
		end

		local map_tick = Map.GetTick()
		if map_tick - ed.spawned < 900 and not force then return end

		-- 1. 计算基础数量 (补全 Stability 系统加成)
		local early_easy = 2 + math.min(Map.GetTotalDays() // 2, 6)
		local max_num = (comp.owner.id == "f_bug_hole" and 1 or early_easy) + ed.extra_spawned
		if StabilityGet then
			local stability = -StabilityGet()
			max_num = max_num + math.max(0, stability // 500)
		end
		max_num = math.min(max_num, comp.owner.def.slots and comp.owner.def.slots.bughole or 1)
		local num = math.random(math.ceil(max_num / 3), max_num)

		-- 2. 玩家等级与距离判定 (补全 Plateau 地形判定)
		local other_faction = other_entity.faction
		local player_level = GetPlayerFactionLevel(other_faction)
		local loc = comp.owner.location
		local dist = 0
		if other_faction.home_location then
			local dx, dy = loc.x - other_faction.home_location.x, loc.y - other_faction.home_location.y
			dist = dx*dx + dy*dy
		end
		local settings = Map.GetSettings()
		local tile_h = Map.GetElevation(loc.x, loc.y)
		if tile_h < settings.plateau_level then dist = 0 end

		if dist > 30000 then player_level = player_level + 5
		elseif dist > 90000 then player_level = player_level + 10
		elseif dist > 122500 then player_level = player_level + 20 end

		-- 3. 强度恢复核心逻辑
		if force and settings.peaceful == 3 then
			local ramp = 0.4
			local level = math.ceil(player_level * ramp)
			num = math.max(level + 1, num) -- 强度泵

			-- 动态削弱：对齐模组上限，引入 0.33 保底强度
			local unit_count = bugs_f.extra_data.unit_count or 0
			local soft = bugs_f.extra_data.soft_limit or 4000
			local abs = bugs_f.extra_data.abs_limit or 12000
			if unit_count > soft then
				local intensity = math.max(0.33, 1.0 - (unit_count - soft) / (abs - soft))
				num = math.max(1, math.floor(num * intensity)) -- 强度修正
			end
		else
			num = math.min((player_level // 3) + 1, num)
		end

		local bug_levels = GetBugCountsForLevel(player_level, num, force)
		local spawn_delay = 1
		local all_bugs_count = 0
		for i=1,#bug_levels do all_bugs_count = all_bugs_count + bug_levels[i] end
		local num_waves = (all_bugs_count // 30) + 1
		local target_loc = Tool.Copy(other_entity.location)

		for i=#bug_levels,1,-1 do
			if bug_levels[i] > 0 then
				for j=1,bug_levels[i] do
					local bug_delay = (((spawn_delay % 15) + ((math.random(1, num_waves)-1)*30))*3)+1
					Map.Delay("SpawnFromHive", math.max(1, bug_delay), {
						level = i, force = force, owner = comp.owner, loc = Tool.Copy(loc), target = target_loc, comp = comp, faction = bugs_f
					})
					spawn_delay = spawn_delay + 1
				end
			end
		end
		ed.spawned, ed.lvl = map_tick, ed.lvl + 1
		if comp.owner.id == "f_bug_hive" and ed.extra_spawned < 8 and math.random() <= 0.05 then
			local x, y = comp.owner.location.x, comp.owner.location.y
			local nb = Map.CreateEntity(bugs_f, "f_bug_hole") nb:Place(math.random(x-4, x+4), math.random(y-4, y+4))
			nb:PlayEffect("fx_digital_in") ed.extra_spawned = ed.extra_spawned + 1
		end
		if not ed.rewards then comp.owner:AddItem("bug_carapace", math.min(all_bugs_count, 20)) ed.rewards = all_bugs_count end
	end

	-- 大型蜂巢行为 (性能门禁前置与安全增强版寻敌)
	components.c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_f = GetBugsFaction()
		local bugs_ed = bugs_f.extra_data
		local unit_count = bugs_ed.unit_count or 0

		-- 【门禁 1】：绝对上限预检
		if unit_count > (bugs_ed.abs_limit or 12000) then return comp:SetStateSleep(1000) end

		local tick, save = Map.GetTick(), Map.GetSave()
		local active_pc, total_pc = GetPlayerStats()
		local scaled_cd = 200 + math.floor(500 / active_pc)

		-- 【门禁 2】：冷却状态预检 (包含扩张 nest_ready)
		local scout_ready = (tick - (save.last_scout_tick or 0)) > scaled_cd and unit_count < (bugs_ed.scout_limit or 6000)
		local attack_ready = (tick - (save.last_attack_tick or 0)) > (scaled_cd * 0.8)
		local nest_ready = (tick - (save.last_nest_tick or 0)) > (scaled_cd * 1.5)

		if not (scout_ready or attack_ready or nest_ready) then
			return comp:SetStateSleep(math.random(100, 200))
		end

		local ed_hive = comp.extra_data
		ed_hive.extra_spawned = (ed_hive.extra_spawned or 0) + 1

		-- 【门禁 3】：决策窗口
		if ed_hive.extra_spawned > 10 then
			local rnd = math.random()
			local towards_any, towards_250, dist_250 = nil, nil, 9999999
            local factions = Map.GetFactions()
            local f_count = #factions

            -- 【安全加固】：防护 modulo 0 导致的脚本中断 (极端图)
            if f_count > 0 then
                local hive_key = comp.owner.key or 0
                local f_start = ((hive_key + tick) % f_count) + 1
                local forward = (tick % 2 == 0)

                for i = 1, f_count do
                    local f_idx = forward and ((f_start + i - 2) % f_count + 1) or ((f_start - i + f_count) % f_count + 1)
                    local faction = factions[f_idx]

                    if faction.is_player_controlled and faction.num_entities > 0 and bugs_f:GetTrust(faction) == "ENEMY" then
						local home = faction.home_entity
						local dice = (math.random() > 0.5)

						-- 1. 几率斩首
						if dice and home and home.exists and IsAttackable(home) then
							local d = comp.owner:GetRangeTo(home)
							towards_any = home
							if d < 250 then towards_250, dist_250 = home, d end
						end

						-- 2. 常规采样
						if not towards_250 then
							local entities = faction.entities
							local e_count = #entities
							if e_count > 0 then
								for try = 1, 15 do
									local ent = entities[math.random(1, e_count)]
									if ent and ent.exists and IsAttackable(ent) then
										local d = comp.owner:GetRangeTo(ent)
										towards_any = ent
										if d < 250 and d < dist_250 then towards_250, dist_250 = ent, d end
										if d < 250 then break end
									end
								end
							end
						end

						-- 3. 后置兜底
						if not towards_250 and not dice and home and home.exists and IsAttackable(home) then
							local d = comp.owner:GetRangeTo(home)
							towards_any = home
							if d < 250 then towards_250, dist_250 = home, d end
						end

                        if towards_any then break end
                    end
                end
            end

			-- --- 执行层 ---
			if scout_ready and towards_any and comp.owner:GetRangeTo(towards_any) > 100 and rnd > 0.6 then
				save.last_scout_tick = tick ed_hive.extra_spawned = 0
				local target_loc = Tool.Copy(towards_any.location)
				Map.Defer(function() if comp.owner.exists and target_loc then
					local s = Map.CreateEntity(bugs_f, "f_triloscout") s:Place(comp.owner)
					local h = s:FindComponent("c_bug_harvest") if h then h.extra_data.home = comp.owner h.extra_data.towards = target_loc end
				end end)
				return comp:SetStateSleep(math.random(4000, 8000))
			end

			if attack_ready and towards_250 then
				if not IsBugActiveSeason() and rnd > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end
				save.last_attack_tick = tick ed_hive.extra_spawned = 0
				Map.Defer(function() if comp.exists and towards_250.exists then data.components.c_bug_spawn:on_trigger_action(comp, towards_250, true) end end)
				return comp:SetStateSleep(math.random(2000, 4000))
			end
			-- 自然扩张
			if nest_ready and rnd < 0.2 then
				local found = Map.FindClosestEntity(comp.owner, 10, function(e) return (e.id == "f_bug_hive" or e.id == "f_bug_hive_large") end, FF_OPERATING|FF_OWNFACTION)
				if not found then save.last_nest_tick = tick ed_hive.extra_spawned = 0 Map.Defer(function() if comp.exists then Map.CreateEntity(bugs_f, "f_bug_hive"):Place(comp.owner.location) end end) return comp:SetStateSleep(math.random(1000, 2000)) end
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	-- 其余逻辑维持 v2.7.32 稳定版
	if components.c_bug_homeless then
		components.c_bug_homeless.on_update = function(self, comp, cause)
			local owner, ed = comp.owner, comp.extra_data
			if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end
			local attack_comp = owner:FindComponent("c_turret", true)
			if attack_comp and not owner.state_path_blocked then
				local ent = attack_comp:GetRegisterEntity(1) or attack_comp:GetRegisterEntity(2)
				local coord = attack_comp:GetRegisterCoord(1)
				if attack_comp.is_working or ent or (coord and owner:GetRangeTo(coord) > 5) then return comp:SetStateSleep(300) end
			end
			local currHome = owner:GetRegisterEntity(FRAMEREG_GOTO)
			if currHome then
				local has_slot = false
				if currHome.exists and currHome.faction.id == "bugs" then
					for _, v in ipairs(currHome.slots) do if v.type == "bughole" and v.entity == nil then has_slot = true break end end
				end
				if not has_slot then owner:SetRegister(FRAMEREG_GOTO, nil) currHome = nil end
			end
			if owner.is_docked then ed.last_health = nil Map.Defer(function() if comp.exists then comp:Destroy() end end) return end
			if owner.state_path_blocked then
				local th = owner:GetRegisterEntity(FRAMEREG_GOTO)
				if th and th.faction.id == "bugs" and owner:GetRangeTo(th) >= 5 then owner:SetRegister(FRAMEREG_GOTO, nil) end
			end
			if owner:GetRegisterEntity(FRAMEREG_GOTO) then return comp:SetStateSleep(30) end
			local nh = Map.FindClosestEntity(owner, 15, function(e)
				if (e.id == "f_bug_hive" or e.id == "f_bug_hive_large") then
					for _, v in ipairs(e.slots) do if v.type == "bughole" and v.entity == nil then return true end end
				end
			end, FF_OPERATING | FF_OWNFACTION)
			if nh then owner:SetRegisterEntity(FRAMEREG_GOTO, nh) return comp:SetStateSleep(10) end

			local bugs_ed = GetBugsFaction().extra_data
			if bugs_ed.last_nest_tick_homeless == Map.GetTick() then
				if (bugs_ed.nest_count_this_tick or 0) >= 5 then return comp:SetStateSleep(5) end
				bugs_ed.nest_count_this_tick = bugs_ed.nest_count_this_tick + 1
			else bugs_ed.last_nest_tick_homeless = Map.GetTick() bugs_ed.nest_count_this_tick = 1 end
			if ed.extrawait then ed.extrawait = nil return comp:SetStateSleep(math.random(10, 40)) end
			Map.Defer(function() if comp.exists then
				local neigh = Map.GetEntitiesInRange(owner, 4, FF_OPERATING|FF_OWNFACTION)
				if #neigh < 10 then for _, f in ipairs(neigh) do local c=f:FindComponent("c_bug_homeless") if c then c.extra_data.extrawait=true end end end
				local home = Map.CreateEntity(GetBugsFaction(), (math.random()>0.8) and "f_bug_hive_large" or "f_bug_hive")
				if home then home:Place(owner.location) owner:SetRegisterEntity(FRAMEREG_GOTO, home) comp:Destroy() end
			end end)
		end
	end

	-- 侦察虫 AI
	components.c_bug_harvest.on_update = function(self, comp, cause)
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
			local save = Map.GetSave()
			if (Map.GetTick() - (save.last_nest_tick or 0)) < 100 then data.state = "wander" return comp:SetStateSleep(100) end
			Map.Defer(function() if comp.exists then
				save.last_nest_tick = Map.GetTick()
				local newhome = Map.CreateEntity(GetBugsFaction(), (math.random() > 0.8) and "f_bug_hive" or "f_bug_hive_large")
				newhome:Place(owner.location) owner:Destroy()
			end end)
			return comp:SetStateSleep(15)
		elseif state == "wander" then
			local loc = Tool.Copy(owner.location)
			if data.towards then
				local dx = math.min(math.max((data.towards.x - loc.x) // 2, -80), 80)
				local dy = math.min(math.max((data.towards.y - loc.y) // 2, -80), 80)
				loc.x, loc.y = loc.x + dx + math.random(-15, 15), loc.y + dy + math.random(-15, 15)
			else loc.x, loc.y = loc.x + math.random(-50, 50), loc.y + math.random(-50, 50) end
			data.state = "idle"
			return comp:RequestStateMove(loc, 1)
		end
	end

	-- Apply All Attack Hooks
	local hooks = {"c_trilobyte_attack", "c_trilobyte_attack_t2", "c_trilobyte_attack_t3", "c_trilobyte_attack1", "c_trilobyte_attack2", "c_trilobyte_attack3", "c_trilobyte_attack4", "c_wasp_attack1", "c_tripodonte1", "c_tetrapuss_attack1", "c_larva_attack1", "c_larva_attack2"}
	for _, n in ipairs(hooks) do if components[n] then components[n].on_update = BugAttackUpdate end end
end
