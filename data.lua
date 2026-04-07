-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 1.8.4 (Stealth Logic Fix & TPS Load Balancing)

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

	---------------------------------------------------------------------------
	-- 1. 修改基础生成器逻辑 (c_bug_spawn)
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

		-- 性能截断：不响应远距离触发（除非强制进攻指令）
		if not force and comp.owner:GetRangeTo(other_entity) > 100 then return end

		-- 隐身实体不触发生成器
		if not other_entity.faction.is_player_controlled or owner_faction:GetTrust(other_entity) ~= "ENEMY" or other_entity.stealth or other_entity.is_construction then
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
		local player_level = GetPlayerFactionLevel(other_entity.faction)
		local difficulty = settings.difficulty or 1.0

		if force and settings.peaceful == 3 then
			num = math.max(math.ceil(player_level * 0.4) + 1, num)
			-- 动态上限缩放
			local pop_limit = 4000 * (Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1) * difficulty
			if comp.faction.num_entities > pop_limit then num = num // 3 end
		else
			num = math.min((player_level // 3)+1, num)
		end

		local bug_levels = GetBugCountsForLevel(player_level, num, force)
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
	-- 2. 修改大型生成器逻辑 (c_bug_spawner_large)
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then
			Map.Defer(function() if comp.exists then comp:Destroy() end end)
			return
		end

		local bugs_faction = GetBugsFaction()
		local settings = Map.GetSettings()
		local peaceful = settings.peaceful
		if peaceful == 1 then return comp:SetStateSleep(20000 + math.random(1, 500)) end

		-- 全局攻势冷却 (尊重实验版逻辑)
		local last_swarm = Map.GetSave().last_swarm or 0
		local map_tick = Map.GetTick()
		if map_tick - last_swarm < 750 then
			return comp:SetStateSleep(750 - (map_tick - last_swarm) + math.random(1, 50))
		end

		-- 上限判定
		local current_total = bugs_faction.num_entities
		local max_total = 30000 * (Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1)
		if current_total > max_total then return comp:SetStateSleep(5000 + math.random(1, 200)) end

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
				-- 采用采样搜索以优化性能
				for _, faction in ipairs(Map.GetFactions()) do
					if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
						local entities = faction.entities
						local test_entity
						local tries = 0
						-- 采样逻辑优化：增加对隐身实体的过滤
						while tries < 5 do
							test_entity = entities[math.random(1, #entities)]
							if test_entity and test_entity.exists and not test_entity.is_construction and not test_entity.stealth then
								if test_entity.is_docked then test_entity = test_entity.docked_garage end
								if test_entity and test_entity.is_placed and not test_entity.stealth then break end
							end
							test_entity = nil
							tries = tries + 1
						end

						if test_entity then
							local d = owner:GetRangeTo(test_entity)
							-- 探测剪枝：250 格感应范围
							if d < 250 and d < closest_distance then
								closest_faction, closest_distance, towards = faction, d, test_entity
							end
						end
					end
				end

				if closest_faction then
					local difficulty = settings.difficulty or 1.0
					if ((peaceful == 2 and closest_distance > 20) or (closest_distance > 150)) and (current_total < (10000 * difficulty)) then
						-- 派遣侦察虫
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
					elseif (peaceful == 3 or closest_distance <= 60) and closest_distance < 250 then
						-- 【目标选择策略优化】：
						-- 1. 优先尝试主基地，但主基地必须在感应范围内且不可隐身
						local attack_target = closest_faction.home_entity
						if not attack_target or not attack_target.exists or attack_target.is_construction or attack_target.stealth or owner:GetRangeTo(attack_target) > 250 then
							-- 2. 如果主基地不可见或太远，则攻击刚才感应到的那个实体（towards 已确保不隐身）
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
		-- TPS Load Balancing: 唤醒时间随机抖动，避免大量蜂巢在同一 Tick 运行
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
			-- 密度探测
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
	-- 4. 修改虫群攻击逻辑 (c_trilobyte_attack)
	---------------------------------------------------------------------------
	c_trilobyte_attack.on_update = function(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local failed_move = cause & CC_FINISH_MOVE ~= 0 and comp.owner.state_path_blocked
			if failed_move or comp.owner.state_custom_1 then
				local ed = comp.extra_data
				if not ed.failed_move then
					ed.failed_move = Map.GetTick() + 900
				elseif ed.failed_move < Map.GetTick() then
					comp:SetRegister(1)
					if not comp.owner:FindComponent("c_bug_homeless") then
						Map.Defer(function()
							if not comp.exists then return end
							local new_homeless = (comp.owner.health > 200) and comp.owner:AddComponent("c_bug_homeless")
							if new_homeless then new_homeless:Activate() else comp.owner:Destroy() end
						end)
					end
					return
				end
			end
		end
		return data.components.c_turret.on_update(self, comp, cause)
	end

	print("[InsectLimit] Optimization 1.8.4 complete. Stealth-aware targeting enabled.")
end
