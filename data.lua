-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 2.2.4 (Performance Monitor Fix & Throttled Reaper Optimization)

local package = ...

function package:init()
	print("[InsectLimit] Initializing v2.2.4 (Performance & Diagnostics Optimized)...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] ERROR: Bug components not found!")
		return
	end

	---------------------------------------------------------------------------
	-- 1. 极速玩家位置缓存系统
	---------------------------------------------------------------------------
	local _player_pos_cache = {}
	local function UpdatePlayerCache()
		local pos = {}
		for _, faction in ipairs(Map.GetFactions()) do
			if faction.is_player_controlled then
				local ents = faction.entities
				for i=1, #ents do
					local e = ents[i]
					-- 排除无物理位置的逻辑实体
					if e and e.exists and e.is_placed and e.id ~= "f_empty" and e.def.type ~= "DroppedItem" then
						table.insert(pos, e.location)
					end
				end
			end
		end
		_player_pos_cache = pos
	end

	local function IsPlayerNearbyLua(loc, radius)
		local r_sq = radius * radius
		local cache = _player_pos_cache
		for i=1, #cache do
			local p = cache[i]
			local dx, dy = loc.x - p.x, loc.y - p.y
			if (dx*dx + dy*dy) < r_sq then return true end
		end
		return false
	end

	---------------------------------------------------------------------------
	-- 2. 全局普查与清理循环 (逻辑增强)
	---------------------------------------------------------------------------
	local function RunIncrementalReaper(bugs_faction)
		local ed = bugs_faction.extra_data
		local ents = bugs_faction.entities
		local total = #ents
		local current_tick = Map.GetTick()

		if total == 0 then
			ed.unit_count = 0
			ed.census_idx, ed.census_acc, ed.census_cleaned = 1, 0, 0
			return
		end

		-- 【修复】：每轮会话开始时精准重置计时器和计数器
		if not ed.census_idx or ed.census_idx == 1 or ed.census_idx > total then
			ed.census_idx = 1
			ed.census_acc = 0
			ed.census_cleaned = 0
			ed.census_start_tick = current_tick
			UpdatePlayerCache() -- 每一轮扫描前刷新一次玩家坐标快照
		end

		-- 每 Tick 扫描 300 个实体 (性能余量充足)
		local end_idx = math.min(ed.census_idx + 300, total)
		local acc = ed.census_acc or 0
		local cleaned = ed.census_cleaned or 0
		local last_unit_count = ed.unit_count or 0

		for i = ed.census_idx, end_idx do
			local e = ents[i]
			if e and e.exists and IsBot(e) then
				acc = acc + 1

				-- 病毒致死处理
				if e.state_custom_1 and e.health <= 80 and not IsFlyingUnit(e) then
					if not e.extra_data.virus_marked_for_death then
						e.extra_data.virus_marked_for_death = true
						e.powered_down = true
						Map.Delay("BugPerishAction", 150, { entity = e })
					end
				end

				-- 远距离清理 (仅当兵力 > 4000 时)
				if last_unit_count >= 4000 and e.health < 400 and not IsFlyingUnit(e) then
					local loc = e.is_placed and e.location or (e.docked_garage and e.docked_garage.location)
					if loc and not IsPlayerNearbyLua(loc, 300) then
						Map.Defer(function()
							if e.exists then
								if e.is_placed then e:PlayEffect("fx_digital") end
								e:Destroy(false)
							end
						end)
						cleaned = cleaned + 1
					end
				end
			end
		end

		if end_idx >= total then
			-- 记录本轮结果
			ed.unit_count = acc
			local duration = current_tick - (ed.census_start_tick or current_tick) + 1
			-- 输出更详细的诊断信息
			print(string.format("[InsectLimit] Census Session -> BOTS: %d | Cleaned: %d | Total: %d | Time: %d ticks", acc, cleaned, total, duration))
			ed.census_idx, ed.census_acc, ed.census_cleaned = 1, 0, 0
		else
			ed.census_idx = end_idx + 1
			ed.census_acc = acc
			ed.census_cleaned = cleaned
		end
	end

	-- 病毒致死回调
	function Delay.BugPerishAction(arg)
		local e = arg.entity
		if e and e.exists then
			if e.is_placed then e:PlayEffect("fx_digital") end
			e:Destroy(false)
		end
	end

	-- 全局普查任务
	function Delay.GlobalCensusLoop(arg)
		local bugs = GetBugsFaction()
		if bugs then RunIncrementalReaper(bugs) end
		Map.Delay("GlobalCensusLoop", 1)
	end

	---------------------------------------------------------------------------
	-- 3. 通用攻击逻辑 (维持 1.9.6 基准)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data

			if owner.state_custom_1 and owner.health <= 80 and not IsFlyingUnit(owner) then
				if not ed.virus_marked_for_death then
					ed.virus_marked_for_death = true
					owner.powered_down = true
					Map.Delay("BugPerishAction", 150, { entity = owner })
				end
				return
			end

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
		if not target or not target.exists or not target.is_placed or target.id == "f_empty" then return false end
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

		-- 启动后台任务
		if not ed.census_loop_started then
			ed.census_loop_started = true
			Map.Delay("GlobalCensusLoop", 1)
		end

		local unit_count = ed.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1

		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000 + math.random(1, 200)) end

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

	-- 应用核心攻击逻辑
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.2.4: Optimized Census Monitor & Higher Throughput Cleanup.")
end
