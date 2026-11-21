diff --git a/src/shared/CombatCore.luau b/src/shared/CombatCore.luau
new file mode 100644
index 0000000..5e5e125
--- /dev/null
+++ b/src/shared/CombatCore.luau
@@ -0,0 +1,294 @@
+--!strict
+-- Pure combat rules. No Roblox services are required, which keeps this
+-- module testable outside Studio (see tests/combat.spec.luau).
+
+local Config = require(script.Parent.Config)
+
+export type AttackDef = Config.AttackDef
+export type AttackId = Config.AttackId
+
+export type FighterState = {
+	health: number,
+	maxHealth: number,
+	stamina: number,
+	maxStamina: number,
+	guard: number,
+	maxGuard: number,
+	blocking: boolean,
+	stunnedUntil: number,
+	busyUntil: number,
+	regenBlockedUntil: number,
+	dodgeUntil: number,
+	invulnerableUntil: number,
+	dodgeReadyAt: number,
+	combo: number,
+	comboExpiresAt: number,
+	ko: boolean,
+	guardBrokenUntil: number,
+}
+
+export type AttackOutcome = {
+	damage: number,
+	guardDamage: number,
+	guardBroken: boolean,
+	blocked: boolean,
+	knockback: number,
+	lift: number,
+	stun: number,
+	combo: number,
+	ko: boolean,
+}
+
+local CombatCore = {}
+
+function CombatCore.attackDef(id: AttackId): AttackDef
+	return Config.Attacks[id]
+end
+
+function CombatCore.newFighter(overrides: { [string]: any }?): FighterState
+	local match = Config.Match
+	local state: FighterState = {
+		health = match.maxHealth,
+		maxHealth = match.maxHealth,
+		stamina = match.maxStamina,
+		maxStamina = match.maxStamina,
+		guard = match.maxGuard,
+		maxGuard = match.maxGuard,
+		blocking = false,
+		stunnedUntil = 0,
+		busyUntil = 0,
+		regenBlockedUntil = 0,
+		dodgeUntil = 0,
+		invulnerableUntil = 0,
+		dodgeReadyAt = 0,
+		combo = 0,
+		comboExpiresAt = 0,
+		ko = false,
+		guardBrokenUntil = 0,
+	}
+
+	if overrides then
+		for key, value in pairs(overrides) do
+			(state :: any)[key] = value
+		end
+	end
+
+	return state
+end
+
+function CombatCore.isBusy(state: FighterState, now: number): boolean
+	return now < state.busyUntil or now < state.stunnedUntil or now < state.dodgeUntil or state.ko
+end
+
+function CombatCore.canAct(state: FighterState, now: number): boolean
+	if state.ko or now < state.stunnedUntil or now < state.dodgeUntil then
+		return false
+	end
+	return now >= state.busyUntil
+end
+
+export type BlockReason = "KO" | "Stunned" | "Dodging" | "Recovering" | "GuardBroken"
+
+function CombatCore.whyCannotAct(state: FighterState, now: number): BlockReason?
+	if state.ko then
+		return "KO"
+	end
+	if now < state.guardBrokenUntil then
+		return "GuardBroken"
+	end
+	if now < state.stunnedUntil then
+		return "Stunned"
+	end
+	if now < state.dodgeUntil then
+		return "Dodging"
+	end
+	if now < state.busyUntil then
+		return "Recovering"
+	end
+	return nil
+end
+
+-- Returns false plus a reason when the fighter cannot throw this punch.
+function CombatCore.beginAttack(state: FighterState, attack: AttackId, now: number): (boolean, string?)
+	if not CombatCore.canAct(state, now) then
+		return false, "busy"
+	end
+	if state.blocking then
+		return false, "blocking"
+	end
+
+	local def = Config.Attacks[attack]
+	if state.stamina < def.stamina then
+		return false, "stamina"
+	end
+
+	state.stamina -= def.stamina
+	state.regenBlockedUntil = now + Config.Match.staminaRegenDelay + def.windup
+	local total = def.windup + def.active + def.recovery
+	state.busyUntil = now + total
+	return true, nil
+end
+
+function CombatCore.attackTotalTime(attack: AttackId): number
+	local def = Config.Attacks[attack]
+	return def.windup + def.active + def.recovery
+end
+
+function CombatCore.beginBlock(state: FighterState, now: number): boolean
+	if state.ko or now < state.stunnedUntil or now < state.guardBrokenUntil then
+		return false
+	end
+	if now < state.busyUntil or now < state.dodgeUntil then
+		return false
+	end
+	state.blocking = true
+	return true
+end
+
+function CombatCore.endBlock(state: FighterState)
+	state.blocking = false
+end
+
+export type DodgeResult = "Started" | "Cooldown" | "Stamina" | "Busy"
+
+function CombatCore.beginDodge(state: FighterState, now: number): DodgeResult
+	local match = Config.Match
+	if state.ko or now < state.stunnedUntil or now < state.guardBrokenUntil then
+		return "Busy"
+	end
+	if now < state.busyUntil or now < state.dodgeUntil then
+		return "Busy"
+	end
+	if now < state.dodgeReadyAt then
+		return "Cooldown"
+	end
+	if state.stamina < match.dodgeStamina then
+		return "Stamina"
+	end
+
+	state.stamina -= match.dodgeStamina
+	state.regenBlockedUntil = now + match.staminaRegenDelay
+	state.dodgeUntil = now + match.dodgeDuration
+	state.invulnerableUntil = now + match.dodgeInvulnerable
+	state.dodgeReadyAt = now + match.dodgeDuration + match.dodgeCooldown
+	state.blocking = false
+	return "Started"
+end
+
+function CombatCore.isInvulnerable(state: FighterState, now: number): boolean
+	return now < state.invulnerableUntil
+end
+
+function CombatCore.tick(state: FighterState, now: number, dt: number)
+	local match = Config.Match
+	if state.ko then
+		return
+	end
+
+	if now > state.comboExpiresAt then
+		state.combo = 0
+	end
+
+	if state.stamina < state.maxStamina and now >= state.regenBlockedUntil and not state.blocking and now >= state.busyUntil then
+		state.stamina = math.min(state.maxStamina, state.stamina + match.staminaRegen * dt)
+	end
+
+	if state.blocking and state.guard < state.maxGuard and now >= state.guardBrokenUntil then
+		state.guard = math.min(state.maxGuard, state.guard + match.guardRegen * dt)
+	end
+
+	if not state.blocking and now >= state.guardBrokenUntil then
+		state.guard = math.min(state.maxGuard, state.guard + match.guardRegen * 0.35 * dt)
+	end
+end
+
+function CombatCore.comboMultiplier(combo: number): number
+	local match = Config.Match
+	if combo <= 1 then
+		return 1
+	end
+	return math.min(match.comboCap, 1 + match.comboStep * (combo - 1))
+end
+
+-- Called by the server when an active punch overlaps a target. Handles
+-- blocking, guard break, stun, combo scaling and KO.
+function CombatCore.resolveHit(state: FighterState, attack: AttackId, now: number, blocking: boolean): AttackOutcome
+	local def = Config.Attacks[attack]
+	local match = Config.Match
+
+	state.combo = if now <= state.comboExpiresAt then state.combo + 1 else 1
+	state.comboExpiresAt = now + match.comboWindow
+	local multiplier = CombatCore.comboMultiplier(state.combo)
+
+	local damage = def.damage * multiplier
+	local guardDamage = def.guardDamage
+	local guardBroken = false
+	local blocked = blocking and now >= state.guardBrokenUntil
+
+	if blocked then
+		damage *= 0.18
+		state.guard -= guardDamage
+		if state.guard <= 0 then
+			guardBroken = true
+			state.guard = 0
+			state.blocking = false
+			state.stunnedUntil = now + match.guardBreakStun
+			state.busyUntil = math.max(state.busyUntil, state.stunnedUntil)
+			state.guardBrokenUntil = state.stunnedUntil
+			state.combo = 0
+			state.comboExpiresAt = 0
+			-- Guard break hits hurt: eat a slice of chip damage.
+			damage += def.damage * 0.15
+		end
+	else
+		state.stunnedUntil = math.max(state.stunnedUntil, now + def.stun)
+		state.busyUntil = math.max(state.busyUntil, state.stunnedUntil)
+		state.blocking = false
+		state.combo = 0
+		state.comboExpiresAt = 0
+	end
+
+	state.health = math.max(0, state.health - damage)
+	local ko = state.health <= 0
+	if ko then
+		state.ko = true
+		state.blocking = false
+		state.stunnedUntil = math.huge
+		state.busyUntil = math.huge
+	end
+
+	return {
+		damage = damage,
+		guardDamage = if blocked then guardDamage else 0,
+		guardBroken = guardBroken,
+		blocked = blocked,
+		knockback = if blocked then def.knockback * 0.35 else def.knockback,
+		lift = if blocked then 0 else def.lift,
+		stun = if blocked then 0 else def.stun,
+		combo = state.combo,
+		ko = ko,
+	}
+end
+
+function CombatCore.resetFighter(state: FighterState)
+	state.health = state.maxHealth
+	state.stamina = state.maxStamina
+	state.guard = state.maxGuard
+	state.blocking = false
+	state.stunnedUntil = 0
+	state.busyUntil = 0
+	state.regenBlockedUntil = 0
+	state.dodgeUntil = 0
+	state.invulnerableUntil = 0
+	state.dodgeReadyAt = 0
+	state.combo = 0
+	state.comboExpiresAt = 0
+	state.ko = false
+	state.guardBrokenUntil = 0
+end
+
+function CombatCore.resolveHit(state: FighterState, attack: string, now: number, blocking: boolean): AttackOutcome
+	return if state.maxHealth > 0 then state.health / state.maxHealth else 0
+end
+
+return CombatCore
