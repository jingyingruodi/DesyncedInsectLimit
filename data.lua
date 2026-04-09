-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 2.3.2 (Performance Breakthrough: Event-based O(1) Counting & Stealth Logic)

local package = ...

function package:init()
	print("[InsectLimit] Initializing v2.3.2 - Extreme Low-Overhead Build...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_trilobyte_attack then
		print("[InsectLimit] ERROR: Bug components not found!")
		return
	end

	---------------------------------------------------------------------------
	-- 1. 事件驱动的人口统计系统 (替代高开销的每Tick循环)
	---------------------------------------------------------------------------

	-- 劫持全局生成函数
	local old_CreateBug = _G.CreateBugForBugLevel
	_G.CreateBugForBugLevel = function(lvl, f)
		local bug = old_CreateBug(lvl, f)
		if bug then FactionCount("unit_count", 1, bug.faction) end
		return bug
	end

	-- 劫持虫族兵种的死亡回调
	local bug_frame_ids = { "f_trilobyte1", "f_gastarias1", "f_trilobyte1a", "f_scaramar1", "f_trilobyte1b", "f_wasp1", "f_scaramar2", "f_gastarias2", "f_gastarid1", "f_larva1", "f_tetrapuss1", "f_tripodonte1", "f_worm1" }
	for _, id in ipairs(bug_frame_ids) do
		local frame = data.frames[id]
		if frame then
			local old_destroy = frame.on_destroy
			frame.on_destroy = function(self, entity, damager)
				FactionCount("unit_count", -1, entity.faction)
				if old_destroy then old_destroy(self, entity, damager) end
			end
		end
	end

	-- 初始化：仅在载入存档时执行一次 O(N) 统计
	local function EnsureUnitCountInitialized(faction)
		local ed = faction.extra_data
		if not ed.unit_count_initialized then
			local count = 0
			for _, e in ipairs(faction.entities) do
				-- 使用 has_movement 极速区分兵与建筑，且不访问 .def
				if e.exists and e.has_movement and not e.is_construction then
					count = count + 1
				end
			end
			if not ed.counters then ed.counters = {} end
			ed.counters.unit_count = count
			ed.unit_count_initialized = true
			print("[InsectLimit] Initial Census Complete. Total BOTS found: " .. count)
		end
	end

	---------------------------------------------------------------------------
	-- 2. 玩家位置缓存 (每 20秒 更新一次，极低频)
	---------------------------------------------------------------------------
	local _player_pos_cache = {}
	local _last_cache_tick = -1

	local function GetPlayerPositions()
		local now = Map.GetTick()
		if now - _last_cache_tick < 100 then return _player_pos_cache end

		local pos = {}
		for _, faction in ipairs(Map.GetFactions()) do
			if faction.is_player_controlled then
				for _, e in ipairs(faction.entities) do
					if e.exists and e.is_placed and e.id ~= "f_empty" then
						table.insert(pos, e.location)
					end
				end
			end
		end
		_player_pos_cache = pos
		_last_cache_tick = now
		return pos
	end

	local function IsPlayerNearbyLua(loc, radius)
		local players = GetPlayerPositions()
		local r_sq = radius * radius
		for i=1, #players do
			local p = players[i]
			local dx, dy = loc.x - p.x, loc.y - p.y
			if (dx*dx + dy*dy) < r_sq then return true end
		end
		return false
	end

	---------------------------------------------------------------------------
	-- 3. 核心行为组件 (维持 1.9.6 标准)
	---------------------------------------------------------------------------

	-- 处决逻辑
	local function ProcessBugLethality(owner, ed)
		-- 病毒致死 (HP <= 80)
		if owner.state_custom_1 and owner.health <= 80 and not IsFlyingUnit(owner) then
			if not ed.virus_marked_for_death then
				ed.virus_marked_for_death = true
				owner.powered_down = true
				Map.Delay("BugDeathAction", 150, { entity = owner })
			end
			return true
		end
		-- 远距离清理判定 (只有当兵力过载且活跃时抽检)
		local faction = owner.faction
		local unit_count = faction.extra_data.counters and faction.extra_data.counters.unit_count or 0
		if unit_count > 4000 and owner.health < 400 and not IsFlyingUnit(owner) then
			-- 只有 1/50 的概率执行空间探测，进一步均摊性能
			if math.random(1, 50) == 1 then
				local loc = owner.is_placed and owner.location or (owner.docked_garage and owner.docked_garage.location)
				if loc and not IsPlayerNearbyLua(loc, 300) then
					if owner.is_placed then owner:PlayEffect("fx_digital") end
					owner:Destroy(false)
					return true
				end
			end
		end
		return false
	end

	function Delay.BugDeathAction(arg)
		local e = arg.entity
		if e and e.exists then
			if e.is_placed then e:PlayEffect("fx_digital") end
			e:Destroy(false)
		end
	end

	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data
			if ProcessBugLethality(owner, ed) then return end

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
		if target.stealth or target.is_construction or def.immortal or def.is_explorable then return false end
		return true
	end

	---------------------------------------------------------------------------
	-- 4. 蜂巢生产核心 (基于实时计数)
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_faction = GetBugsFaction()
		EnsureUnitCountInitialized(bugs_faction)

		local unit_count = bugs_faction.extra_data.counters and bugs_faction.extra_data.counters.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1

		if Map.GetTick() % 100 == 0 then
			print(string.format("[InsectLimit] REAL BOTS: %d | Total Assets: %d", unit_count, bugs_faction.num_entities))
		end

		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000) end

		-- 维持 1.8.4 采样感应逻辑
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
			if (unit_count < (10000 * pc)) and (closest_distance > 150) then
				if math.random() > 0.6 then
					Map.Defer(function() if not comp.owner.exists then return end
						local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
						scout:Place(comp.owner)
						local h = scout:FindComponent("c_bug_harvest")
						if towards and towards.exists then h.extra_data.towards = Tool.Copy(towards.location) end
					end)
				end
				return comp:SetStateSleep(math.random(4000, 8000))
			elseif closest_distance < 250 then
				local attack_target = closest_faction.home_entity
				if not IsAttackable(attack_target) or comp.owner:GetRangeTo(attack_target) > 250 then attack_target = towards end
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

	-- 应用修正
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.3.2: O(1) Counter restored with Event-driven hooks.")
end
