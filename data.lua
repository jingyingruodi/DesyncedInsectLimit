-- InsectLimit Mod - Performance & Logic Hybrid Build
-- Version: 2.5.0 (Rebased on 1.9.6 Stability + Heartbeat Optimization)
-- Author: 镜影若滴

local package = ...

function package:init()
	print("[InsectLimit] Re-initializing v2.5.0 - Rebased on stable v1.9.6...")

	local c_bug_spawn = data.components.c_bug_spawn
	local c_bug_spawner_large = data.components.c_bug_spawner_large
	local c_bug_harvest = data.components.c_bug_harvest
	local c_trilobyte_attack = data.components.c_trilobyte_attack

	if not c_bug_spawn or not c_bug_spawner_large or not c_bug_harvest or not c_trilobyte_attack then
		print("[InsectLimit] CRITICAL ERROR: Bug components missing!")
		return
	end

	---------------------------------------------------------------------------
	-- 1. 全局普查系统 (性能补丁：每 20秒 一次统计，全图蜂巢共享结果)
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

					-- [病毒处决逻辑] 基于 max_health 判定阶级，保护受伤的高阶单位
					-- 底层单位受感染直接处决
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
		-- 20秒心跳 (5 TPS * 20 = 100 ticks)
		Map.Delay("DiagnosticHeartbeat", 100)
	end

	---------------------------------------------------------------------------
	-- 2. 辅助判定逻辑 (还原 1.9.6 核心)
	---------------------------------------------------------------------------
	local function IsBugActiveSeason()
		return math.abs(Map.GetYearSeason() - 0.5) < 0.25
	end

	-- 【核心修复】：判断实体是否为真正可攻击目标
	-- 过滤掉原版会去攻击的蓝图、遗迹、掉落物等无效目标
	local function IsAttackable(e)
		if not e or not e.exists then return false end
		-- 目标必须已放置在地图上（或者是停靠在车库中的单位）
		local target = e.is_placed and e or e.docked_garage
		if not target or not target.is_placed or e.id == "f_empty" then return false end

		local def = target.def
		-- 排除列表
		if target.stealth then return false end           -- 隐行中
		if target.is_construction then return false end   -- 建筑规划/蓝图
		if def.immortal then return false end             -- 无敌单位
		if def.is_explorable then return false end        -- 可探索项
		if def.size == "Mission" then return false end    -- 任务特殊单位
		if def.type == "DroppedItem" then return false end -- 掉落物
		if def.type == "Resource" then return false end    -- 资源点

		return true
	end

	---------------------------------------------------------------------------
	-- 3. 病毒致命逻辑 (活跃单位防御性关机)
	---------------------------------------------------------------------------
	local function ProcessVirusDeath(owner, ed)
		-- 原版机制强化：底层受感染虫子强制关机倒计时
		if owner.state_custom_1 and owner.max_health <= 80 and not IsFlyingUnit(owner) then
			if not ed.virus_marked_for_death then
				ed.virus_marked_for_death = true
				owner:Cancel()        -- 立即中断当前任务
				owner.powered_down = true -- 瘫痪
				if owner.is_placed then owner:PlayEffect("fx_glitch2") end
				-- 30秒后覆灭 (150 ticks)
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
	-- 4. 攻击与卡死逻辑 (忠实 1.9.6 标准)
	---------------------------------------------------------------------------
	local function BugAttackUpdate(self, comp, cause)
		if not comp.faction.is_player_controlled then
			local owner, ed = comp.owner, comp.extra_data
			if ProcessVirusDeath(owner, ed) then return end

			-- 判定卡死：路径被阻挡 120秒
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

	---------------------------------------------------------------------------
	-- 5. 大型蜂巢生产控制 (还原 1.9.6 的智能目标筛选与采样优化)
	---------------------------------------------------------------------------
	c_bug_spawner_large.on_update = function(self, comp, cause)
		if comp.faction.is_player_controlled then return comp:SetStateSleep(10000) end

		local bugs_faction = GetBugsFaction()
		local ed = bugs_faction.extra_data

		-- 确保性能心跳启动
		if not ed.heartbeat_started then
			ed.heartbeat_started = true
			Map.Delay("DiagnosticHeartbeat", 10)
		end

		local unit_count = ed.unit_count or 0
		local pc = Map.GetPlayerFactionCount and Map.GetPlayerFactionCount() or 1
		local settings = Map.GetSettings()

		-- 上限逻辑 (适配 1.9.6 的扩容参数)
		if unit_count > (30000 * pc) then return comp:SetStateSleep(5000) end

		-- 攻势冷却
		local last_swarm = Map.GetSave().last_swarm or 0
		if Map.GetTick() - last_swarm < 750 then return comp:SetStateSleep(100) end

		-- 【核心重构】：智能目标寻找
		local closest_distance, closest_faction, towards = 9999999, nil, nil
		for _, faction in ipairs(Map.GetFactions()) do
			-- 必须与虫群敌对且有单位
			if faction.is_player_controlled and faction.num_entities > 0 and bugs_faction:GetTrust(faction) == "ENEMY" then
				local entities = faction.entities
				local test_unit, tries = nil, 0

				-- 采用采样搜索优化性能，不再盲目全量扫描
				while tries < 15 do
					local ent = entities[math.random(1, #entities)]
					if ent and ent.exists then
						-- 使用 IsAttackable 严格筛选合法目标
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

			-- [扩张与侦察模式] 还原 1.9.6
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

			-- [集群攻击模式] 还原 1.9.6 逻辑并修复千里奔袭 Bug
			elseif (settings.peaceful == 3 or closest_distance <= 60) and closest_distance < 250 then
				-- 季节判定：非活跃季降低攻击性
				if not IsBugActiveSeason() and math.random() > 0.1 then return comp:SetStateSleep(math.random(2000, 4000)) end

				-- 寻找优先攻击点：优先打击玩家基地中心
				local attack_target = closest_faction.home_entity
				-- 如果基地中心不可被攻击、或太远（防止千里奔袭），则选择采样到的普通单位
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
	-- 6. 侦察 AI (维持 1.9.6 筑巢稳定逻辑)
	---------------------------------------------------------------------------
	c_bug_harvest.on_update = function(self, comp, cause)
		local owner, ed = comp.owner, comp.extra_data
		local target, home = ed.target, ed.home

		if not home or not home.exists then
			Map.Defer(function() if owner.exists then owner:Destroy() end end)
			return comp:SetStateSleep(1)
		end

		if target and not target.exists then
			ed.state, ed.target = "wander", nil
			return comp:SetStateSleep(1)
		end
		if owner.is_moving then return comp:SetStateSleep(20 + math.random(1, 10)) end

		local state = ed.state or "idle"
		if state == "idle" then
			-- 官方原版扩张判定：寻找极小范围内的硅矿
			target = Map.FindClosestEntity(owner, 8, function(e)
				if IsResource(e) and GetResourceHarvestItemId(e) == "silica" and e:GetRangeTo(home) > 20 then return true end
				return false
			end, FF_RESOURCE)

			if target then
				ed.target, ed.state = target, "deploy"
			else
				ed.state, ed.wandertimes = "wander", (ed.wandertimes or 0) + 1
				-- 原版饥饿机制：50次游走未筑巢则消失
				if ed.wandertimes > 50 then Map.Defer(function() if owner.exists then owner:Destroy() end end) return comp:SetStateSleep(1) end
			end
		elseif state == "deploy" then
			if not owner.state_path_blocked then
				if comp:RequestStateMove(target, 3) then return end
			end
			ed.target = nil

			-- 1.9.6 密度检查：35格半径内大型蜂巢数量控制
			local hive_count = 0
			Map.FindClosestEntity(owner, 35, function(e)
				if e.id == "f_bug_hive" or e.id == "f_bug_hive_large" then
					hive_count = hive_count + 1
					if hive_count >= 2 then return true end
				end
			end, FF_OPERATING | FF_OWNFACTION)

			if hive_count >= 2 then
				ed.state = "wander"
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
			if ed.towards and (ed.towards.x ~= 0 or ed.towards.y ~= 0) then
				local tloc = ed.towards
				local dx = math.min(math.max((tloc.x - loc.x) // 3, -50), 50)
				local dy = math.min(math.max((tloc.y - loc.y) // 3, -50), 50)
				loc.x, loc.y = loc.x + dx + math.random(-5, 5), loc.y + dy + math.random(-5, 5)
			else
				loc.x, loc.y = loc.x + math.random(-15, 15), loc.y + math.random(-15, 15)
			end
			ed.state = "idle"
			return comp:RequestStateMove(loc, 1)
		end
	end

	-- 应用组件
	c_trilobyte_attack.on_update = BugAttackUpdate
	if data.components.c_tetrapuss_attack1 then data.components.c_tetrapuss_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack1 then data.components.c_larva_attack1.on_update = BugAttackUpdate end
	if data.components.c_larva_attack2 then data.components.c_larva_attack2.on_update = BugAttackUpdate end

	print("[InsectLimit] v2.5.0: Final Hybrid Logic Stabilized. 1.9.6 Logic Reinstated with Performance Census.")
end
