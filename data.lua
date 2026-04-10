-- InsectLimit Mod - Performance & Faithful Expansion Logic
-- Version: 2.5.2 (Census Philosophy Aligned + 30s Heartbeat)
-- Author: 镜影若滴

local package = ...

function package:init()
	print("[InsectLimit] Initializing v2.5.2 - Unit-only Census Active...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] CRITICAL ERROR: Bug components missing!")
		return
	end

	---------------------------------------------------------------------------
	-- 1. 全局普查系统 (极致低频 30秒/150 ticks 一次统计)
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
				-- 【设计哲学差异】：
				-- 官方统计(num_entities)包含所有实体（虫巢+虫子）。
				-- 本模组统计(unit_count)仅包含具有移动能力的非建筑单位。
				-- 这样可以防止大量筑巢后导致战斗单位名额被占用的情况。
				if e.has_movement and not e.is_construction then
					bot_count = bot_count + 1
					-- [病毒处决逻辑]
					if e.state_custom_1 and e.max_health <= 80 then
						e:Destroy(false)
						perish_count = perish_count + 1
					end
				end
			end
		end

		bugs.extra_data.unit_count = bot_count
		bugs.extra_data.asset_count = total
		print(string.format("[InsectLimit] Census -> REAL BOTS: %d | Total Assets: %d | Virus Culled: %d", bot_count, total, perish_count))

		-- 30秒心跳 (5 TPS * 30 = 150 ticks)
		Map.Delay("DiagnosticHeartbeat", 150)
	end

	---------------------------------------------------------------------------
	-- 2. 辅助判定逻辑
	---------------------------------------------------------------------------
	local function IsBugActiveSeason()
		return math.abs(Map.GetYearSeason() - 0.5) < 0.25
	end

	-- 【核心修复】：目标合法性筛选
	local function IsAttackable(e)
		if not e or not e.exists then return false end
		local target = e.is_placed and e or e.docked_garage
		if not target or not target.is_placed or e.id == "f_empty" then return false end

		local def = target.def
		if target.stealth then return false end
		if target.is_construction then return false end
		if def.immortal then return false end
		if def.is_explorable then return false end
		if def.size == "Mission" then return false end
		if def.type == "DroppedItem" then return false end
		if def.type == "Resource" then return false end

		return true
	end

	---------------------------------------------------------------------------
	-- 3. 通用行为逻辑
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
				if not ed.failed_move_ticks then ed.failed_move_ticks = Map.GetTick() + 600
				elseif ed.failed_move_ticks < Map.GetTick() then
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

	function Delay.BugForcePerish(arg)
		local e = arg.entity
		if e and e.exists then
			if e.is_placed then e:PlayEffect("fx_digital") end
			e:Destroy(false)
		end
	end

	---------------------------------------------------------------------------
	-- 4. 蜂巢生产与入侵截断
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_faction = GetBugsFaction()
		local ed = bugs_faction.extra_data

		if not ed.heartbeat_started then
			ed.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		-- 基于活跃单位(Unit)而非全部资产(Asset)判定上限
		local unit_count = ed.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
		local settings = Map.GetSettings()

		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000) end

		local last_swarm = Map.GetSave().last_swarm or 0
		if Map.GetTick() - last_swarm < 750 then return comp:SetStateSleep(100) end

		local closest_distance, closest_faction, towards = 9999999, nil, nil
		for _, faction in ipairs(Map.GetFactions()) do
			if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
				local entities = faction.entities
				local test_unit, tries = nil, 0
				while tries < 15 do
					local ent = entities[math.random(1, #entities)]
					if ent and ent.exists then
						if IsAttackable(ent) then test_unit = ent break end
					end
					tries = tries + 1
				end
				if test_unit then
					local d = comp.owner:GetRangeTo(test_unit)
					if d < 250 and d < closest_distance then closest_distance, closest_faction, towards = d, faction, test_unit end
				end
			end
		end

		if closest_faction then
			local difficulty = settings.difficulty or 1.0

			if (unit_count < (10000 * pc * difficulty)) and (closest_distance > 150) then
				if math.random() > 0.6 then
					Map.Defer(function() if not comp.owner.exists then return end
						local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
						scout:Place(comp.owner)
						local harvest_comp = scout:FindComponent("c_bug_harvest")
						if harvest_comp then
							harvest_comp.extra_data.home = comp.owner
							if towards and towards.exists then harvest_comp.extra_data.towards = Tool.Copy(towards.location) end
						end
					end)
				end
				return comp:SetStateSleep(math.random(4000, 8000))

			elseif (settings.peaceful == 3 or closest_distance <= 60) and closest_distance < 250 then
				if not IsBugActiveSeason() and math.random() > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end

				local attack_target = closest_faction.home_entity
				if not IsAttackable(attack_target) or comp.owner:GetRangeTo(attack_target) > 250 then
					attack_target = towards
				end

				if attack_target and attack_target.exists then
					Map.GetSave().last_swarm = Map.GetTick()
					Map.Defer(function() if comp.exists and attack_target.exists then
						data.components.c_bug_spawn:on_trigger_action(comp, attack_target, true)
					end end)
				end
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	---------------------------------------------------------------------------
	-- 5. 侦察 AI (Faithful Original Behavior)
	---------------------------------------------------------------------------
	c_bug_harvest.on_update = function(self, comp, cause)
		local owner, data = comp.owner, comp.extra_data
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
				if data.wandertimes > 50 then Map.Defer(function() if owner.exists then owner:Destroy() end end) return comp:SetStateSleep(1) end
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

	-- Apply hooks
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.5.2: Final Stability & Performance Aligned.")
end
