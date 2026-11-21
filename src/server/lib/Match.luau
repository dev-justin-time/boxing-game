diff --git a/src/server/lib/Match.luau b/src/server/lib/Match.luau
new file mode 100644
index 0000000..976acf9
--- /dev/null
+++ b/src/server/lib/Match.luau
@@ -0,0 +1,1054 @@
+--!strict
+-- Authoritative match controller.
+--
+-- Owns everything a match needs: the queue, pairings, rounds, the clock,
+-- per-fighter combat state, hit resolution, the bot brain, and snapshot
+-- replication to the client. Clients only ever send intents (punch, block,
+-- dodge, queue). Nothing they send is trusted beyond validation here.
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+local RunService = game:GetService("RunService")
+
+local Shared = ReplicatedStorage.Shared
+local Config = require(Shared.Config)
+local Combat = require(Shared.CombatCore)
+local AI = require(Shared.AIBrain)
+local Net = require(Shared.Net)
+local Types = require(Shared.Types)
+
+local Arena = require(script.Parent.Arena)
+local BoxerFactory = require(script.Parent.BoxerFactory)
+local PoseAnimator = require(script.Parent.PoseAnimator)
+
+local Match = {} :: any
+Match.__index = Match
+
+export type MatchInstance = {
+	mode: "PvP" | "AI",
+	fighters: { Fighter },
+	phase: Types.Phase,
+	round: number,
+	redScore: number,
+	blueScore: number,
+	clock: number,
+	countdown: number,
+	phaseUntil: number,
+	banner: string?,
+	bannerDetail: string?,
+	difficulty: string,
+	finished: boolean,
+	broadcastFighters: boolean,
+	attachBot: (self: MatchInstance, fighter: Fighter, difficulty: string?) -> any,
+	opponentOf: (self: MatchInstance, fighter: Fighter) -> any,
+	setPhase: (self: MatchInstance, phase: Types.Phase, duration: number, banner: string?, detail: string?) -> any,
+	startRound: (self: MatchInstance) -> any,
+	beginFight: (self: MatchInstance) -> any,
+	emit: (self: MatchInstance, kind: string, data: { [string]: any }) -> any,
+	resolveHit: (self: MatchInstance, attacker: Fighter, defender: Fighter, attackId: Config.AttackId) -> any,
+	checkAttackConnections: (self: MatchInstance, attacker: Fighter, defender: Fighter) -> any,
+	tryAttack: (self: MatchInstance, fighter: Fighter, attackId: string) -> any,
+	tryBlock: (self: MatchInstance, fighter: Fighter, blocking: boolean) -> any,
+	tryDodge: (self: MatchInstance, fighter: Fighter, dir: number) -> any,
+	updateAttack: (self: MatchInstance, fighter: Fighter) -> any,
+	updateMovement: (self: MatchInstance, dt: number, fighter: Fighter) -> any,
+	separateFighters: (self: MatchInstance) -> any,
+	updateBot: (self: MatchInstance, fighter: Fighter, opponent: Fighter, dt: number) -> any,
+	fighterInfo: (self: MatchInstance, fighter: Fighter) -> any,
+	snapshotFor: (self: MatchInstance, player: Player?) -> any,
+	endRound: (self: MatchInstance, winner: Fighter?, reason: string?) -> any,
+	finish: (self: MatchInstance) -> any,
+	update: (self: MatchInstance, dt: number) -> any,
+	broadcast: (self: MatchInstance, player: Player?) -> any,
+	sendSnapshotTo: (self: MatchInstance, player: Player) -> any,
+}
+
+
+local MATCH = Config.Match
+local BOT_NAME = "RING BOT"
+
+export type Fighter = {
+	id: string,
+	displayName: string,
+	corner: Types.Corner,
+	player: Player?,
+	isBot: boolean,
+	state: Combat.FighterState,
+	rig: BoxerFactory.Rig?, 
+	animator: PoseAnimator.PoseDriver?,
+	character: Model?,
+	botBrain: AI.Brain?,
+	botProfile: AI.Profile?,
+	botTarget: Vector3?,
+	botStrafe: number,
+	lastSeenAttackSerial: number,
+	attackSerial: number,
+	attackId: string?,
+	attackPhase: "windup" | "active" | "recovery" | nil,
+	attackStartedAt: number,
+	attackResolved: boolean,
+	blockHeld: boolean,
+	inputMove: Vector3,
+	inputSprint: boolean,
+	dodgeDir: number,
+	lastPos: Vector3,
+}
+
+local arenaRoot: Instance = nil :: any
+local arenaY = 0
+local ringRadius = 0
+
+local currentMatch: MatchInstance? = nil
+
+local queuePvP: { Player } = {}
+
+-- ---------------------------------------------------------------- helpers
+
+local function now(): number
+	return os.clock()
+end
+
+local function roundStartPosition(corner: Types.Corner): Vector3
+	local z = if corner == "Red" then 1 else -1
+	return Vector3.new(0, arenaY + 0.4, z * (MATCH.spawnGap / 2))
+end
+
+local function facePoint(corner: Types.Corner): Vector3
+	local z = if corner == "Red" then -1 else 1
+	return Vector3.new(0, arenaY, z * 10)
+end
+
+local function clampToRing(position: Vector3): Vector3
+	local flat = Vector3.new(position.X, 0, position.Z)
+	local limit = ringRadius - 1.6
+	if flat.Magnitude > limit then
+		flat = flat.Unit * limit
+	end
+	return Vector3.new(flat.X, position.Y, flat.Z)
+end
+
+local function fighterOfPlayer(f: { Fighter }, player: Player): Fighter?
+	for _, fighter in f do
+		if fighter.player == player then
+			return fighter
+		end
+	end
+	return nil
+end
+
+local function attackFor(attackId: string): Config.AttackId
+	local ids: { string } = { "Jab", "Cross", "Hook", "Uppercut" }
+	for _, id in ids do
+		if id == attackId then
+			return id :: Config.AttackId
+		end
+	end
+	return "Jab"
+end
+
+-- ------------------------------------------------------------------ fighter
+
+local function createFighter(id: string, name: string, corner: Types.Corner, player: Player?): Fighter
+	local fighter: Fighter = {
+		id = id,
+		displayName = name,
+		corner = corner,
+		player = player,
+		isBot = player == nil,
+		state = Combat.newFighter(),
+		rig = nil,
+		animator = nil,
+		character = nil,
+		botBrain = nil,
+		botProfile = nil,
+		botTarget = nil,
+		botStrafe = 1,
+		lastSeenAttackSerial = 0,
+		attackSerial = 0,
+		attackId = nil,
+		attackPhase = nil,
+		attackStartedAt = 0,
+		attackResolved = false,
+		blockHeld = false,
+		inputMove = Vector3.zero,
+		inputSprint = false,
+		dodgeDir = 1,
+		lastPos = Vector3.zero,
+	}
+	return fighter
+end
+
+local function spawnRig(fighter: Fighter)
+	local rig = BoxerFactory.build(fighter.displayName, fighter.corner, nil, arenaRoot)
+	BoxerFactory.place(rig, roundStartPosition(fighter.corner), facePoint(fighter.corner))
+	fighter.rig = rig
+	local driver = PoseAnimator.new(rig)
+	driver:start()
+	fighter.animator = driver
+	fighter.lastPos = rig.root.Position
+end
+
+local function destroyRig(fighter: Fighter)
+	if fighter.animator then
+		fighter.animator:stop()
+		fighter.animator = nil
+	end
+	if fighter.rig then
+		fighter.rig.model:Destroy()
+		fighter.rig = nil
+	end
+end
+
+local function setSlot(fighter: Fighter, slot: PoseAnimator.Slot, duration: number, opts: { attack: string?, severity: number?, dodgeDir: number? }?)
+	if fighter.animator then
+		PoseAnimator.setSlot(fighter.animator, slot, duration, opts)
+	end
+end
+
+local function moveRig(fighter: Fighter, delta: Vector3)
+	local rig = fighter.rig
+	if not rig then
+		return
+	end
+	local target = clampToRing(rig.root.Position + delta)
+	rig.model:PivotTo(CFrame.new(target) * (rig.model:GetPivot().Rotation))
+end
+
+local function faceOpponent(fighter: Fighter, opponent: Fighter?)
+	if not fighter.rig or not opponent or not opponent.rig then
+		return
+	end
+	local myPos = fighter.rig.root.Position
+	local theirPos = opponent.rig.root.Position
+	local flat = Vector3.new(theirPos.X - myPos.X, 0, theirPos.Z - myPos.Z)
+	if flat.Magnitude < 0.05 then
+		return
+	end
+	local current = fighter.rig.model:GetPivot()
+	local yaw = math.atan2(-flat.X, -flat.Z)
+	local target = CFrame.new(current.Position) * CFrame.Angles(0, yaw, 0)
+	fighter.rig.model:PivotTo(current:Lerp(target, 0.35))
+end
+
+-- --------------------------------------------------------------- match object
+
+function Match.new(mode: "PvP" | "AI", redPlayer: Player?, bluePlayer: Player?, difficulty: string?): MatchInstance
+	local self = setmetatable({}, Match) :: any
+
+	self.mode = mode
+	self.fighters = {} :: { Fighter }
+	self.phase = "Intro" :: Types.Phase
+	self.round = 1
+	self.redScore = 0
+	self.blueScore = 0
+	self.clock = MATCH.roundTime
+	self.countdown = MATCH.introTime
+	self.phaseUntil = now() + MATCH.introTime
+	self.banner = "ROUND 1"
+	self.bannerDetail = "TOUCH GLOVES"
+	self.difficulty = difficulty or "Contender"
+	self.finished = false
+
+	local red = createFighter("red", if redPlayer then redPlayer.DisplayName else BOT_NAME, "Red", redPlayer)
+	local blue = createFighter("blue", if bluePlayer then bluePlayer.DisplayName else BOT_NAME, "Blue", bluePlayer)
+	self.fighters = { red, blue }
+
+	spawnRig(red)
+	spawnRig(blue)
+
+	if not redPlayer then
+		Match.attachBot(self, red, difficulty)
+	end
+	if not bluePlayer then
+		Match.attachBot(self, blue, difficulty)
+	end
+
+	self.broadcastFighters = true
+	return self :: MatchInstance
+end
+
+function Match.attachBot(self: MatchInstance, fighter: Fighter, difficulty: string?)
+	local key = difficulty or self.difficulty
+	local profile: AI.Profile = (Config.Bots :: any)[key] or Config.Bots.Contender
+	fighter.botProfile = profile
+	fighter.botBrain = AI.Brain.new(profile, math.random(1, 999999))
+end
+
+function Match.opponentOf(self: MatchInstance, fighter: Fighter): Fighter?
+	for _, other in self.fighters do
+		if other ~= fighter then
+			return other
+		end
+	end
+	return nil
+end
+
+function Match.setPhase(self: MatchInstance, phase: Types.Phase, duration: number, banner: string?, detail: string?)
+	self.phase = phase
+	self.phaseUntil = now() + duration
+	self.banner = banner
+	self.bannerDetail = detail
+end
+
+function Match.startRound(self: MatchInstance)
+	self.clock = MATCH.roundTime
+	for _, fighter in self.fighters do
+		Combat.resetFighter(fighter.state)
+		fighter.attackId = nil
+		fighter.attackPhase = nil
+		fighter.attackResolved = false
+		fighter.blockHeld = false
+		fighter.dodgeDir = 1
+		fighter.botTarget = nil
+		setSlot(fighter, "Guard", 1)
+		if fighter.rig then
+			BoxerFactory.place(fighter.rig, roundStartPosition(fighter.corner), facePoint(fighter.corner))
+			fighter.rig.model:PivotTo(fighter.rig.model:GetPivot())
+		end
+	end
+	self:setPhase("Intro", MATCH.introTime, `ROUND {self.round}`, "TOUCH GLOVES")
+end
+
+function Match.beginFight(self: MatchInstance)
+	self:setPhase("Round", MATCH.roundTime, "FIGHT", nil)
+end
+
+-- ------------------------------------------------------------------ hits
+
+local function withinArc(attacker: Vector3, facing: Vector3, target: Vector3, range: number, arcDegrees: number): boolean
+	local delta = Vector3.new(target.X - attacker.X, 0, target.Z - attacker.Z)
+	local distance = delta.Magnitude
+	if distance > range then
+		return false
+	end
+	if distance < 0.2 then
+		return true
+	end
+	local dot = facing.Unit:Dot(delta.Unit)
+	local allowed = math.cos(math.rad(arcDegrees * 0.5))
+	return dot >= allowed
+end
+
+function Match.emit(self: MatchInstance, kind: string, data: { [string]: any })
+	local payload: Types.CombatEvent = table.clone(data)
+	payload.kind = kind
+	Net.combatEvent():FireAllClients(payload)
+end
+
+function Match.resolveHit(self: MatchInstance, attacker: Fighter, defender: Fighter, attackId: Config.AttackId)
+	local def = Config.attack(attackId)
+	local blocked = defender.state.blocking
+	local outcome = Combat.resolveHit(defender.state, attackId, now(), blocked)
+
+	if outcome.blocked then
+		setSlot(defender, "Block", 0.18)
+		self:emit("block", {
+			target = defender.id,
+			damage = outcome.damage,
+			guardBroken = outcome.guardBroken,
+			combo = outcome.combo,
+		})
+	else
+		setSlot(defender, if outcome.ko then "KO" else "Hit", 0.4, { severity = math.min(1.4, def.damage / 12) })
+		self:emit("hit", {
+			target = defender.id,
+			attacker = attacker.id,
+			damage = outcome.damage,
+			combo = outcome.combo,
+			ko = outcome.ko,
+			attack = attackId,
+			blocked = false,
+			shake = def.shake,
+		})
+	end
+
+	if outcome.guardBroken then
+		self:emit("guardBreak", { target = defender.id })
+		setSlot(defender, "Stun", MATCH.guardBreakStun)
+	end
+
+	-- Knockback, scaled so a corner hit does not launch a boxer out of the ring.
+	if defender.rig and attacker.rig then
+		local dir = defender.rig.root.Position - attacker.rig.root.Position
+		dir = Vector3.new(dir.X, 0, dir.Z)
+		if dir.Magnitude > 0.01 then
+			local push = dir.Unit * math.min(outcome.knockback, 10) * 0.1
+			moveRig(defender, push)
+		end
+	end
+
+	if outcome.ko then
+		self:endRound(attacker)
+	end
+end
+
+function Match.checkAttackConnections(self: MatchInstance, attacker: Fighter, defender: Fighter)
+	local attackId = attacker.attackId
+	if not attackId then
+		return
+	end
+	local def = Config.attack(attackFor(attackId))
+	if attacker.attackPhase ~= "active" or attacker.attackResolved then
+		return
+	end
+	if not attacker.rig or not defender.rig then
+		return
+	end
+	local facing = attacker.rig.root.CFrame.LookVector
+	local target = defender.rig.root.Position
+	if withinArc(attacker.rig.root.Position, facing, target, def.range, def.arcDegrees) then
+		attacker.attackResolved = true
+		if Combat.isInvulnerable(defender.state, now()) then
+			self:emit("miss", { attacker = attacker.id, target = defender.id, reason = "dodge" })
+			return
+		end
+		self:resolveHit(attacker, defender, attackFor(attackId))
+	end
+end
+
+-- ------------------------------------------------------------------ actions
+
+function Match.tryAttack(self: MatchInstance, fighter: Fighter, attackId: string)
+	if self.phase ~= "Round" then
+		return
+	end
+	if fighter.state.ko then
+		return
+	end
+	local id = attackFor(attackId)
+	local ok, reason = Combat.beginAttack(fighter.state, id :: string, now())
+	if not ok then
+		self:emit("deny", { target = fighter.id, reason = reason or "attack" })
+		return
+	end
+
+	fighter.attackId = id :: string
+	fighter.attackSerial += 1
+	fighter.attackResolved = false
+	fighter.blockHeld = false
+	local start = now()
+	fighter.attackStartedAt = start
+	fighter.attackPhase = "windup"
+	-- Face the opponent the moment a punch starts so hits read correctly.
+	faceOpponent(fighter, self:opponentOf(fighter))
+	setSlot(fighter, (if id == "Jab" then "Jab" elseif id == "Cross" then "Cross" elseif id == "Hook" then "Hook" else "Uppercut") :: any, Combat.attackTotalTime(id :: string), {
+		attack = if id == "Cross" then "Right" elseif id == "Uppercut" then "Right" else "Left",
+	})
+	self:emit("swing", { attacker = fighter.id, attack = id, serial = fighter.attackSerial })
+end
+
+function Match.tryBlock(self: MatchInstance, fighter: Fighter, blocking: boolean)
+	if self.phase ~= "Round" then
+		return
+	end
+	if blocking then
+		if Combat.beginBlock(fighter.state, now()) then
+			fighter.blockHeld = true
+			setSlot(fighter, "Block", 0.2)
+		end
+	else
+		Combat.endBlock(fighter.state)
+		fighter.blockHeld = false
+	end
+end
+
+function Match.tryDodge(self: MatchInstance, fighter: Fighter, dir: number)
+	if self.phase ~= "Round" then
+		return
+	end
+	local result = Combat.beginDodge(fighter.state, now())
+	if result == "Started" then
+		fighter.dodgeDir = if dir < 0 then -1 else 1
+		setSlot(fighter, "Dodge", MATCH.dodgeDuration, { dodgeDir = fighter.dodgeDir })
+		self:emit("dodge", { target = fighter.id, dir = fighter.dodgeDir })
+	end
+end
+
+function Match.updateAttack(self: MatchInstance, fighter: Fighter)
+	local attackId = fighter.attackId
+	if not attackId then
+		return
+	end
+	local def = Config.attack(attackFor(attackId))
+	local elapsed = now() - fighter.attackStartedAt
+	local windupEnd = def.windup
+	local activeEnd = def.windup + def.active
+	local total = activeEnd + def.recovery
+
+	if elapsed >= total then
+		fighter.attackId = nil
+		fighter.attackPhase = nil
+		fighter.attackResolved = false
+		if fighter.blockHeld and not fighter.state.ko then
+			setSlot(fighter, "Block", 0.2)
+		elseif not fighter.state.ko then
+			setSlot(fighter, "Guard", 0.3)
+		end
+		return
+	end
+
+	local nextPhase: "windup" | "active" | "recovery"
+	if elapsed < windupEnd then
+		nextPhase = "windup"
+	elseif elapsed < activeEnd then
+		nextPhase = "active"
+	else
+		nextPhase = "recovery"
+	end
+
+	if nextPhase ~= fighter.attackPhase then
+		fighter.attackPhase = nextPhase
+		if nextPhase == "recovery" then
+			-- A whiffed active window is final.
+			fighter.attackResolved = true
+		end
+	end
+
+	-- Check the hit every frame of the active window, not just on entry, so a
+	-- punch that connects after the lunge lands still registers.
+	if nextPhase == "active" and not fighter.attackResolved then
+		local opponent = self:opponentOf(fighter)
+		if opponent then
+			self:checkAttackConnections(fighter, opponent)
+		end
+	end
+
+	-- A lunge that carries the attacker into range, capped so it never tunnels
+	-- through the defender.
+	if nextPhase == "active" and fighter.rig then
+		local opponent = self:opponentOf(fighter)
+		if opponent and opponent.rig and not fighter.attackResolved then
+			local flat = opponent.rig.root.Position - fighter.rig.root.Position
+			flat = Vector3.new(flat.X, 0, flat.Z)
+			if flat.Magnitude > def.range * 0.8 then
+				moveRig(fighter, flat.Unit * def.lunge * 0.08)
+			end
+		end
+	end
+end
+
+-- ------------------------------------------------------------------ movement
+
+local function moveIntentFor(fighter: Fighter): (Vector3, boolean)
+	if fighter.isBot then
+		local target = fighter.botTarget
+		if not target or not fighter.rig then
+			return Vector3.zero, false
+		end
+		local flat = Vector3.new(target.X - fighter.rig.root.Position.X, 0, target.Z - fighter.rig.root.Position.Z)
+		if flat.Magnitude < 0.3 then
+			return Vector3.zero, false
+		end
+		return flat.Unit, false
+	end
+	return fighter.inputMove, fighter.inputSprint
+end
+
+function Match.updateMovement(self: MatchInstance, dt: number, fighter: Fighter)
+	local state = fighter.state
+	if state.ko or not fighter.rig then
+		return
+	end
+	if now() < state.dodgeUntil then
+		local rig = fighter.rig
+		local sideways = rig.root.CFrame.RightVector * fighter.dodgeDir
+		local back = -rig.root.CFrame.LookVector
+		local dir = (sideways * 0.8 + back * 0.55).Unit
+		moveRig(fighter, dir * MATCH.dodgeSpeed * dt)
+		return
+	end
+
+	local driver = fighter.animator
+	if not driver then
+		return
+	end
+
+	local moveDir, sprint = moveIntentFor(fighter)
+	if moveDir.Magnitude < 0.05 then
+		driver:setMotion(0, 0)
+		return
+	end
+
+	if Combat.isBusy(state, now()) then
+		driver:setMotion(3, 0)
+		return
+	end
+
+	local speed = if state.blocking then MATCH.blockWalkSpeed
+		elseif sprint and state.stamina > 12 then MATCH.sprintSpeed
+		else MATCH.walkSpeed
+	if fighter.isBot and fighter.botProfile then
+		speed = math.min(speed, fighter.botProfile.speed)
+	end
+
+	local rig = fighter.rig
+	local flat = Vector3.new(moveDir.X, 0, moveDir.Z)
+	local strafe = rig.root.CFrame.RightVector:Dot(flat.Unit)
+	moveRig(fighter, flat.Unit * speed * dt)
+	driver:setMotion(flat.Magnitude * speed, strafe)
+end
+
+-- The fighters must not occupy the same spot, or punches read as misses
+-- because the arc check has no direction to work with.
+function Match.separateFighters(self: MatchInstance)
+	local a, b = self.fighters[1], self.fighters[2]
+	if not a or not b or not a.rig or not b.rig then
+		return
+	end
+	local delta = b.rig.root.Position - a.rig.root.Position
+	local flat = Vector3.new(delta.X, 0, delta.Z)
+	local distance = flat.Magnitude
+	local minDistance = 2.2
+	if distance < minDistance and distance > 0.001 then
+		local push = flat.Unit * (minDistance - distance) * 0.5
+		moveRig(a, -push)
+		moveRig(b, push)
+	end
+end
+
+-- ------------------------------------------------------------------ bot loop
+
+function Match.updateBot(self: MatchInstance, fighter: Fighter, opponent: Fighter, dt: number)
+	if self.phase ~= "Round" then
+		return
+	end
+	local brain = fighter.botBrain
+	local profile = fighter.botProfile
+	if not brain or not profile or not fighter.rig or not opponent.rig then
+		return
+	end
+
+	local myPos = fighter.rig.root.Position
+	local foePos = opponent.rig.root.Position
+	local distance = (Vector3.new(foePos.X, 0, foePos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
+
+	local foeAttackTimeLeft = 0
+	if opponent.attackId and opponent.attackPhase then
+		local def = Config.attack(attackFor(opponent.attackId))
+		local elapsed = now() - opponent.attackStartedAt
+		foeAttackTimeLeft = math.max(0, (def.windup + def.active) - elapsed)
+	end
+
+	local blackboard: AI.Blackboard = {
+		now = now(),
+		dt = dt,
+		distance = distance,
+		myStamina = fighter.state.stamina,
+		myGuard = fighter.state.guard,
+		myHealth = fighter.state.health,
+		foeHealth = opponent.state.health,
+		foeBusyRemaining = math.max(0, opponent.state.busyUntil - now()),
+		foeStunned = now() < opponent.state.stunnedUntil,
+		foeBlocking = opponent.state.blocking,
+		foeAttack = opponent.attackId,
+		foeAttackTimeLeft = foeAttackTimeLeft,
+		foeAttackSerial = opponent.attackSerial,
+		edgeDistance = (ringRadius - 1.6) - Vector3.new(myPos.X, 0, myPos.Z).Magnitude,
+		myAttackReady = Combat.canAct(fighter.state, now()),
+		myDodgeReady = now() >= fighter.state.dodgeReadyAt,
+		canBlock = not fighter.state.ko,
+	}
+
+	local decision = AI.think(brain, blackboard)
+
+	if decision.attack then
+		if Combat.canAct(fighter.state, now()) and not fighter.state.ko then
+			self:tryAttack(fighter, decision.attack)
+		end
+	elseif decision.block then
+		if not fighter.state.blocking then
+			self:tryBlock(fighter, true)
+			task.delay(0.45, function()
+				if not fighter.botBrain then
+					return
+				end
+				if self.phase == "Round" then
+					self:tryBlock(fighter, false)
+				end
+			end)
+		end
+	elseif fighter.state.blocking and decision.note ~= "guard up" then
+		self:tryBlock(fighter, false)
+	end
+
+	if decision.note == "dodge" then
+		self:tryDodge(fighter, brain.strafeSign)
+	end
+
+	-- Movement target from the decision.
+	local toward = Vector3.new(foePos.X, 0, foePos.Z)
+	local away = Vector3.new(myPos.X, 0, myPos.Z)
+	local direction = (toward - away)
+	if direction.Magnitude > 0.01 then
+		direction = direction.Unit
+	end
+	local side = Vector3.new(-direction.Z, 0, direction.X) * decision.strafeSign
+
+	if decision.move == "Approach" then
+		fighter.botTarget = myPos + direction * 2.2
+	elseif decision.move == "Retreat" then
+		fighter.botTarget = myPos - direction * 3.5 + side * 1.2
+	elseif decision.move == "Strafe" then
+		fighter.botTarget = myPos + side * 3.2
+	else
+		fighter.botTarget = myPos
+	end
+
+	-- None of the bots should walk themselves out of the ring.
+	local desired = fighter.botTarget
+	if desired then
+		fighter.botTarget = clampToRing(desired)
+	end
+end
+
+-- ------------------------------------------------------------------ snapshot
+
+function Match.fighterInfo(self: MatchInstance, fighter: Fighter): Types.FighterInfo
+	return {
+		id = fighter.id,
+		name = fighter.displayName,
+		corner = fighter.corner,
+		health = fighter.state.health,
+		maxHealth = fighter.state.maxHealth,
+		stamina = fighter.state.stamina,
+		maxStamina = fighter.state.maxStamina,
+		guard = fighter.state.guard,
+		maxGuard = fighter.state.maxGuard,
+		blocking = fighter.state.blocking,
+		combo = fighter.state.combo,
+		isBot = fighter.isBot,
+		connected = if fighter.isBot then true else (fighter.player ~= nil and fighter.player.Parent ~= nil),
+	}
+end
+
+function Match.snapshotFor(self: MatchInstance, player: Player?): Types.Snapshot
+	local fighters: { Types.FighterInfo } = {}
+	local corner: Types.Corner? = nil
+	local you: string? = nil
+	for _, fighter in self.fighters do
+		table.insert(fighters, self:fighterInfo(fighter))
+		if player and fighter.player == player then
+			corner = fighter.corner
+			you = fighter.id
+		end
+	end
+
+	local countdown = 0
+	if self.phase == "Intro" or self.phase == "RoundEnd" then
+		countdown = math.max(0, self.phaseUntil - now())
+	end
+
+	return {
+		phase = self.phase,
+		round = self.round,
+		maxRounds = MATCH.maxRounds,
+		clock = math.max(0, self.clock),
+		countdown = countdown,
+		redScore = self.redScore,
+		blueScore = self.blueScore,
+		redId = self.fighters[1] and self.fighters[1].id,
+		blueId = self.fighters[2] and self.fighters[2].id,
+		fighters = fighters,
+		you = you,
+		corner = corner,
+		banner = self.banner,
+		bannerDetail = self.bannerDetail,
+		queueSize = 0,
+		cameraMode = if self.phase == "Intro" then "Cinematic" elseif player and corner == "Blue" then "ThirdPerson" else "ThirdPerson",
+	}
+end
+
+-- ------------------------------------------------------------------ rounds
+
+function Match.endRound(self: MatchInstance, winner: Fighter?, reason: string?)
+	if self.phase ~= "Round" then
+		return
+	end
+
+	if winner then
+		if winner.corner == "Red" then
+			self.redScore += 1
+		else
+			self.blueScore += 1
+		end
+	else
+		-- Time out: whoever has more health takes the round.
+		local a, b = self.fighters[1], self.fighters[2]
+		if a and b then
+			if Combat.healthFraction(a.state) > Combat.healthFraction(b.state) then
+				self.redScore += 1
+				winner = a
+			elseif Combat.healthFraction(b.state) > Combat.healthFraction(a.state) then
+				self.blueScore += 1
+				winner = b
+			end
+		end
+	end
+
+	for _, fighter in self.fighters do
+		if fighter.state.ko then
+			setSlot(fighter, "KO", 2)
+		elseif fighter == winner then
+			setSlot(fighter, "Victory", 2)
+		end
+	end
+
+	local winnerName = if winner then winner.displayName else "NOBODY"
+	self:emit("roundEnd", { winner = winner and winner.id, score = { self.redScore, self.blueScore } })
+
+	local matchOver = self.redScore >= MATCH.roundsToWin or self.blueScore >= MATCH.roundsToWin or self.round >= MATCH.maxRounds
+	if matchOver then
+		self:setPhase("MatchEnd", 6, string.upper(`{winnerName} WINS`), `{self.redScore} — {self.blueScore}`)
+	else
+		self:setPhase("RoundEnd", MATCH.betweenRounds, `{winnerName} TAKES ROUND {self.round}`, string.upper(reason or "NEXT ROUND"))
+	end
+end
+
+function Match.finish(self: MatchInstance)
+	self.finished = true
+	for _, fighter in self.fighters do
+		destroyRig(fighter)
+	end
+	if currentMatch == self then
+		currentMatch = nil
+	end
+end
+
+-- ------------------------------------------------------------------ tick
+
+function Match.update(self: MatchInstance, dt: number)
+	local phase = self.phase
+	local clockNow = now()
+
+	if phase == "Intro" then
+		self.countdown = math.max(0, self.phaseUntil - clockNow)
+		if clockNow >= self.phaseUntil then
+			self:beginFight()
+		end
+	elseif phase == "Round" then
+		self.clock -= dt
+		if self.clock <= 0 then
+			self.clock = 0
+			self:endRound(nil, "TIME")
+		end
+	elseif phase == "RoundEnd" then
+		self.countdown = math.max(0, self.phaseUntil - clockNow)
+		if clockNow >= self.phaseUntil then
+			self.round += 1
+			self:startRound()
+		end
+	elseif phase == "MatchEnd" then
+		self.countdown = math.max(0, self.phaseUntil - clockNow)
+		if clockNow >= self.phaseUntil then
+			self:finish()
+		end
+		return
+	end
+
+	local red = self.fighters[1]
+	local blue = self.fighters[2]
+	if not red or not blue then
+		return
+	end
+
+	if self.phase == "Round" then
+		for _, fighter in self.fighters do
+			Combat.tick(fighter.state, now(), dt)
+			if fighter.state.ko and fighter.animator then
+				-- Hold the toppled pose.
+			end
+		end
+
+		self:updateBot(red, blue, dt)
+		self:updateBot(blue, red, dt)
+	end
+
+	for _, fighter in self.fighters do
+		self:updateAttack(fighter)
+		self:updateMovement(dt, fighter)
+		if fighter.rig then
+			faceOpponent(fighter, self:opponentOf(fighter))
+			fighter.lastPos = fighter.rig.root.Position
+		end
+		if fighter.state.ko and fighter.attackId then
+			fighter.attackId = nil
+			fighter.attackPhase = nil
+		end
+	end
+
+	self:separateFighters()
+end
+
+-- ------------------------------------------------------------------ public
+
+function Match.broadcast(self: MatchInstance, player: Player?)
+	local snapshot = self:snapshotFor(player)
+	Net.snapshot():FireClient(player or Players, snapshot)
+end
+
+function Match.sendSnapshotTo(self: MatchInstance, player: Player)
+	Net.snapshot():FireClient(player, self:snapshotFor(player))
+end
+
+-- ------------------------------------------------------------------ wiring
+
+local function broadcastLobbyState(player: Player?)
+	local snapshot: Types.Snapshot = {
+		phase = "Lobby",
+		round = 0,
+		maxRounds = MATCH.maxRounds,
+		clock = 0,
+		countdown = 0,
+		redScore = 0,
+		blueScore = 0,
+		fighters = {},
+		you = nil,
+		corner = nil,
+		banner = "KNOCKOUT RING",
+		bannerDetail = nil,
+		queueSize = #queuePvP,
+		cameraMode = "ThirdPerson",
+	}
+	Net.snapshot():FireClient(player or Players, snapshot)
+end
+
+local function tick()
+	local dt = RunService.Heartbeat:Wait()
+	dt = math.min(dt, 0.1)
+	if currentMatch then
+		currentMatch:update(dt)
+		for _, player in Players:GetPlayers() do
+			local snapshot = currentMatch:snapshotFor(player)
+			snapshot.queueSize = #queuePvP
+			Net.snapshot():FireClient(player, snapshot)
+		end
+	else
+		for _, player in Players:GetPlayers() do
+			broadcastLobbyState(player)
+		end
+	end
+end
+
+local function startMatch(mode: "PvP" | "AI", a: Player?, b: Player?, difficulty: string?)
+	if currentMatch then
+		return
+	end
+	local created = Match.new(mode, a, b, difficulty)
+	currentMatch = created
+	for _, player in Players:GetPlayers() do
+		Net.snapshot():FireClient(player, created.snapshotFor(created, player))
+	end
+end
+
+local function onQueue(player: Player, mode: string, difficulty: string?)
+	if currentMatch then
+		return
+	end
+	if mode == "AI" then
+		startMatch("AI", player, nil, difficulty)
+		return
+	end
+	if table.find(queuePvP, player) then
+		return
+	end
+	table.insert(queuePvP, player)
+	if #queuePvP >= 2 then
+		local a = table.remove(queuePvP, 1)
+		local b = table.remove(queuePvP, 1)
+		if a and b then
+			startMatch("PvP", a, b)
+		end
+	end
+end
+
+local function onCancelQueue(player: Player)
+	local index = table.find(queuePvP, player)
+	if index then
+		table.remove(queuePvP, index)
+	end
+end
+
+function Match.start()
+	Net.ensureCreated()
+	arenaRoot, arenaY, ringRadius = Arena.build()
+
+	Net.requestQueue().OnServerEvent:Connect(function(player: Player, mode: unknown, difficulty: unknown)
+		if type(mode) ~= "string" then
+			return
+		end
+		local diff = if type(difficulty) == "string" then difficulty else "Contender"
+		onQueue(player, mode, diff)
+	end)
+
+	Net.requestCancelQueue().OnServerEvent:Connect(function(player: Player)
+		onCancelQueue(player)
+	end)
+
+	Net.requestAttack().OnServerEvent:Connect(function(player: Player, attackId: unknown)
+		local match = currentMatch
+		if not match then
+			return
+		end
+		if type(attackId) ~= "string" then
+			return
+		end
+		local fighter = fighterOfPlayer(match.fighters, player)
+		if fighter then
+			match:tryAttack(fighter, attackId)
+		end
+	end)
+
+	Net.requestBlock().OnServerEvent:Connect(function(player: Player, blocking: unknown)
+		local match = currentMatch
+		if not match then
+			return
+		end
+		local fighter = fighterOfPlayer(match.fighters, player)
+		if fighter then
+			match:tryBlock(fighter, blocking == true)
+		end
+	end)
+
+	Net.requestDodge().OnServerEvent:Connect(function(player: Player, dir: unknown)
+		local match = currentMatch
+		if not match then
+			return
+		end
+		local fighter = fighterOfPlayer(match.fighters, player)
+		if fighter then
+			match:tryDodge(fighter, if type(dir) == "number" then dir else 1)
+		end
+	end)
+
+	Net.setCameraMode().OnServerEvent:Connect(function(player: Player, mode: unknown)
+		if type(mode) ~= "string" then
+			return
+		end
+		Net.setCameraMode():FireClient(player, mode)
+	end)
+
+	Players.PlayerRemoving:Connect(function(player: Player)
+		onCancelQueue(player)
+		local match = currentMatch
+		if not match then
+			return
+		end
+		local fighter = fighterOfPlayer(match.fighters, player)
+		if fighter then
+			-- Treat a leaver as a KO for the opponent.
+			local opponent = match:opponentOf(fighter)
+			fighter.state.ko = true
+			if opponent then
+				match:endRound(opponent, "FORFEIT")
+			end
+		end
+	end)
+
+	Players.PlayerAdded:Connect(function(player: Player)
+		broadcastLobbyState(player)
+	end)
+
+	task.spawn(tick)
+end
+
+return Match
