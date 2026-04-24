-- InsectLimit Mod - Performance & Intelligent Combat Fixes
-- Version: 2.7.31 (Legacy Save Auto-Merge & Pure Decoupling)
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
		-- 环境未就绪则延迟 10 tick 后重试
		Map.Delay("DiagnosticHeartbeat", 10)
		return
	end

	-- 【救档核心：唯一线程竞争自杀协议】
	-- 如果当前 Tick 已经有统计完成了，说明当前运行的是旧存档残留的多余线程。
	-- 立即终止本线程循环 (不执行 Map.Delay)，从而实现旧档多线程自动融合。
	local tick = Map.GetTick()
	local ed = bugs.extra_data
	if ed.last_hb_run_tick == tick then return end
	ed.last_hb_run_tick = tick

	local ents = bugs.entities
	local total_assets = #ents
	local bot_count = 0
	for i = 1, total_assets do
		local e = ents[i]
		if e and e.exists and e.has_movement and not e.is_construction then
			bot_count = bot_count + 1
			-- 自动清理低血量感染单位
			if e.state_custom_1 and e.max_health <= 80 then e:Destroy(false) end
		end
	end

	ed.unit_count = bot_count
	local active_pc, total_pc = GetPlayerStats()

	-- 【逻辑稳固】：所有的容量上限 (Limit/Threshold) 均严格基于总玩家数 (total_pc)
	-- 活动频率缩放基于活跃玩家 (active_pc)，优化 UPS 性能。
	local abs_limit = 12000 + (total_pc - 1) * 3000
	local soft_limit = 4000 + (total_pc - 1) * 1500
	local scout_limit = 6000 + (total_pc - 1) * 2000

	-- 播报完整格式
	print(string.format("[InsectLimit] Heartbeat -> Players: %d/%d (Alive/Total) | BOTS: %d/%d (Soft: %d, Scout: %d) | Assets: %d",
		active_pc, total_pc, bot_count, abs_limit, soft_limit, scout_limit, total_assets))

	Map.Delay("DiagnosticHeartbeat", 150)
end

-- 【关键机制】：病毒致死处决执行器
function Delay.BugForcePerish(arg)
	local e = arg.entity
	if e and e.exists then if e.is_placed then e:PlayEffect("fx_digital") end e:Destroy(false) end
end

---------------------------------------------------------------------------
-- 2. 系统注入启动器 (全面兼容旧版存档残留)
---------------------------------------------------------------------------
function MapMsg.OnTick()
	-- 确保即使没有任何实体，模组逻辑也能自动拉起心跳
	if _G.InsectLimitActive then return end
	local bugs = GetBugsFaction()
	if bugs then
		_G.InsectLimitActive = true
		local ed = bugs.extra_data
		-- 兼容性检查：如果是新档或无残留旧档才拉起新的 Delay
		if not ed.heartbeat_active and not ed.heartbeat_started then
			ed.heartbeat_active = true
			print("[InsectLimit] SYSTEM STARTUP -> Diagnostic Heartbeat bootstrapped via MapMsg.OnTick")
			Map.Delay("DiagnosticHeartbeat", 5)
		end
	end
end

function package:init()
	print("[InsectLimit] Initializing v2.7.31 Final - Independent Simulation Startup Deployed...")

	local components = data.components

	---------------------------------------------------------------------------
	-- 3. 进攻组件 Hook (精准战斗判定)
	---------------------------------------------------------------------------
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

			-- 180s 容错卡死判定
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

	---------------------------------------------------------------------------
	-- 4. 大型蜂巢逻辑 (三路解耦 & 分布式采样)
	---------------------------------------------------------------------------
	components.c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end
		local bugs_f = GetBugsFaction()
		local active_pc, total_pc = GetPlayerStats()
		-- 【频率保底公式】：300 + 500/玩家数。确保决策频率有下限，保护多人服务器。
		local scaled_cd = 300 + math.floor(500 / active_pc)

		local unit_count = bugs_f.extra_data.unit_count or 0
		local abs_limit = 12000 + (total_pc - 1) * 3000
		local scout_limit = 6000 + (total_pc - 1) * 2000

		if unit_count > abs_limit then return comp:SetStateSleep(5000) end

		local ed_hive = comp.extra_data
		ed_hive.extra_spawned = (ed_hive.extra_spawned or 0) + 1

		if ed_hive.extra_spawned > 10 then
			local tick, save, rnd = Map.GetTick(), Map.GetSave(), math.random()

			-- 分布式采样逻辑
			local towards_any, towards_250, dist_250 = nil, nil, 9999999
			local factions = Map.GetFactions()
			for f_idx = 1, #factions do
				local faction = factions[f_idx]
				if faction.is_player_controlled and faction.num_entities > 0 and bugs_f:GetTrust(faction) == "ENEMY" then
					local entities = faction.entities
					local tries = 0
					while tries < 15 do
						local ent = entities[math.random(1, #entities)]
						if ent and ent.exists and IsAttackable(ent) then
							local d = comp.owner:GetRangeTo(ent)
							towards_any = ent
							if d < 250 and d < dist_250 then towards_250, dist_250 = ent, d end
							break
						end
						tries = tries + 1
					end
					if towards_any then break end
				end
			end

			-- 通道 1：派遣侦察
			if (tick - (save.last_scout_tick or 0)) > scaled_cd and unit_count < scout_limit then
				if towards_any and comp.owner:GetRangeTo(towards_any) > 100 and rnd > 0.6 then
					save.last_scout_tick = tick ed_hive.extra_spawned = 0
					local target_loc = Tool.Copy(towards_any.location)
					Map.Defer(function() if comp.owner.exists and target_loc then
						local s = Map.CreateEntity(bugs_f, "f_triloscout") s:Place(comp.owner)
						local h = s:FindComponent("c_bug_harvest") if h then h.extra_data.home = comp.owner h.extra_data.towards = target_loc end
					end end)
					return comp:SetStateSleep(math.random(4000, 8000))
				end
			end
			-- 通道 2：发起进攻 (250格智能截断)
			if (tick - (save.last_attack_tick or 0)) > (scaled_cd * 0.8) and towards_250 then
				local settings = Map.GetSettings()
				if (settings.peaceful == 3 or dist_250 <= 60) then
					if not IsBugActiveSeason() and rnd > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end
					save.last_attack_tick = tick ed_hive.extra_spawned = 0
					Map.Defer(function() if comp.exists and towards_250.exists then data.components.c_bug_spawn:on_trigger_action(comp, towards_250, true) end end)
					return comp:SetStateSleep(math.random(2000, 4000))
				end
			end
			-- 通道 3：随机自然扩张
			if (tick - (save.last_nest_tick or 0)) > (scaled_cd * 1.5) and rnd < 0.2 then
				local found = Map.FindClosestEntity(comp.owner, 10, function(e) return (e.id == "f_bug_hive" or e.id == "f_bug_hive_large") end, FF_OPERATING|FF_OWNFACTION)
				if not found then save.last_nest_tick = tick ed_hive.extra_spawned = 0 Map.Defer(function() if comp.exists then Map.CreateEntity(bugs_f, "f_bug_hive"):Place(comp.owner.location) end end) return comp:SetStateSleep(math.random(1000, 2000)) end
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	-- 归巢逻辑 (原版避让机制)
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

			-- 极速验位逻辑：解决“盯着满巢发呆”
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

			-- 筑巢并发限流
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

	-- Apply Hooks
	local hooks = {"c_trilobyte_attack", "c_trilobyte_attack_t2", "c_trilobyte_attack_t3", "c_trilobyte_attack1", "c_trilobyte_attack2", "c_trilobyte_attack3", "c_trilobyte_attack4", "c_wasp_attack1", "c_tripodonte1", "c_tetrapuss_attack1", "c_larva_attack1", "c_larva_attack2"}
	for _, n in ipairs(hooks) do if components[n] then components[n].on_update = BugAttackUpdate end end
end
