--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

-- Import dependencies from your engine architecture
local SpatialEngine = require(script.Parent.Parent.SpatialEngine)
local NavigationEngine = require(script.Parent.Parent.NavigationEngine)
local CharacterEngine = require(script.Parent.Parent.CharacterEngine)
local DataEngine = require(script.Parent.Parent.DataEngine)

export type NPCType = "Zombie" | "Soldier" | "Robot_RO01" | "Robot_NPC9000"

export type NPCConfig = {
	Type: NPCType,
	PatrolEnabled: boolean,
	PatrolRadius: number,
	AttackDamage: number,
	AttackDelay: number,
	AttackMode: number, -- 1: Tagged enemies only, 2: All non-friends, 3: All characters
	AttackRadius: number,
	RagdollEnabled: boolean,
	DestroyOnDeath: boolean,
	-- Soldier-specific
	ClipCapacity: number?,
	ReloadDelay: number?
}

export type NPCInstance = {
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	Config: NPCConfig,
	CurrentAmmo: number,
	IsReloading: boolean,
	LastAttackTime: number,
	Target: Model?,
	IsDead: boolean
}

local NPCEngine = {
	ActiveNPCs = {} :: {[Model]: NPCInstance},
	NPC_TEMPLATES = {} :: {[NPCType]: Model}, -- Pre-loaded NPC models
	DEFAULT_CONFIGS = {
		Zombie = {
			Type = "Zombie",
			PatrolEnabled = true,
			PatrolRadius = 25,
			AttackDamage = 15,
			AttackDelay = 1.5,
			AttackMode = 1,
			AttackRadius = 5,
			RagdollEnabled = true,
			DestroyOnDeath = false
		},
		Soldier = {
			Type = "Soldier",
			PatrolEnabled = true,
			PatrolRadius = 40,
			AttackDamage = 25,
			AttackDelay = 0.8,
			AttackMode = 2,
			AttackRadius = 50,
			RagdollEnabled = false,
			DestroyOnDeath = true,
			ClipCapacity = 30,
			ReloadDelay = 2.5
		},
		Robot_RO01 = {
			Type = "Robot_RO01",
			PatrolEnabled = true,
			PatrolRadius = 30,
			AttackDamage = 20,
			AttackDelay = 1.0,
			AttackMode = 1,
			AttackRadius = 35,
			RagdollEnabled = false,
			DestroyOnDeath = true
		},
		Robot_NPC9000 = {
			Type = "Robot_NPC9000",
			PatrolEnabled = false,
			PatrolRadius = 0,
			AttackDamage = 30,
			AttackDelay = 2.0,
			AttackMode = 3,
			AttackRadius = 60,
			RagdollEnabled = false,
			DestroyOnDeath = true
		}
	} :: {[NPCType]: NPCConfig}
}

-- ============================================
-- INITIALIZATION & SPAWNING
-- ============================================

function NPCEngine.registerTemplate(npcType: NPCType, templateModel: Model)
	NPCEngine.NPC_TEMPLATES[npcType] = templateModel
end

function NPCEngine.spawnNPC(npcType: NPCType, position: Vector3, customConfig: NPCConfig?): NPCInstance?
	local template = NPCEngine.NPC_TEMPLATES[npcType]
	if not template then
		warn(`[NPCEngine] No template registered for type: {npcType}`)
		return nil
	end
	
	local model = template:Clone()
	model:PivotTo(CFrame.new(position))
	model.Parent = workspace
	
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	
	if not humanoid or not rootPart then
		warn(`[NPCEngine] Invalid NPC model structure for {npcType}`)
		model:Destroy()
		return nil
	end
	
	-- Merge custom config with defaults
	local config = table.clone(NPCEngine.DEFAULT_CONFIGS[npcType])
	if customConfig then
		for key, value in pairs(customConfig) do
			config[key] = value
		end
	end
	
	-- Apply configuration to the NPC's Configuration object
	local configObj = model:FindFirstChild("Configuration")
	if configObj then
		for key, value in pairs(config) do
			local valueObj = configObj:FindFirstChild(key)
			if valueObj and typeof(valueObj) == "Instance" then
				(valueObj :: any).Value = value
			end
		end
	end
	
	local npcInstance: NPCInstance = {
		Model = model,
		Humanoid = humanoid,
		RootPart = rootPart,
		Config = config,
		CurrentAmmo = config.ClipCapacity or 0,
		IsReloading = false,
		LastAttackTime = 0,
		Target = nil,
		IsDead = false
	}
	
	NPCEngine.ActiveNPCs[model] = npcInstance
	
	-- Hook into death event
	humanoid.Died:Connect(function()
		NPCEngine.handleNPCDeath(npcInstance)
	end)
	
	-- Start AI behavior loop
	task.spawn(NPCEngine.runBehaviorLoop, npcInstance)
	
	return npcInstance
end

-- ============================================
-- TAG SYSTEM & AGGRESSION LOGIC
-- ============================================

function NPCEngine.shouldAttack(npc: NPCInstance, target: Model): boolean
	local config = npc.Config
	
	-- Mode 3: Attack everything
	if config.AttackMode == 3 then
		return true
	end
	
	-- Check if target is a player character
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	
	-- Mode 1: Attack only tagged enemies
	if config.AttackMode == 1 then
		if npc.Config.Type == "Soldier" then
			return CollectionService:HasTag(target, "SoldierEnemy")
		elseif npc.Config.Type == "Zombie" then
			-- Zombies attack everyone EXCEPT those tagged as friends
			return not CollectionService:HasTag(target, "ZombieFriend")
		end
	end
	
	-- Mode 2: Attack all non-friends
	if config.AttackMode == 2 then
		return not CollectionService:HasTag(target, "SoldierFriend")
	end
	
	return false
end

function NPCEngine.findTarget(npc: NPCInstance): Model?
	local rootPos = npc.RootPart.Position
	local attackRadius = npc.Config.AttackRadius
	
	-- Check all players and NPCs within radius
	local candidates: {Model} = {}
	
	-- Check players
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local distance = (character.HumanoidRootPart.Position - rootPos).Magnitude
			if distance <= attackRadius then
				table.insert(candidates, character)
			end
		end
	end
	
	-- Check other NPCs
	for otherModel, otherNPC in pairs(NPCEngine.ActiveNPCs) do
		if otherModel ~= npc.Model and not otherNPC.IsDead then
			local distance = (otherNPC.RootPart.Position - rootPos).Magnitude
			if distance <= attackRadius then
				table.insert(candidates, otherModel)
			end
		end
	end
	
	-- Filter by aggression rules
	for _, candidate in ipairs(candidates) do
		if NPCEngine.shouldAttack(npc, candidate) then
			return candidate
		end
	end
	
	return nil
end

-- ============================================
-- COMBAT SYSTEM
-- ============================================

function NPCEngine.attemptAttack(npc: NPCInstance, target: Model)
	local config = npc.Config
	local currentTime = tick()
	
	-- Check attack cooldown
	if currentTime - npc.LastAttackTime < config.AttackDelay then
		return
	end
	
	-- Soldier-specific: Check ammo and reload
	if config.Type == "Soldier" then
		if npc.CurrentAmmo <= 0 then
			if not npc.IsReloading then
				task.spawn(NPCEngine.reloadWeapon, npc)
			end
			return
		end
		npc.CurrentAmmo -= 1
	end
	
	-- Check line of sight using SpatialEngine
	local rayResult = SpatialEngine.castRay(
		npc.RootPart.Position,
		(target:FindFirstChild("HumanoidRootPart") :: BasePart).Position - npc.RootPart.Position,
		{ FilterDescendantsInstances = {npc.Model} }
	)
	
	if rayResult and rayResult.Instance and rayResult.Instance:IsDescendantOf(target) then
		-- Execute attack
		local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
		if targetHumanoid then
			targetHumanoid:TakeDamage(config.AttackDamage)
			npc.LastAttackTime = currentTime
			
			-- Play attack animation (if exists)
			local animations = npc.Model:FindFirstChild("Animations")
			if animations then
				local attackAnim = animations:FindFirstChild("AttackAnimation")
				if attackAnim then
					local animator = npc.Humanoid:FindFirstChildOfClass("Animator")
					if animator then
						local track = animator:LoadAnimation(attackAnim :: Animation)
						track:Play()
					end
				end
			end
		end
	end
end

function NPCEngine.reloadWeapon(npc: NPCInstance)
	if npc.IsReloading then return end
	
	npc.IsReloading = true
	task.wait(npc.Config.ReloadDelay or 2.5)
	npc.CurrentAmmo = npc.Config.ClipCapacity or 30
	npc.IsReloading = false
end

-- ============================================
-- BEHAVIOR LOOP (AI STATE MACHINE)
-- ============================================

function NPCEngine.runBehaviorLoop(npc: NPCInstance)
	local spawnPosition = npc.RootPart.Position
	
	while not npc.IsDead and npc.Model.Parent do
		-- Find target
		local target = NPCEngine.findTarget(npc)
		npc.Target = target
		
		if target then
			-- COMBAT STATE: Move toward target and attack
			local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if targetRoot then
				local distance = (targetRoot.Position - npc.RootPart.Position).Magnitude
				
				if distance > npc.Config.AttackRadius * 0.8 then
					-- Move toward target
					local pathResult = NavigationEngine.computePath(
						npc.RootPart.Position,
						targetRoot.Position
					)
					
					if pathResult.Success and pathResult.Waypoints then
						-- Follow path (simplified - in production, iterate through waypoints)
						npc.Humanoid:MoveTo(pathResult.Waypoints[2].Position)
					end
				else
					-- In attack range, attempt attack
					NPCEngine.attemptAttack(npc, target)
				end
			end
		elseif npc.Config.PatrolEnabled then
			-- PATROL STATE: Wander within patrol radius
			local patrolTarget = spawnPosition + Vector3.new(
				math.random(-npc.Config.PatrolRadius, npc.Config.PatrolRadius),
				0,
				math.random(-npc.Config.PatrolRadius, npc.Config.PatrolRadius)
			)
			
			npc.Humanoid:MoveTo(patrolTarget)
			task.wait(3) -- Wait before choosing new patrol point
		else
			-- IDLE STATE
			task.wait(1)
		end
		
		task.wait(0.2) -- AI tick rate
	end
end

-- ============================================
-- DEATH & CLEANUP
-- ============================================

function NPCEngine.handleNPCDeath(npc: NPCInstance)
	npc.IsDead = true
	
	-- Ragdoll logic (if enabled)
	if npc.Config.RagdollEnabled then
		-- Convert to ragdoll (requires Ragdoll module from NPC kit)
		local ragdollModule = npc.Model:FindFirstChild("Ragdoll", true)
		if ragdollModule and ragdollModule:IsA("ModuleScript") then
			local ragdoll = require(ragdollModule)
			ragdoll(npc.Model)
		end
	end
	
	-- Destroy after delay (if enabled)
	if npc.Config.DestroyOnDeath then
		task.delay(5, function()
			if npc.Model then
				npc.Model:Destroy()
				NPCEngine.ActiveNPCs[npc.Model] = nil
			end
		end)
	end
end

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

function NPCEngine.getNPCByModel(model: Model): NPCInstance?
	return NPCEngine.ActiveNPCs[model]
end

function NPCEngine.getAllActiveNPCs(): {NPCInstance}
	local npcs = {}
	for _, npc in pairs(NPCEngine.ActiveNPCs) do
		table.insert(npcs, npc)
	end
	return npcs
end

function NPCEngine.assignTag(target: Model, tag: string)
	CollectionService:AddTag(target, tag)
end

function NPCEngine.removeTag(target: Model, tag: string)
	CollectionService:RemoveTag(target, tag)
end

return NPCEngine