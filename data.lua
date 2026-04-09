-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 2.3.8 (Tier Logic Fix: Consistent max_health Discrimination)

local package = ...

function package:init()
	print("[InsectLimit] Initializing v2.3.8 (Tier-Logic Reinforced)...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_trilobyte_attack then
		print("[InsectLimit] ERROR: Bug components not found!")
		return
	end

	---------------------------------------------------------------------------
	-- 1. 低频心跳普查系统 (每 20秒 一次，基于 max_health 的上帝视角处决)
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
				-- O(1) 属性探测：区分移动单位
				if e.has_movement and not e.is_construction then
					bot_count = bot_count + 1

					-- 【修复】：改用 max_health 判定阶级，保护受伤的高阶单位
					if e.state_custom_1 and e.max_health <= 80 then
						e:Destroy(false)
						perish_count = perish_count + 1
					end
				end
			end
		end

		bugs.extra_data.unit_count = bot_count
		print(string.format("[InsectLimit] Heartbeat -> REAL BOTS: %d | Total Assets: %d | Virus Perished: %d", bot_count, total, perish_count))
		Map.Delay("DiagnosticHeartbeat", 100)
	end

	---------------------------------------------------------------------------
	-- 2. 病毒致命逻辑 (基于 max_health 触发关机)
	---------------------------------------------------------------------------
	local function ProcessVirusDeath(owner, ed)
		-- 只有最大血量 <= 80 的基础单位受感染才会瘫痪自毁
		if owner.state_custom_1 and owner.max_health <= 80 and not IsFlyingUnit(owner) then
			if not ed.virus_marked_for_death then
				ed.virus_marked_for_death = true
				owner.powered_down = true
				if owner.is_placed then owner:PlayEffect("fx_glitch2") end
				-- 设置 30秒 延迟处决
				Map.Delay("BugForcePerish", 150, { entity = owner })
			end
			return true
		end
		return false
	end

	function Delay.BugForcePerish(arg)
		local e = arg.entity
		if e and e.exists then
			if e.is_placed then e:PlayEffect("fx_digital") end
			e:Destroy(false)
		end
	end

	---------------------------------------------------------------------------
	-- 3. 通用行为逻辑 (维持 1.9.6 标准)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data
			if ProcessVirusDeath(owner, ed) then return end

			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			if is_stuck then
				if not ed.failed_move_ticks then ed.failed_move_ticks = Map.GetTick() + 600
				elseif ed.failed_move_ticks < Map.GetTick() then
					ed.failed_move_ticks = nil
					if not comp:RegisterIsLink(1) then comp:SetRegister(1, nil) end
					if not owner:FindComponent("c_bug_homeless") then
						Map.Defer(function() if comp.exists then owner:AddComponent("c_bug_homeless") end end)
					end
					return
				end
			else
				if not owner.state_path_blocked and owner.is_moving then ed.failed_move_ticks = nil end
			end
		end
		return data.components.c_turret.on_update(self, comp, cause)
	end

	local function IsAttackable(e)
		if not e or not e.exists then return false end
		local target = e.is_placed and e or e.docked_garage
		if not target or not target.is_placed or e.id == "f_empty" then return false end
		local def = target.def
		if target.stealth or target.is_construction or def.immortal or def.is_explorable or def.size == "Mission" then return false end
		if def.type == "DroppedItem" or def.type == "Resource" then return false end
		return true
	end

	---------------------------------------------------------------------------
	-- 4. 蜂巢生产控制
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_faction = GetBugsFaction()
		local ed = bugs_faction.extra_data

		if not ed.heartbeat_started then
			ed.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		local unit_count = ed.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1

		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000) end

		local last_swarm = Map.GetSave().last_swarm or 0
		if Map.GetTick() - last_swarm < 750 then return comp:SetStateSleep(100) end

		local closest_distance, closest_faction, towards = 9999999
		for _, faction in ipairs(Map.GetFactions()) do
			if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
				local entities = faction.entities
				local test_unit, tries = nil, 0
				while tries < 20 do
					local ent = entities[math.random(1, #entities)]
					if ent and ent.exists and not ent.stealth and not ent.is_construction then
						if ent.is_docked then ent = ent.docked_garage end
						if IsAttackable(ent) then test_unit = ent break end
					end
					tries = tries + 1
				end
				if test_unit then
					local d = comp.owner:GetRangeTo(test_unit)
					if d < 250 and d < closest_distance then closest_faction, closest_distance, towards = faction, d, test_unit end
				end
			end
		end

		if closest_faction then
			local difficulty = Map.GetSettings().difficulty or 1.0
			if (unit_count < (10000 * pc * difficulty)) and (closest_distance > 150) then
				if math.random() > 0.6 then
					Map.Defer(function() if not comp.owner.exists then return end
						local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
						scout:Place(comp.owner)
						local h = scout:FindComponent("c_bug_harvest")
						if towards and towards.exists then h.extra_data.towards = Tool.Copy(towards.location) end
					end)
				end
				comp.extra_data.extra_spawned = 0
				return comp:SetStateSleep(math.random(4000, 8000))
			elseif closest_distance < 250 then
				local attack_target = closest_faction.home_entity
				if not IsAttackable(attack_target) or comp.owner:GetRangeTo(attack_target) > 250 then attack_target = towards end
				if attack_target and attack_target.exists then
					Map.GetSave().last_swarm = Map.GetTick()
					Map.Defer(function() if comp.exists and attack_target.exists then
						data.components.c_bug_spawn:on_trigger_action(comp, attack_target, true)
						comp.extra_data.extra_spawned = 0
					end end)
				end
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	-- 应用组件
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.3.8: Fixed tier discrimination logic using max_health.")
end
