-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 2.2.8 (Performance Optimized: Independent Census & Session Diagnostics)

local package = ...

function package:init()
	print("[InsectLimit] Initializing stable v2.2.8...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] ERROR: Bug components not found!")
		return
	end

	-- 局部化高频方法以提升 Lua 虚拟机性能
	local GetTick = Map.GetTick

	---------------------------------------------------------------------------
	-- 1. 独立人口普查系统 (分时扫描，逻辑对齐 1.9.6)
	---------------------------------------------------------------------------
	local function UpdateUnitCensus(bugs_faction)
		local ed = bugs_faction.extra_data
		local ents = bugs_faction.entities
		local total = #ents
		local now = GetTick()

		if total == 0 then
			ed.unit_count = 0
			ed.census_idx = 1
			return
		end

		-- 新一轮会话启动检测
		if not ed.census_idx or ed.census_idx == 1 or ed.census_idx > total then
			ed.census_idx = 1
			ed.census_acc = 0
			ed.census_start_tick = now
		end

		-- 每 Tick 扫描 100 个实体
		local end_idx = math.min(ed.census_idx + 100, total)
		local acc = ed.census_acc or 0

		for i = ed.census_idx, end_idx do
			local e = ents[i]
			if e and e.exists then
				local def = e.def
				-- 精准区分：只有移动单位 (Bots) 才计入单位上限统计
				if def and not def.type and (def.movement_speed or 0) > 0 then
					acc = acc + 1

					-- 【增量功能】：病毒致死判定 (HP <= 80)
					-- 放在此处可确保即便单位关机或休眠，也能被“上帝视角”扫描并回收
					if e.state_custom_1 and e.health <= 80 and def.cost_modifier ~= 0 then
						if not e.extra_data.virus_marked_for_death then
							e.extra_data.virus_marked_for_death = true
							e.powered_down = true
							if e.is_placed then e:PlayEffect("fx_glitch2") end
							Map.Delay("BugPerishAction", 150, { entity = e })
						end
					end
				end
			end
		end

		if end_idx >= total then
			-- 会话结束报告
			ed.unit_count = acc
			local duration = now - (ed.census_start_tick or now) + 1
			print(string.format("[InsectLimit] Census Session Complete -> BOTS: %d | Total Assets: %d | Duration: %d ticks (~%.1fs)", acc, total, duration, duration / 5))
			ed.census_idx = 1
		else
			ed.census_idx = end_idx + 1
			ed.census_acc = acc
		end
	end

	-- 注册全局后台任务
	function Delay.GlobalCensusLoop(arg)
		local bugs = GetBugsFaction()
		if bugs then UpdateUnitCensus(bugs) end
		Map.Delay("GlobalCensusLoop", 1)
	end

	-- 病毒覆灭回调
	function Delay.BugPerishAction(arg)
		local e = arg.entity
		if e and e.exists then
			if e.is_placed then e:PlayEffect("fx_digital") end
			e:Destroy(false)
		end
	end

	---------------------------------------------------------------------------
	-- 2. 通用攻击逻辑 (基于 1.9.6 持久化计时器)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner = comp.owner
			local ed = comp.extra_data

			-- 基础兵种感染后的防御性关机逻辑 (自毁由 Census 循环接管)
			if owner.state_custom_1 and owner.health <= 80 and not IsFlyingUnit(owner) then
				owner.powered_down = true
				return
			end

			local is_stuck = (cause & CC_FINISH_MOVE ~= 0 and owner.state_path_blocked) or owner.state_custom_1
			if is_stuck then
				if not ed.failed_move_ticks then ed.failed_move_ticks = GetTick() + 600
				elseif ed.failed_move_ticks < GetTick() then
					ed.failed_move_ticks = nil
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
				-- 只有顺畅移动才重置计时
				if not owner.state_path_blocked and owner.is_moving then ed.failed_move_ticks = nil end
			end
		end
		return data.components.c_turret.on_update(self, comp, cause)
	end

	-- 辅助：判定合法攻击目标 (支持驻留重定向)
	local function IsAttackable(e)
		if not e or not e.exists then return false end
		local target = e.is_placed and e or e.docked_garage
		if not target or not target.exists or not target.is_placed or target.id == "f_empty" then return false end

		local def = target.def
		if target.stealth or target.is_construction or def.immortal or def.is_explorable or def.size == "Mission" then
			return false
		end
		if def.type == "DroppedItem" or def.type == "Resource" then return false end
		return true
	end

	---------------------------------------------------------------------------
	-- 3. 蜂巢生产控制
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_faction = GetBugsFaction()
		local ed = bugs_faction.extra_data

		-- 启动后台任务
		if not ed.census_loop_started then
			ed.census_loop_started = true
			print("[InsectLimit] Starting Global Census Loop from Simulation Context...")
			Map.Delay("GlobalCensusLoop", 1)
		end

		local unit_count = ed.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1

		-- 生产上限判定
		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000 + math.random(1, 200)) end

		local last_swarm = Map.GetSave().last_swarm or 0
		if GetTick() - last_swarm < 750 then return comp:SetStateSleep(100) end

		-- 采样搜索玩家
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
					Map.GetSave().last_swarm = GetTick()
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

	print("[InsectLimit] v2.2.8: Session-based Diagnostics & Performance Peak enabled.")
end
