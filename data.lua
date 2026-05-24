-- InsectLimit Mod - Performance & Intelligent Combat Fixes
-- Version: 2.9.1 (CD-Gated Cadence + Distance-Decay + Dynamic Scout Suppress)
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

	local abs_limit = 12000 + (total_pc - 1) * 1500 + (active_pc - 1) * 500
	local soft_limit = 3000 + (total_pc - 1) * 500 + (active_pc - 1) * 250
	local scout_limit = 6000 + (total_pc - 1) * 750 + (active_pc - 1) * 250

	bugs_ed.abs_limit = abs_limit
	bugs_ed.soft_limit = soft_limit
	bugs_ed.scout_limit = scout_limit

	print(string.format("[InsectLimit] Heartbeat -> Players: %d/%d (Alive/Total) | BOTS: %d/%d (Soft: %d, Scout: %d) | Assets: %d",
		active_pc, total_pc, bot_count, abs_limit, soft_limit, scout_limit, total_assets))
	Map.Delay("DiagnosticHeartbeat", 150 + math.random(-10, 10))
end

-- 【关键机制】：病毒致死执行器
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
			print("[InsectLimit] SYSTEM STARTUP -> v2.9.1 DynSuppress Deployed")
			Map.Delay("DiagnosticHeartbeat", 5)
		end
	end
end

function package:init()
print("[InsectLimit] Initializing v2.9.1 - CD-Gated + Dist-Decay + DynSuppress...")

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

			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			if is_stuck then
				if not ed.failed_move_ticks then ed.failed_move_ticks = Map.GetTick() + 900 + math.random(-10, 10)
				elseif ed.failed_move_ticks < Map.GetTick() then
					ed.failed_move_ticks = nil
					if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end
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

	-- 波次逻辑：支持自卫反击标志
	components.c_bug_spawn.on_trigger_action = function (self, comp, other_entity, force, is_link, retaliate)
		local bugs_f = comp.faction
		if bugs_f.is_player_controlled then Map.Defer(function() if comp.exists then comp:Destroy() end end) return end

		if comp.id == "c_bug_spawner_large" then
			local link_count = 0
			Map.FindClosestEntity(comp.owner, 10, function(e)
				if not retaliate and link_count >= 5 then return true end
				if e.id ~= "f_bug_hive" then return end
				local c = e:FindComponent("c_bug_spawn")
				if c then self:on_trigger_action(c, other_entity, force, true, retaliate) link_count = link_count + 1 end
			end, FF_OPERATING)
		end

		if not other_entity.faction.is_player_controlled or bugs_f:GetTrust(other_entity) ~= "ENEMY" or other_entity.stealth then return end

		local ed = comp.extra_data
		if not ed.bugs then ed.bugs, ed.spawned, ed.lvl, ed.extra_spawned = {}, Map.GetTick() - 901, 0, 0 end
		for i=#ed.bugs,1,-1 do if not ed.bugs[i].exists then table.remove(ed.bugs, i) end end

		for i=#ed.bugs,1,-1 do
            if not ed.bugs[i].exists then table.remove(ed.bugs, i) end
        end

        -------------------------------------------------
        -- 第一优先级：已有驻军立即反击
        -------------------------------------------------
        if #ed.bugs > 0 then
            for _,bug in ipairs(ed.bugs) do
                if bug.exists then
                    local atk = bug:FindComponent("c_turret", true)
                    if atk then
                        atk:SetRegisterCoord(1, other_entity.location)
                    end

                    if force and not bug:FindComponent("c_bug_homeless") then
                        bug:SetRegisterEntity(FRAMEREG_GOTO, nil)
                        bug:AddComponent("c_bug_homeless", "hidden")
                    end
                end
            end
            return
        end

		local tick = Map.GetTick()
        if tick - ed.spawned < 900 then
            return
        end

		local early_easy = 2 + math.min(Map.GetTotalDays() // 2, 6)
		local max_num = (comp.owner.id == "f_bug_hole" and 1 or early_easy) + ed.extra_spawned
		if StabilityGet then max_num = max_num + math.max(0, (-StabilityGet() // 500)) end
		max_num = math.min(max_num, comp.owner.def.slots and comp.owner.def.slots.bughole or 1)
		local num = math.random(math.ceil(max_num / 3), max_num)

		local other_faction = other_entity.faction
		local player_level = GetPlayerFactionLevel(other_faction)
		local loc = comp.owner.location
		local dist = 0
		if other_faction.home_location then
			local dx, dy = loc.x - other_faction.home_location.x, loc.y - other_faction.home_location.y
			dist = dx*dx + dy*dy
		end
		if Map.GetElevation(loc.x, loc.y) < Map.GetSettings().plateau_level then dist = 0 end
		if dist > 30000 then player_level = player_level + 5
		elseif dist > 90000 then player_level = player_level + 10
		elseif dist > 122500 then player_level = player_level + 20 end

		local settings = Map.GetSettings()
		local final_force = force
		local spawn_owner = nil

		if force and settings.peaceful == 3 and not retaliate then
			num = math.max(math.ceil(player_level * 0.4) + 1, num)
			local unit_count, soft, abs = bugs_f.extra_data.unit_count or 0, bugs_f.extra_data.soft_limit or 4000, bugs_f.extra_data.abs_limit or 12000
			if unit_count > soft then
				local intensity = math.max(0.33, 1.0 - (unit_count - soft) / (abs - soft))
				num = math.floor(num * intensity)
			end
			spawn_owner = nil
		else
			num = math.min((player_level // 3) + 1, num)
			final_force = false
			spawn_owner = comp.owner
		end

		local bug_levels = GetBugCountsForLevel(player_level, num, final_force)
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
						level = i, force = final_force, owner = spawn_owner, loc = Tool.Copy(loc), target = target_loc, comp = comp, faction = bugs_f
					})
					spawn_delay = spawn_delay + 1
				end
			end
		end
		ed.spawned, ed.lvl = tick, ed.lvl + 1
		if comp.owner.id == "f_bug_hive" and ed.extra_spawned < 8 and math.random() <= 0.05 then
			local x, y = comp.owner.location.x, comp.owner.location.y
			local nb = Map.CreateEntity(bugs_f, "f_bug_hole") nb:Place(math.random(x-4, x+4), math.random(y-4, y+4))
			nb:PlayEffect("fx_digital_in") ed.extra_spawned = ed.extra_spawned + 1
		end
		if not ed.rewards then comp.owner:AddItem("bug_carapace", math.min(all_bugs_count, 20)) ed.rewards = all_bugs_count end
	end

	-- 受击响应
	components.c_bug_spawn.on_take_damage = function(self, comp, amount, damager)
		if not damager or not damager.exists then return end
		Map.Defer(function()
			if comp.exists and damager.exists then
				self:on_trigger_action(comp, damager, false, false, true)
			end
		end)
	end

	-- 大型蜂巢行为 (深度逻辑解耦：完全分离进攻与侦察的目标、ID与账本)
	-- v2.9.1: CD门控预扫描——仿原版机制，CD期间不推进extra_spawned计数器
	-- 原版全局CD未到时extra_spawned不递增；本模组改为按玩家势力独立判定
	components.c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000 + math.random(-10, 10)) end

		local bugs_f = GetBugsFaction()
		local bugs_ed = bugs_f.extra_data
		local unit_count = bugs_ed.unit_count or 0
		if unit_count > (bugs_ed.abs_limit or 12000) then return comp:SetStateSleep(1000 + math.random(-10, 10)) end

		local tick, save = Map.GetTick(), Map.GetSave()
		local nest_ready = (tick - (save.last_nest_tick or 0)) > (1000 + math.random(-10, 10))

		-- 【CD门控预扫描】：若所有玩家势力均在CD中且无扩张需求，
		-- 则仿原版行为不递增extra_spawned，休眠至最近CD到期
		-- 侦察CD = 700 + 侦察抑制值（进攻越频繁抑制越高，随时间衰减）
		local f_atk_ticks_pre = save.f_attack_ticks or {}
		local f_sct_ticks_pre = save.f_scout_ticks or {}
		-- 【侦察抑制值】：进攻成功+750，每tick衰减1，上限1400（侦察CD最大2100）
		local sct_suppress_val = save.f_sct_suppress_val or {}
		local sct_suppress_tick = save.f_sct_suppress_tick or {}
		local function GetSctSuppress(f_id)
			local elapsed = tick - (sct_suppress_tick[f_id] or tick)
			return math.max(0, (sct_suppress_val[f_id] or 0) - elapsed)
		end
		local any_ready = nest_ready  -- 扩张需求可绕过CD门控
		local min_cd_remain = 999999

		if not any_ready then
			local factions_pre = Map.GetFactions()
			for _, faction in ipairs(factions_pre) do
				if faction and faction.is_player_controlled and faction.num_entities > 0
				   and bugs_f:GetTrust(faction) == "ENEMY" then
					local f_id = faction.id
					local atk_remain = 700 - (tick - (f_atk_ticks_pre[f_id] or 0))
					local sct_suppress = GetSctSuppress(f_id)
					local sct_remain = (700 + sct_suppress) - (tick - (f_sct_ticks_pre[f_id] or 0))
					if atk_remain <= 0 or sct_remain <= 0 then
						any_ready = true
						break
					end
					if atk_remain < min_cd_remain then min_cd_remain = atk_remain end
					if sct_remain < min_cd_remain then min_cd_remain = sct_remain end
				end
			end
		end

		if not any_ready then
			-- 所有玩家势力CD均未到期：休眠至最近CD到期（仿原版time_between+1行为）
			return comp:SetStateSleep(math.max(5, math.min(min_cd_remain + 1, 300) + math.random(-5, 5)))
		end

		local ed_hive = comp.extra_data
		ed_hive.extra_spawned = (ed_hive.extra_spawned or 0) + 1

		if ed_hive.extra_spawned > 10 then
			local rnd = math.random()
			-- 【逻辑分离变量】：彻底解决“张冠李戴”污染
			local atk_target, atk_f_id, atk_dist = nil, nil, 9999999
			local sct_target, sct_f_id = nil, nil

            local factions = Map.GetFactions()
            local f_count = #factions

            if f_count > 0 then
				local f_atk_ticks = save.f_attack_ticks or {}
				local f_sct_ticks = save.f_scout_ticks or {}
                local f_start = ((comp.owner.key + tick) % f_count) + 1
                local forward = (tick % 2 == 0)
				local any_action_possible = false

                for i = 1, f_count do
                    local f_idx = forward and ((f_start + i - 2) % f_count + 1) or ((f_start - i + f_count) % f_count + 1)
                    local faction = factions[f_idx]

					if faction and faction.is_player_controlled and faction.num_entities > 0 and bugs_f:GetTrust(faction) == "ENEMY" then
						local f_id = faction.id
						-- 独立判定两个类型的 CD（侦察CD含动态抑制值）
						local can_atk_f = (tick - (f_atk_ticks[f_id] or 0)) > (700 + math.random(-10, 10))
						local sct_suppress_ck = GetSctSuppress(f_id)
						local can_sct_f = (tick - (f_sct_ticks[f_id] or 0)) > (700 + sct_suppress_ck + math.random(-10, 10)) and (unit_count < (bugs_ed.scout_limit or 6000))
						-- DEBUG: print(string.format("[InsectLimit] CD-CHECK | f=%s | atk=%s sct=%s(supp=%d)", tostring(f_id), tostring(can_atk_f), tostring(can_sct_f), sct_suppress_ck))

						if can_atk_f or can_sct_f then
							any_action_possible = true
							local home, dice = faction.home_entity, (math.random() > 0.5)

							-- 寻敌计算：采样寻找
							if dice and home and home.exists and IsAttackable(home) then
								local d = comp.owner:GetRangeTo(home)
								if can_atk_f and d < 250 then atk_target, atk_f_id, atk_dist = home, f_id, d end
								if can_sct_f and d > 100 and not sct_target then sct_target, sct_f_id = home, f_id end
							end

							if (not atk_target) or (not sct_target) then
								local entities = faction.entities
								local e_count = #entities
								if e_count > 0 then
									for try = 1, 15 do
										local ent = entities[math.random(1, e_count)]
										if ent and ent.exists and IsAttackable(ent) then
											local d = comp.owner:GetRangeTo(ent)
											-- 进攻目标锁定
											if can_atk_f and d < 250 and d < atk_dist then
												atk_target, atk_f_id, atk_dist = ent, f_id, d
											end
											-- 侦察目标锁定 (抽到 100格以外)
											if can_sct_f and d > 100 and not sct_target then
												sct_target, sct_f_id = ent, f_id
											end
											if atk_target and d < 250 then break end
										end
									end
								end
							end

							-- 补漏
							if not atk_target and not sct_target and home and home.exists and IsAttackable(home) then
								local d = comp.owner:GetRangeTo(home)
								if can_atk_f and d < 250 then atk_target, atk_f_id, atk_dist = home, f_id, d end
								if can_sct_f and d > 100 then sct_target, sct_f_id = home, f_id end
							end

							if atk_target or sct_target then break end
						end
                    end
                end

				if not any_action_possible and not nest_ready then
					return comp:SetStateSleep(300 + math.random(-10, 10))
				end
            end

			-- --- 执行决策（双轨完全隔离） ---
			-- 1. 进攻执行 (仅使用 atk_f_id)
			if atk_target and atk_f_id then
				-- 【距离衰减成功率】：100格内必成功，250格仅30%，线性插值
				-- 失败不消耗CD，重置计数器，进入下一周期
				if atk_dist > 100 then
					local atk_prob = 1.0 - (atk_dist - 100) * 0.7 / 150.0
					if math.random() > atk_prob then
						ed_hive.extra_spawned = 0
						return comp:SetStateSleep(math.random(290, 310))
					end
				end
				if not IsBugActiveSeason() and rnd > 0.1 then return comp:SetStateSleep(math.random(1990, 2010)) end
				ed_hive.extra_spawned = 0
				-- 【侦察抑制值更新】：进攻成功追加750抑制（上限1400），随时间自然衰减
				-- 进攻越频繁→抑制越高→侦察扩张越消极，实现自调节负反馈
				local cur_suppress = GetSctSuppress(atk_f_id)
				local new_suppress = math.min(1400, cur_suppress + 750)
				sct_suppress_val[atk_f_id] = new_suppress
				sct_suppress_tick[atk_f_id] = tick
				save.f_sct_suppress_val = sct_suppress_val
				save.f_sct_suppress_tick = sct_suppress_tick
				--print(string.format("[InsectLimit] ATK→SUPPRESS | faction=%s | +750 | %d→%d | scoutCD=%.0ft",
				--	tostring(atk_f_id), cur_suppress, new_suppress, 700.0 + new_suppress))
				local f_atk_ticks = save.f_attack_ticks or {}
				f_atk_ticks[atk_f_id] = tick -- 精准上 CD
				save.f_attack_ticks = f_atk_ticks
				Map.Defer(function() if comp.exists and atk_target.exists then data.components.c_bug_spawn:on_trigger_action(comp, atk_target, true, false, false) end end)
				return comp:SetStateSleep(math.random(1990, 2010))
			end

			-- 2. 侦察执行 (仅使用 sct_f_id)
			if sct_target and sct_f_id and rnd > 0.6 then
				ed_hive.extra_spawned = 0
				local f_sct_ticks = save.f_scout_ticks or {}
				f_sct_ticks[sct_f_id] = tick -- 精准上 CD
				save.f_scout_ticks = f_sct_ticks
				local target_loc = Tool.Copy(sct_target.location)
				Map.Defer(function() if comp.owner.exists and target_loc then
					local s = Map.CreateEntity(bugs_f, "f_triloscout") s:Place(comp.owner)
					local h = s:FindComponent("c_bug_harvest") if h then h.extra_data.home = comp.owner h.extra_data.towards = target_loc end
				end end)
				return comp:SetStateSleep(math.random(3990, 4010))
			end

			-- 3. 扩张
			if nest_ready and rnd < 0.2 then
				local found = Map.FindClosestEntity(comp.owner, 10, function(e) return (e.id == "f_bug_hive" or e.id == "f_bug_hive_large") end, FF_OPERATING|FF_OWNFACTION)
				if not found then save.last_nest_tick = tick ed_hive.extra_spawned = 0 Map.Defer(function() if comp.exists then Map.CreateEntity(bugs_f, "f_bug_hive"):Place(comp.owner.location) end end) return comp:SetStateSleep(math.random(990, 1010)) end
			end
		end
		return comp:SetStateSleep(math.random(290, 310))
	end

	-- 归巢逻辑：全量随机化
	if components.c_bug_homeless then
		components.c_bug_homeless.on_update = function(self, comp, cause)
			local owner, ed = comp.owner, comp.extra_data
			if owner:FindComponent("c_bug_harvest") then owner:Destroy(false) return end
			local attack_comp = owner:FindComponent("c_turret", true)
			if attack_comp and not owner.state_path_blocked then
				local ent = attack_comp:GetRegisterEntity(1) or attack_comp:GetRegisterEntity(2)
				local coord = attack_comp:GetRegisterCoord(1)
				if attack_comp.is_working or ent or (coord and owner:GetRangeTo(coord) > 5) then return comp:SetStateSleep(300 + math.random(-10, 10)) end
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
			if owner:GetRegisterEntity(FRAMEREG_GOTO) then return comp:SetStateSleep(30 + math.random(-5, 5)) end
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

	components.c_bug_harvest.on_update = function(self, comp, cause)
		local owner, data = comp.owner, comp.extra_data
		local target, home = data.target, data.home
		if not home or not home.exists then Map.Defer(function() if owner.exists then owner:Destroy() end end) return comp:SetStateSleep(1) end
		if target and not target.exists then data.state, data.target = "wander", nil return comp:SetStateSleep(1) end
		if owner.is_moving then return comp:SetStateSleep(5) end
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
			if hive_count >= 4 then data.state = "wander" return comp:SetStateSleep(200 + math.random(-10, 10)) end
			local save = Map.GetSave()
			if (Map.GetTick() - (save.last_nest_tick or 0)) < 100 then data.state = "wander" return comp:SetStateSleep(100 + math.random(-10, 10)) end
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

	local hooks = {"c_trilobyte_attack", "c_trilobyte_attack_t2", "c_trilobyte_attack_t3", "c_trilobyte_attack1", "c_trilobyte_attack2", "c_trilobyte_attack3", "c_trilobyte_attack4", "c_wasp_attack1", "c_tripodonte1", "c_tetrapuss_attack1", "c_larva_attack1", "c_larva_attack2"}
	for _, n in ipairs(hooks) do if components[n] then components[n].on_update = BugAttackUpdate end end
end
