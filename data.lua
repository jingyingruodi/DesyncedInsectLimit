-- InsectLimit Mod - Dedicated Server Compatible
-- Version: 2.3.6 (Performance Milestone: Low-frequency Heartbeat & Zero-Latency Counting)

local package = ...

function package:init()
	print("[InsectLimit] Restoring peak performance (v2.3.6 Heartbeat mode)...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_trilobyte_attack then
		print("[InsectLimit] ERROR: Bug components not found!")
		return
	end

	---------------------------------------------------------------------------
	-- 1. 低频心跳统计与处决系统 (每 20秒 运行一次，平时 0 占用)
	---------------------------------------------------------------------------
	function Delay.DiagnosticHeartbeat(arg)
		local bugs = GetBugsFaction()
		if not bugs then return end

		local ents = bugs.entities
		local total = #ents
		local bot_count = 0
		local perish_count = 0

		-- 极速全量扫描 (每 20秒 执行一次)
		for i = 1, total do
			local e = ents[i]
			if e and e.exists then
				-- 使用 has_movement 极速判定兵种
				if e.has_movement and not e.is_construction then
					bot_count = bot_count + 1

					-- 【上帝视角处决】：顺便清理感染的小虫，彻底解决关机不覆灭问题
					if e.state_custom_1 and e.health <= 80 then
						e:Destroy(false)
						perish_count = perish_count + 1
					end
				end
			end
		end

		-- 更新全局计数
		bugs.extra_data.unit_count = bot_count

		-- 周期性报告
		print(string.format("[InsectLimit] Heartbeat -> BOTS: %d | Total: %d | Virus Perished: %d", bot_count, total, perish_count))

		-- 预定下一个 20秒 后的心跳
		Map.Delay("DiagnosticHeartbeat", 100)
	end

	---------------------------------------------------------------------------
	-- 2. 攻击组件脱困 (维持 1.9.6 标准)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data

			-- 感染后立即关机 (覆灭由 20秒 一次的心跳循环兜底执行)
			if owner.state_custom_1 and owner.health <= 80 and not IsFlyingUnit(owner) then
				owner.powered_down = true
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

	---------------------------------------------------------------------------
	-- 3. 蜂巢生产控制
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_faction = GetBugsFaction()
		local ed = bugs_faction.extra_data

		-- 首次启动心跳
		if not ed.heartbeat_started then
			ed.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		local unit_count = ed.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1

		-- 生产限制
		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000) end

		-- 维持 1.8.4 感知标准
		local last_swarm = Map.GetSave().last_swarm or 0
		if Map.GetTick() - last_swarm < 750 then return comp:SetStateSleep(100) end

		-- 采样搜索玩家
		local closest_distance, towards = 9999999, nil
		for _, faction in ipairs(Map.GetFactions()) do
			if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
				local entities = faction.entities
				local test_unit, tries = nil, 0
				while tries < 20 do
					local ent = entities[math.random(1, #entities)]
					if ent and ent.exists then
						local target = ent.is_placed and ent or ent.docked_garage
						if target and target.is_placed and not target.stealth and not target.is_construction and not target.def.immortal and not target.def.is_explorable then
							test_unit = target
							break
						end
					end
					tries = tries + 1
				end
				if test_unit then
					local d = comp.owner:GetRangeTo(test_unit)
					if d < 250 and d < closest_distance then closest_distance, towards = d, test_unit end
				end
			end
		end

		if towards then
			local difficulty = Map.GetSettings().difficulty or 1.0
			if (unit_count < (10000 * pc * difficulty)) and (closest_distance > 150) then
				if math.random() > 0.6 then
					Map.Defer(function() if not comp.owner.exists then return end
						local scout = Map.CreateEntity(bugs_faction, "f_triloscout")
						scout:Place(comp.owner)
						if towards and towards.exists then scout:FindComponent("c_bug_harvest").extra_data.towards = Tool.Copy(towards.location) end
					end)
				end
				return comp:SetStateSleep(math.random(4000, 8000))
			elseif closest_distance < 250 then
				local attack_target = towards
				Map.GetSave().last_swarm = Map.GetTick()
				Map.Defer(function() if comp.exists and attack_target.exists then
					data.components.c_bug_spawn:on_trigger_action(comp, attack_target, true)
				end end)
			end
		end
		return comp:SetStateSleep(math.random(300, 600))
	end

	-- 应用组件
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.3.6: Performance parity with 1.9.6 restored.")
end
