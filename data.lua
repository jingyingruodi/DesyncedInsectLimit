-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 1.9.6 (Targeting Fix Base 1.9.2 + Persistent Stuck Timer Fix)

local package = ...

function package:init()
	print("[InsectLimit] Applying low-level performance optimizations...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] ERROR: Bug components not found!")
		return
	end

	-- 辅助函数：还原原版季节活跃度判断
	local function IsBugActiveSeason()
		return math.abs(Map.GetYearSeason() - 0.5) < 0.25
	end

	-- 辅助函数：判断实体是否为真正可攻击目标
	local function IsAttackable(e)
		if not e or not e.exists or not e.is_placed then return false end
		local def = e.def
		if e.stealth or e.is_construction or def.immortal or def.is_explorable or def.size == "Mission" then return false end
		if def.type == "DroppedItem" or def.type == "Resource" then return false end
		return true
	end

	-- 【核心重构】：通用的虫群攻击更新逻辑
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner = comp.owner
			-- 判定卡死：路径被阻挡
			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			local ed = comp.extra_data

			if is_stuck then
				if not ed.failed_move_ticks then
					ed.failed_move_ticks = Map.GetTick() + 600 -- 120秒
				elseif ed.failed_move_ticks < Map.GetTick() then
					ed.failed_move_ticks = nil
					-- 强制清除 Reg 1，确保归巢逻辑能顺利执行
					if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end

					if not owner:FindComponent("c_bug_homeless") then
						Map.Defer(function()
							if not comp.exists then return end
							local new_homeless = (owner.health > 200) and owner:AddComponent("c_bug_homeless")
							if new_homeless then new_homeless:Activate() else owner:Destroy() end
						end)
					end
					return
				end
			else
				-- 【持久化修复】：只有在真正顺畅移动时才重置计时器，微小位移或静止不重置
				if not owner.state_path_blocked and owner.is_moving then
					ed.failed_move_ticks = nil
				end
			end
		end
		return data.components.c_turret.on_update(self, comp, cause)
	end

	---------------------------------------------------------------------------
	-- 1. 修改基础生成器逻辑
	---------------------------------------------------------------------------
	c_bug_spawn.on_trigger = function (self, comp, other_entity, force)
		if other_entity.faction.is_player_controlled then
			if force or IsBugActiveSeason() then
				self:on_trigger_action(comp, other_entity, force)
			end
		end
	end

	c_bug_spawn.on_trigger_action = function (self, comp, other_entity, force)
		local owner_faction = comp.faction
		if owner_faction.is_player_controlled then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end

		if comp.id == "c_bug_spawner_large" then
			Map.FindClosestEntity(comp.owner, 10, function(e)
				if e.id ~= "f_bug_hive" then return end
				local c = e:FindComponent("c_bug_spawn")
				self:on_trigger_action(c, other_entity, force)
			end, FF_OPERATING | FF_OWNFACTION)
		end

		if not force and comp.owner:GetRangeTo(other_entity) > 100 then return end

		if not IsAttackable(other_entity) or owner_faction:GetTrust(other_entity) ~= "ENEMY" then
			return
		end

		local extra_data = comp.extra_data
		local ed_bugs = extra_data.bugs
		if not ed_bugs then
			ed_bugs = {}
			extra_data.bugs = ed_bugs
			extra_data.spawned = Map.GetTick() - 901
			extra_data.lvl = 0
			extra_data.extra_spawned = 0
		end

		for i=#ed_bugs,1,-1 do
			if not ed_bugs[i].exists then table.remove(ed_bugs, i) end
		end

		local owner = comp.owner
		if #ed_bugs > 0 then
			for _,bug in ipairs(ed_bugs) do
				bug:FindComponent("c_turret", true):SetRegisterCoord(1, other_entity.location)
				if force then
					bug:SetRegisterEntity(FRAMEREG_GOTO, nil)
					if not bug:FindComponent("c_bug_homeless") then bug:AddComponent("c_bug_homeless", "hidden") end
				end
			end
			return
		end

		local map_tick, ed_spawned, ed_lvl, ed_extra_spawned = Map.GetTick(), extra_data.spawned, extra_data.lvl or 0, extra_data.extra_spawned or 0
		if map_tick - ed_spawned < 900 and not force then return end

		local early_easy = 2 + math.min(Map.GetTotalDays() // 2, 6)
		local max_num = (owner.id == "f_bug_hole" and 1 or early_easy) + ed_extra_spawned
		if StabilityGet then
			local stability = -StabilityGet()
			max_num = max_num + math.max(0, stability // 500)
		end
		max_num = math.min(max_num, owner.def.slots and owner.def.slots.bughole) or 1
		local num = math.random(math.ceil(max_num / 3), max_num)

		local settings = Map.GetSettings()
		local player_faction = other_entity.faction
		local difficulty = settings.difficulty or 1.0

		if force and settings.peaceful == 3 then
			num = math.max(math.ceil(GetPlayerFactionLevel(player_faction) * 0.4) + 1, num)
			local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
			if comp.faction.num_entities > (4000 * pc * difficulty) then num = num // 3 end
		else
			num = math.min((GetPlayerFactionLevel(player_faction) // 3)+1, num)
		end

		local bug_levels = GetBugCountsForLevel(GetPlayerFactionLevel(player_faction), num, force)
		local rewards, spawn_delay, target = 0, 1, other_entity.location
		local loc = owner.location

		for i=#bug_levels,1,-1 do
			if bug_levels[i] > 0 then
				for j=1,bug_levels[i] do
					rewards = rewards + (i * 3)
					local bug_delay = (((spawn_delay % 15) + (math.random(0, 2)*30))*3)+1
					Map.Delay("SpawnFromHive", bug_delay, {
						level = i, force = force, owner = owner, loc = Tool.Copy(loc), target = target, comp = comp,
					})
					spawn_delay = spawn_delay + 1
				end
			end
		end
		extra_data.spawned = map_tick
		extra_data.lvl = ed_lvl + 1

		if (comp.owner.id == "f_bug_hive" or comp.owner.id == "f_bug_hive_large") and ed_extra_spawned < 8 and math.random() <= 0.05 then
			local newbughole = Map.CreateEntity(owner_faction, "f_bug_hole")
			newbughole:Place(math.random(loc.x-4, loc.x+4), math.random(loc.y-4, loc.y+4))
			extra_data.extra_spawned = ed_extra_spawned + 1
		end

		if not extra_data.rewards then
			comp.owner:AddItem("bug_carapace", math.min(rewards, 20))
			extra_data.rewards = rewards
		end
	end

	---------------------------------------------------------------------------
	-- 2. 修改大型生成器逻辑
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end

		local bugs_faction = GetBugsFaction()
		local settings = Map.GetSettings()
		if settings.peaceful == 1 then return comp:SetStateSleep(20000 + math.random(1, 500)) end

		local last_swarm = Map.GetSave().last_swarm or 0
		local map_tick = Map.GetTick()
		if map_tick - last_swarm < 750 then return comp:SetStateSleep(750 - (map_tick - last_swarm) + math.random(1, 50)) end

		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
		if bugs_faction.num_entities > (30000 * pc) then return comp:SetStateSleep(5000 + math.random(1, 200)) end

		local extra_data = comp.extra_data
		if not extra_data.extra_spawned then extra_data.extra_spawned = 0 end
		extra_data.extra_spawned = extra_data.extra_spawned + 1

		local owner = comp.owner
		if extra_data.extra_spawned > 10 then
			local rnd = math.random()
			if rnd < 0.2 then
				local found = Map.FindClosestEntity(owner, 10, function(e)
					return e.id == "f_bug_hive" or e.id == "f_bug_hive_large"
				end, FF_OPERATING | FF_OWNFACTION)
				if not found then
					Map.Defer(function()
						if comp.exists then
							local newhome = Map.CreateEntity(bugs_faction, "f_bug_hive")
							newhome:Place(owner.location)
							comp.extra_data.extra_spawned = 0
						end
					end)
				end
			elseif rnd > 0.3 then
				if not IsBugActiveSeason() and math.random() > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end

				local closest_distance, closest_faction, towards = 9999999
				for _, faction in ipairs(Map.GetFactions()) do
					if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
						local entities = faction.entities
						local test_unit
						local tries = 0
						while tries < 20 do
							local ent = entities[math.random(1, #entities)]
							if ent and ent.exists and not ent.stealth then
								if ent.is_docked then ent = ent.docked_garage end
								if IsAttackable(ent) then
									test_unit = ent
									break
								end
							end
							tries = tries + 1
						end

						if test_unit then
							local d = owner:GetRangeTo(test_unit)
							if d < 250 and d < closest_distance then
								closest_faction, closest_distance, towards = faction, d, test_unit
							end
						end
					end
				end

				if closest_faction then
					if ((settings.peaceful == 2 and closest_distance > 20) or (closest_distance > 150)) and (bugs_faction.num_entities < (10000 * pc * (settings.difficulty or 1.0))) then
						if math.random() > 0.6 then
							Map.Defer(function()
								if not owner.exists then return end
								local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
								scout:Place(owner)
								local harvest_comp = scout:FindComponent("c_bug_harvest")
								harvest_comp.extra_data.home = owner
								if towards and towards.exists then
									local tloc = towards.location
									if tloc.x ~= 0 or tloc.y ~= 0 then harvest_comp.extra_data.towards = Tool.Copy(tloc) end
								end
							end)
						end
						comp.extra_data.extra_spawned = 0
						return comp:SetStateSleep(math.random(4000, 8000))
					elseif (settings.peaceful == 3 or closest_distance <= 60) and closest_distance < 250 then
						local attack_target = closest_faction.home_entity
						if not IsAttackable(attack_target) or owner:GetRangeTo(attack_target) > 250 then
							attack_target = towards
						end

						if attack_target and attack_target.exists then
							Map.GetSave().last_swarm = Map.GetTick()
							Map.Defer(function()
								if comp.exists and attack_target.exists then
									self:on_trigger_action(comp, attack_target, true)
									comp.extra_data.extra_spawned = 0
								end
							end)
						end
					end
				end
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	---------------------------------------------------------------------------
	-- 3. 修改筑巢 AI (c_bug_harvest)
	---------------------------------------------------------------------------
	c_bug_harvest.on_update = function(self, comp, cause)
		local owner = comp.owner
		local data = comp.extra_data
		local target, home = data.target, data.home

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
			target = Map.FindClosestEntity(owner, 8, function(e)
				if IsResource(e) and GetResourceHarvestItemId(e) == "silica" and e:GetRangeTo(home) > 20 then return true end
				return false
			end, FF_RESOURCE)

			if target then
				data.target, data.state = target, "deploy"
			else
				data.state, data.wandertimes = "wander", (data.wandertimes or 0) + 1
				if data.wandertimes > 30 then Map.Defer(function() if owner.exists then owner:Destroy() end end) return comp:SetStateSleep(1) end
			end
		elseif state == "deploy" then
			if not owner.state_path_blocked then
				if comp:RequestStateMove(target, 3) then return end
			end
			data.target = nil
			local hive_count = 0
			Map.FindClosestEntity(owner, 35, function(e)
				if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then
					hive_count = hive_count + 1
					if hive_count >= 2 then return true end
				end
			end, FF_OPERATING | FF_OWNFACTION)

			if hive_count >= 2 then
				data.state = "wander"
				return comp:SetStateSleep(200 + math.random(1, 50))
			end

			Map.Defer(function()
				if comp.exists then
					local newhome = Map.CreateEntity(GetBugsFaction(), (math.random() > 0.8) and "f_bug_hive" or "f_bug_hive_large")
					newhome:Place(owner.location)
					owner:Destroy()
				end
			end)
			return comp:SetStateSleep(10 + math.random(1, 10))
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

	---------------------------------------------------------------------------
	-- 4. 虫群攻击卡死判定修复
	---------------------------------------------------------------------------
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] Optimization 1.9.6 complete. Homing logic reset to stable 1.9.2 with improved stuck detection.")
end
