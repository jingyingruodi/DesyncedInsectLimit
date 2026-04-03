-- InsectLimit Mod - Dedicated Server Compatible
local package = ...

function package:init()
	print("[InsectLimit] Initializing addon logic...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large

	if not c_bug_spawn or not c_bug_spawner_large then
		print("[InsectLimit] ERROR: Bug components not found in data.components!")
		return
	end

	-- 1. 修改基础虫群生成器
	c_bug_spawn.on_trigger_action = function (self, comp, other_entity, force)
		local owner_faction = comp.faction
		if owner_faction.is_player_controlled then return end

		if comp.id == "c_bug_spawner_large" then
			Map.FindClosestEntity(comp.owner, 10, function(e)
				if e.id ~= "f_bug_hive" then return end
				local c = e:FindComponent("c_bug_spawn")
				self:on_trigger_action(c, other_entity, force)
			end, FF_OPERATING)
		end

		if not other_entity.faction.is_player_controlled or owner_faction:GetTrust(other_entity) ~= "ENEMY" or other_entity.stealth then
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
		local player_level = GetPlayerFactionLevel(other_faction)

		local settings = Map.GetSettings()
		if force and settings.peaceful == 3 then
			local ramp = 0.4
			local level = math.ceil(player_level * ramp)
			local num_bugs = level+1
			num = math.max(num_bugs, num)
			-- 【核心修改】单位超过 20000 之前，不缩减生成数量 (原版为 2000)
			if comp.faction.num_entities > 20000 then num = num // 3 end
		else
			num = math.min((player_level // 3)+1, num)
		end

		local bug_levels = GetBugCountsForLevel(player_level, num, force)
		local rewards = 0
		local spawn_delay = 1
		local allbugs = 0
		for i=1,#bug_levels do allbugs = allbugs + bug_levels[i] end
		local num_waves = (allbugs // 30)+1
		local target = other_entity.location

		for i=#bug_levels,1,-1 do
			if bug_levels[i] > 0 then
				for j=1,bug_levels[i] do
					rewards = rewards + (i * 3)
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

		if comp.owner.id == "f_bug_hive" and ed_extra_spawned < 8 and math.random() <= 0.05 then
			local x, y = owner.location.x, owner.location.y
			local newbughole = Map.CreateEntity(owner_faction, "f_bug_hole")
			newbughole:Place(math.random(x-4, x+4), math.random(y-4, y+4))
			extra_data.extra_spawned = ed_extra_spawned + 1
		end

		if not extra_data.rewards then
			comp.owner:AddItem("bug_carapace", math.min(rewards, 20))
			extra_data.rewards = rewards
		end
	end

	-- 2. 修改大型生成器
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return end

		local bugs_faction = GetBugsFaction()
		local settings = Map.GetSettings()
		local peaceful = settings.peaceful
		if peaceful == 1 then return comp:SetStateSleep(20000) end
		if peaceful ~= 3 and not settings.creep then return comp:SetStateSleep(10000) end

		-- 【核心修改】最大单位上限提升至 30000 (原版为 4000)
		if bugs_faction.num_entities > 30000 then return comp:SetStateSleep(1000) end

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
				local closest_distance, closest_faction, towards = 9999999
				for _, faction in ipairs(Map.GetFactions()) do
					if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
						local test_entity = faction.entities[math.random(1, #faction.entities)]
						local newdist = owner:GetRangeTo(test_entity)
						if newdist < closest_distance then
							closest_faction = faction
							closest_distance = newdist
							towards = test_entity
						end
					end
				end

				if closest_faction then
					-- 【核心修改】扩张/建立新巢穴的阈值提升至 20000 (原版为 2000)
					if ((peaceful == 2 and closest_distance > 20) or (closest_distance > 150)) and (bugs_faction.num_entities < 20000) then
						local rnd_scout = math.random()
						if rnd_scout > 0.6 then
							Map.Defer(function()
								if not owner.exists then return end
								local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
								scout:Place(owner)
								local harvest_comp = scout:FindComponent("c_bug_harvest")
								harvest_comp.extra_data.home = owner
								if rnd_scout > 0.7 or bugs_faction.num_entities > 500 then
									harvest_comp.extra_data.towards = towards and towards.location or closest_faction.home_location
								end
							end)
						end
						comp.extra_data.extra_spawned = 0
						return comp:SetStateSleep(math.random(4000,8000))
					elseif peaceful == 3 or (closest_distance <= 60) then
						local ent = closest_faction.home_entity
						if not ent then
							for _,e in ipairs(closest_faction.entities) do
								if e.exists and e.is_placed then ent = e break end
							end
						end
						if ent then
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

	print("[InsectLimit] Logic override successful. Swarm limit set to 30000, falloff at 20000.")
end
