diff --git a/src/shared/AIBrain.luau b/src/shared/AIBrain.luau
new file mode 100644
index 0000000..cd7928c
--- /dev/null
+++ b/src/shared/AIBrain.luau
@@ -0,0 +1,293 @@
+--!strict
+-- Bot boxing brain. Pure: takes a plain table snapshot of the fight and
+-- returns what the bot wants to do. The server applies the decision to a
+-- real Humanoid, so this stays unit-testable with Lune.
+
+local Config = require(script.Parent.Config)
+
+export type Profile = {
+	reaction: number,
+	blockChance: number,
+	dodgeChance: number,
+	aggression: number,
+	comboLove: number,
+	punish: number,
+	speed: number,
+}
+
+export type Move = "Approach" | "Retreat" | "Strafe" | "Hold"
+
+export type Decision = {
+	move: Move,
+	strafeSign: number,
+	attack: Config.AttackId?,
+	block: boolean,
+	sprint: boolean,
+	note: string,
+}
+
+export type Blackboard = {
+	now: number,
+	dt: number,
+	distance: number,
+	myStamina: number,
+	myGuard: number,
+	myHealth: number,
+	foeHealth: number,
+	foeBusyRemaining: number,
+	foeStunned: boolean,
+	foeBlocking: boolean,
+	foeAttack: Config.AttackId?,
+	foeAttackTimeLeft: number,
+	foeAttackSerial: number,
+	edgeDistance: number,
+	myAttackReady: boolean,
+	myDodgeReady: boolean,
+	canBlock: boolean,
+}
+
+export type Brain = {
+	profile: Profile,
+	rng: () -> number,
+	nextDecisionAt: number,
+	lastAttackSerial: number,
+	reactionToSerial: number,
+	queuedAttack: Config.AttackId?,
+	pendingDodge: number,
+	strafeSign: number,
+	strafeFlipAt: number,
+	comboLeft: number,
+	comboUntil: number,
+	lastAction: string,
+}
+
+local Brain = {}
+Brain.__index = Brain
+
+local ATTACK_RANGE: { [Config.AttackId]: number } = {
+	Jab = Config.Attacks.Jab.range * 0.92,
+	Cross = Config.Attacks.Cross.range * 0.92,
+	Hook = Config.Attacks.Hook.range * 0.92,
+	Uppercut = Config.Attacks.Uppercut.range * 0.92,
+}
+
+function Brain.new(profile: Profile, seed: number?): Brain
+	local s = seed or 1234567
+	local self = setmetatable({}, Brain) :: any
+	self.profile = profile
+	self.rng = function(): number
+		-- Deterministic xorshift so tests can assert on behavior.
+		s = bit32.bxor(s, s * 4)
+		s = bit32.bxor(s, math.floor(s / 2))
+		return (s % 10000) / 10000
+	end
+	self.nextDecisionAt = 0
+	self.lastAttackSerial = 0
+	self.reactionToSerial = -1
+	self.queuedAttack = nil
+	self.pendingDodge = 0
+	self.strafeSign = 1
+	self.strafeFlipAt = 0
+	self.comboLeft = 0
+	self.comboUntil = 0
+	self.lastAction = "Hold"
+	return self
+end
+
+local function affordable(stamina: number, attack: Config.AttackId): boolean
+	return stamina >= Config.Attacks[attack].stamina + 4
+end
+
+-- Pick the punch that fits the gap and the bot's current stamina.
+local function chooseAttack(bb: Blackboard, profile: Profile, rng: () -> number, punish: boolean): Config.AttackId?
+	local pool: { Config.AttackId } = {}
+
+	for _, id in Config.AttackOrder do
+		local reach = ATTACK_RANGE[id]
+		if bb.distance <= reach and affordable(bb.myStamina, id) then
+			table.insert(pool, id)
+		end
+	end
+
+	if #pool == 0 then
+		return nil
+	end
+
+	if punish then
+		-- Heaviest punch that fits, respecting the punish skill dial.
+		for i = #pool, 1, -1 do
+			if rng() <= profile.punish then
+				return pool[i]
+			end
+		end
+		return pool[#pool]
+	end
+
+	-- Mix light and heavy: weight toward the cheap punches.
+	local roll = rng()
+	if roll < 0.45 and affordable(bb.myStamina, "Jab") and bb.distance <= ATTACK_RANGE.Jab then
+		return "Jab"
+	elseif roll < 0.72 and affordable(bb.myStamina, "Cross") and bb.distance <= ATTACK_RANGE.Cross then
+		return "Cross"
+	elseif roll < 0.9 and affordable(bb.myStamina, "Hook") and bb.distance <= ATTACK_RANGE.Hook then
+		return "Hook"
+	elseif affordable(bb.myStamina, "Uppercut") and bb.distance <= ATTACK_RANGE.Uppercut then
+		return "Uppercut"
+	end
+	return pool[#pool]
+end
+
+function Brain.think(self: Brain, bb: Blackboard): Decision
+	local profile = self.profile
+	local now = bb.now
+	local decision: Decision = {
+		move = "Hold",
+		strafeSign = self.strafeSign,
+		attack = nil,
+		block = false,
+		sprint = false,
+		note = "hold",
+	}
+
+	if now >= self.strafeFlipAt then
+		self.strafeSign = if self.rng() < 0.5 then 1 else -1
+		self.strafeFlipAt = now + 1.2 + self.rng() * 1.4
+	end
+	decision.strafeSign = self.strafeSign
+
+	-- 1. React to a new incoming punch. Reaction is applied by delaying the
+	-- defensive response instead of teleport-blocking on the same frame.
+	local incoming = bb.foeAttack ~= nil and bb.foeAttackTimeLeft > 0
+	if incoming and bb.foeAttackSerial ~= self.lastAttackSerial then
+		self.lastAttackSerial = bb.foeAttackSerial
+		self.reactionToSerial = now + profile.reaction + self.rng() * 0.06
+		local roll = self.rng()
+		if roll < profile.dodgeChance and bb.myDodgeReady and bb.myStamina >= Config.Match.dodgeStamina then
+			self.pendingDodge = self.reactionToSerial
+		elseif roll < profile.dodgeChance + profile.blockChance and bb.canBlock then
+			self.queuedAttack = nil
+			self.comboLeft = 0
+			self.reactionToSerial = now + profile.reaction
+		end
+	end
+
+	local reacting = incoming and self.reactionToSerial >= 0 and now >= self.reactionToSerial
+	if reacting then
+		if now >= self.pendingDodge then
+			self.pendingDodge = 0
+			decision.move = "Strafe"
+			decision.attack = nil
+			decision.block = false
+			decision.note = "dodge"
+			return decision
+		end
+		if self.pendingDodge > 0 then
+			decision.move = "Retreat"
+			decision.note = "winding up dodge"
+			return decision
+		end
+		-- Attack will land soon: hold guard, back off slightly.
+		decision.block = true
+		decision.move = "Retreat"
+		decision.note = "guard up"
+		if bb.distance > Config.Attacks.Uppercut.range + 3 then
+			decision.move = "Hold"
+		end
+		return decision
+	end
+
+	-- 2. Do not walk into a punch: stop just outside their reach while their
+	-- attack is unresolved.
+	if incoming and bb.foeAttackTimeLeft > 0 and bb.distance < 5 and self.rng() < 0.5 then
+		decision.move = "Retreat"
+		decision.note = "respect the swing"
+		return decision
+	end
+
+	-- 3. Queue a combo continuation without waiting another full reaction.
+	if self.comboLeft > 0 and now < self.comboUntil and bb.myAttackReady and bb.distance < 4.2 then
+		local followUp = chooseAttack(bb, profile, self.rng, false)
+		if followUp then
+			self.comboLeft -= 1
+			self.comboUntil = now + 0.55
+			decision.attack = followUp
+			decision.move = if bb.distance > ATTACK_RANGE[followUp] then "Approach" else "Hold"
+			decision.note = "combo"
+			return decision
+		end
+		self.comboLeft = 0
+	end
+
+	if now < self.nextDecisionAt then
+		decision.move = if bb.distance > 4.6 then "Approach" else "Strafe"
+		decision.strafeSign = self.strafeSign
+		return decision
+	end
+	self.nextDecisionAt = now + profile.reaction
+
+	-- 4. Punish a whiffed punch, a stun or a guard break.
+	local punishWindow = bb.foeStunned or (bb.foeBusyRemaining > 0.16 and bb.foeBusyRemaining < 0.5)
+	if punishWindow and bb.distance < 5 and bb.myAttackReady and self.rng() < 0.55 + profile.punish * 0.45 then
+		local pick = chooseAttack(bb, profile, self.rng, true)
+		if pick then
+			decision.attack = pick
+			decision.move = if bb.distance > ATTACK_RANGE[pick] then "Approach" else "Hold"
+			decision.note = "punish"
+			if self.rng() < profile.comboLove then
+				self.comboLeft = 1 + math.floor(self.rng() * 2)
+				self.comboUntil = now + 1.1
+			end
+			return decision
+		end
+	end
+
+	-- 5. Keep the guard honest when the other corner is swinging freely.
+	if bb.foeBlocking and bb.distance < 4.5 and self.rng() < 0.4 then
+		decision.attack = chooseAttack(bb, profile, self.rng, false)
+		decision.note = "break the shell"
+		if decision.attack == nil then
+			decision.move = "Strafe"
+		end
+		return decision
+	end
+
+	-- 6. Out of range: close the distance, cut the ring off at the edge.
+	if bb.distance > 4.4 then
+		decision.move = "Approach"
+		decision.sprint = bb.distance > 8 and bb.myStamina > 30
+		decision.note = "close in"
+		if bb.edgeDistance < 3.5 then
+			decision.move = "Strafe"
+			decision.note = "circle off the ropes"
+		end
+		return decision
+	end
+
+	-- 7. In range: swing at a rate driven by aggression and stamina.
+	local staminaFloor = if bb.myHealth < 34 then 45 else 18
+	if bb.myStamina > staminaFloor and self.rng() < profile.aggression then
+		local pick = chooseAttack(bb, profile, self.rng, false)
+		if pick then
+			decision.attack = pick
+			decision.note = "work the body"
+			if self.rng() < profile.comboLove * 0.7 then
+				self.comboLeft = 1
+				self.comboUntil = now + 0.9
+			end
+			return decision
+		end
+	end
+
+	if bb.myStamina < staminaFloor then
+		decision.move = "Retreat"
+		decision.block = bb.canBlock
+		decision.note = "catch breath"
+		return decision
+	end
+
+	decision.move = "Strafe"
+	decision.note = "reset angle"
+	return decision
+end
+
+return Brain
