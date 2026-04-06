-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 1.7.9 (Fix: Scout (0,0) clump, Added pathfinding distance pruning, Optimized Scout AI)

local package = ...

function package:init()
	print("[InsectLimit] Initializing safety-first bug logic override...")

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

	-- 辅助函数：仅统计非建筑移动单位
	local function GetMobileBugCount()
		local bugs_faction = GetBugsFaction()
		local count = 0
		for _, e in ipairs(bugs_faction.entities) do
			if e.exists and not e.is_construction and e.has_movement then
				count = count + 1
			end
		end
		return count
	end

	-- 辅助函数：检查一个派系是否真的有“可被攻击”的实体
	local function FactionHasAttackableEntities(faction)
		if faction.num_entities <= 0 then return false end
		for _, e in ipairs(faction.entities) do
			if e.exists and not e.is_construction then
				return true
			end
		end
		return false
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
			end, FF_OPERATING)
		end

		-- 距离截断：不响应太远处的触发（防止长距离寻路）
		if not force and comp.owner:GetRangeTo(other_entity) > 100 then
			return
		end

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
					if not bug:FindComponent("c_bug_homeless") then
						bug:AddComponent("c_bug_homeless", "hidden")
					end
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
			stability = stability // 500
			max_num = max_num + math.max(0, stability)
		end
		max_num = math.min(max_num, owner.def.slots and owner.def.slots.bughole) or 1
		local num = math.random(math.ceil(max_num / 3), max_num)

		local loc = owner.location
		local other_faction = other_entity.faction
		local other_home =  other_faction.home_location
		local distloc = { x = loc.x, y = loc.y }
		if other_home then
			distloc.x = loc.x - other_home.x
			distloc.y = loc.y - other_home.y
		end
		local dist = (distloc.x*distloc.x)+(distloc.y*distloc.y)

		local settings = Map.GetSettings()
		local plateau_level = settings.plateau_level
		local tile_h = Map.GetElevation(loc.x, loc.y)
		if tile_h < plateau_level then dist = 0 end

		local player_level = GetPlayerFactionLevel(other_faction)
		local difficulty = settings.difficulty or 1.0

		if dist > 30000 then player_level = player_level + 5
		elseif dist > 90000 then player_level = player_level + 10
		elseif dist > 122500 then player_level = player_level + 20
		end

		if force and settings.peaceful == 3 then
			local ramp = 0.4
			local level = math.ceil(player_level * ramp)
			local num_bugs_limit = level+1
			num = math.max(num_bugs_limit, num)
			if GetMobileBugCount() > (4000 * difficulty) then num = num // 3 end
		else
			num = math.min((player_level // 3)+1, num)
		end

		local bug_levels = GetBugCountsForLevel(player_level, num, force)
		local rewards = 0
		local spawn_delay = 1
		local num_bugs_counter = 0

		local allbugs = 0
		for i=1,#bug_levels do allbugs = allbugs + bug_levels[i] end
		local num_waves = (allbugs // 30)+1
		local target = other_entity.location

		for i=#bug_levels,1,-1 do
			if bug_levels[i] > 0 then
				for j=1,bug_levels[i] do
					rewards = rewards + (i * 3)
					num_bugs_counter = num_bugs_counter + 1
					local bug_delay = (((spawn_delay % 15) + ((math.random(1, num_waves)-1)*30))*3)+1
					if bug_delay < 5 then bug_delay = 1 end
					Map.Delay("SpawnFromHive", bug_delay, {
						level = i,
						force = force,
						owner = owner,
						loc = Tool.Copy(loc),
						target = target,
						comp = comp,
					})
					spawn_delay = spawn_delay + 1
				end
			end
		end
		extra_data.spawned = map_tick
		extra_data.lvl = ed_lvl + 1

		if (comp.owner.id == "f_bug_hive" or comp.owner.id == "f_bug_hive_large") and ed_extra_spawned < 8 and math.random() <= 0.05 then
			local x, y = owner.location.x, owner.location.y
			local newbughole = Map.CreateEntity(owner_faction, "f_bug_hole")
			newbughole:Place(math.random(x-4, x+4), math.random(y-4, y+4))
			newbughole:PlayEffect("fx_digital_in")
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
		if peaceful == 1 then return comp:SetStateSleep(20000) end
		if peaceful ~= 3 and not settings.creep then return comp:SetStateSleep(10000) end

		local mobile_count = GetMobileBugCount()
		if mobile_count > 30000 then return comp:SetStateSleep(1000) end

		local extra_data = comp.extra_data
		if not extra_data.extra_spawned then extra_data.extra_spawned = 0 end
		extra_data.extra_spawned = extra_data.extra_spawned + 1

		local owner = comp.owner
		if extra_data.extra_spawned > 10 then
			local rnd = math.random()
			if rnd < 0.2 then
				local hivecount = 0
				local found = Map.FindClosestEntity(comp.owner, 5, function(enemy)
					if enemy.id == "f_bug_hive" or enemy.id == "f_bug_hive_large" then
						hivecount = hivecount + 1
						if hivecount > 5 then return true end
					end
				end, FF_OPERATING)
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
				if not IsBugActiveSeason() and math.random() > 0.2 then
					return comp:SetStateSleep(math.random(1000, 2000))
				end

				local closest_distance, closest_faction, towards = 9999999
				for _, faction in ipairs(Map.GetFactions()) do
					if faction.is_player_controlled and FactionHasAttackableEntities(faction) and bugs_faction:GetTrust(faction) == "ENEMY" then
						local newdist = 9999998
						local valid_targets = {}
						-- 增加探测范围限制，减少对极远处玩家的扫描负担
						for _, ent in ipairs(faction.entities) do
							if ent.exists and not ent.is_construction and owner:GetRangeTo(ent) < 250 then
								table.insert(valid_targets, ent)
							end
						end

						if #valid_targets > 0 then
							local test_entity = valid_targets[math.random(1, #valid_targets)]
							newdist = owner:GetRangeTo(test_entity)
							if newdist < closest_distance then
								closest_faction = faction
								closest_distance = newdist
								towards = test_entity
							end
						end
					end
				end

				if closest_faction then
					local difficulty = settings.difficulty or 1.0
					if ((peaceful == 2 and closest_distance > 20) or (closest_distance > 150)) and (mobile_count < (10000 * difficulty)) then
						local rnd_scout = math.random()
						if rnd_scout > 0.6 then
							Map.Defer(function()
								if not owner.exists then return end
								local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
								scout:Place(owner)
								local harvest_comp = scout:FindComponent("c_bug_harvest")
								harvest_comp.extra_data.home = owner
								-- 修复：严谨校验 towards 坐标，防止 (0,0) 扎堆
								if towards and towards.exists then
									local tloc = towards.location
									if tloc.x ~= 0 or tloc.y ~= 0 then
										harvest_comp.extra_data.towards = Tool.Copy(tloc)
									end
								elseif closest_faction.home_location then
									local hloc = closest_faction.home_location
									if hloc.x ~= 0 or hloc.y ~= 0 then
										harvest_comp.extra_data.towards = Tool.Copy(hloc)
									end
								end
							end)
						end
						comp.extra_data.extra_spawned = 0
						return comp:SetStateSleep(math.random(4000,8000))
					elseif peaceful == 3 or (closest_distance <= 60) then
						local ent = closest_faction.home_entity
						if not ent or ent.is_construction then
							for _,e in ipairs(closest_faction.entities) do
								if e.exists and e.is_placed and not e.is_construction then
									ent = e
									break
								end
							end
						end
						-- 增加响应距离截断，防止远距离进攻寻路
						if ent and not ent.is_construction and owner:GetRangeTo(ent) < 150 then
							Map.Defer(function()
								if comp.exists and ent.exists then
									self:on_trigger_action(comp, ent, true)
									comp.extra_data.extra_spawned = 0
								end
							end)
						end
					end
				end
			end
		end
		return comp:SetStateSleep(math.random(300,600))
	end

	---------------------------------------------------------------------------
	-- 3. 修改筑巢 AI (c_bug_harvest)
	---------------------------------------------------------------------------
	c_bug_harvest.on_update = function(self, comp, cause)
		local owner = comp.owner
		local data = comp.extra_data
		local target = data.target
		local home = data.home

		if not home or not home.exists or not home.is_placed then
			Map.Defer(function() if owner.exists then owner:Destroy() end end)
			return comp:SetStateSleep(1)
		end

		local home_loc = home.location
		if target and not target.exists then
			data.state = "wander"
			data.target = nil
			return comp:SetStateSleep(1)
		end
		if owner.is_moving then return comp:SetStateSleep(5) end

		local state = data.state or "idle"
		if not target and state ~= "idle" and state ~= "wander" then
			data.state = "wander"
			return
		end

		if state == "idle" then
			-- 限制资源寻找范围，减少寻路压力
			target = Map.FindClosestEntity(owner, 8, function(e)
				if home and home.exists and home.is_placed then
					if IsResource(e) and GetResourceHarvestItemId(e) == "silica" and e:GetRangeTo(home_loc) > 20 then
						return true
					end
				end
				return false
			end, FF_RESOURCE)

			if target then
				data.target = target
				data.state = "deploy"
			else
				data.state = "wander"
				data.wandertimes = (data.wandertimes or 1) + 1
				if data.wandertimes > 50 then
					Map.Defer(function() owner:Destroy() end)
					return comp:SetStateSleep(1)
				end
			end
		elseif state == "deploy" then
			if not owner.state_path_blocked then
				if comp:RequestStateMove(target, 3) then return end
			end

			data.target = nil
			local hive_count = 0
			-- 优化：使用局部范围检测替代全局计数
			for _, e in ipairs(Map.GetEntitiesInRange(owner, 35, FF_OPERATING)) do
				if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then
					hive_count = hive_count + 1
				end
			end

			if hive_count >= 3 then
				data.state = "wander"
				return comp:SetStateSleep(10)
			end

			Map.Defer(function()
				if comp.exists then
					local newhome = Map.CreateEntity(GetBugsFaction(), (math.random() > 0.8) and "f_bug_hive" or "f_bug_hive_large")
					newhome:Place(owner.location)
					comp.extra_data.extra_spawned = 0
					owner:Destroy()
				end
			end)
			return comp:SetStateSleep(10)
		elseif state == "wander" then
			local loc = owner.location
			-- 修正 wander 逻辑，防止 towards 指向 (0,0)
			if data.towards and (data.towards.x ~= 0 or data.towards.y ~= 0) then
				local tloc = data.towards
				local dx = math.min(math.max((tloc.x - loc.x) // 3, -50), 50)
				local dy = math.min(math.max((tloc.y - loc.y) // 3, -50), 50)
				loc.x = loc.x + dx + math.random(-5, 5)
				loc.y = loc.y + dy + math.random(-5, 5)
			else
				loc.x = loc.x + math.random(-15, 15)
				loc.y = loc.y + math.random(-15, 15)
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
				else
					if ed.failed_move < Map.GetTick() then
						comp:SetRegister(1)
						local homeless = comp.owner:FindComponent("c_bug_homeless")
						if not homeless then
							ed.failed_move = nil
							Map.Defer(function()
								if not comp.exists then return end
								local new_homeless = (comp.owner.health > 200) and comp.owner:AddComponent("c_bug_homeless")
								if new_homeless then
									new_homeless:Activate()
								else
									comp.owner:Destroy()
								end
							end)
						else
							homeless:Activate()
						end
						return
					end
				end
			end
		end
		return data.components.c_turret.on_update(self, comp, cause)
	end

	print("[InsectLimit] Logic override successful. (0,0) fix and pathing pruning applied.")
end
