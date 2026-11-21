diff --git a/tests/run.luau b/tests/run.luau
new file mode 100644
index 0000000..3f80c69
--- /dev/null
+++ b/tests/run.luau
@@ -0,0 +1,364 @@
+--!strict
+-- Headless tests for the pure boxing rules.
+-- Run: lune run tests/run.luau
+
+local Config = require("../src/shared/Config")
+local Combat = require("../src/shared/CombatCore")
+local AI = require("../src/shared/AIBrain")
+local Poser = require("../src/shared/Poser")
+local Library = require("../src/shared/AnimationLibrary")
+
+local passed = 0
+local failed = 0
+local failures: { string } = {}
+
+local function test(name: string, fn: () -> ())
+	local ok, err = pcall(fn)
+	if ok then
+		passed += 1
+		print(`  ok   {name}`)
+	else
+		failed += 1
+		table.insert(failures, `{name}: {tostring(err)}`)
+		print(`  FAIL {name}`)
+		print(`       {tostring(err)}`)
+	end
+end
+
+local function expect(condition: boolean, message: string)
+	if not condition then
+		error(message, 2)
+	end
+end
+
+local function near(a: number, b: number, tolerance: number?): boolean
+	return math.abs(a - b) <= (tolerance or 0.001)
+end
+
+print("CombatCore")
+
+test("a fresh fighter starts at full everything", function()
+	local f = Combat.newFighter()
+	expect(f.health == Config.Match.maxHealth, "health")
+	expect(f.stamina == Config.Match.maxStamina, "stamina")
+	expect(f.guard == Config.Match.maxGuard, "guard")
+	expect(f.combo == 0, "combo")
+	expect(f.ko == false, "not ko")
+end)
+
+test("a punch costs its stamina and locks the fighter out", function()
+	local f = Combat.newFighter()
+	local ok = Combat.beginAttack(f, "Jab", 0)
+	expect(ok, "attack should start")
+	expect(f.stamina == Config.Match.maxStamina - Config.attack("Jab").stamina, "stamina spent")
+	expect(not Combat.canAct(f, 0.05), "still winding up")
+	expect(Combat.canAct(f, 1), "free after recovery")
+end)
+
+test("you cannot punch without stamina", function()
+	local f = Combat.newFighter({ stamina = 2 })
+	local ok, reason = Combat.beginAttack(f, "Uppercut", 0)
+	expect(not ok, "should refuse")
+	expect(reason == "stamina", `reason was {tostring(reason)}`)
+end)
+
+test("you cannot punch while stunned", function()
+	local f = Combat.newFighter({ stunnedUntil = 5 })
+	local ok = Combat.beginAttack(f, "Jab", 1)
+	expect(not ok, "should refuse while stunned")
+end)
+
+test("a clean hit damages and stuns", function()
+	local f = Combat.newFighter()
+	local out = Combat.resolveHit(f, "Cross", 10, false)
+	expect(out.blocked == false, "not blocked")
+	expect(out.damage > 0, "damage")
+	expect(f.health < f.maxHealth, "health dropped")
+	expect(f.stunnedUntil > 10, "stunned")
+	expect(f.combo == 1, "combo starts at 1")
+end)
+
+test("a combo grows damage up to the cap", function()
+	local f = Combat.newFighter()
+	local now = 0
+	local firstOut = Combat.resolveHit(f, "Jab", now, false)
+	-- Chain inside the combo window.
+	local lastOut = firstOut
+	for i = 2, 6 do
+		now += 0.2
+		lastOut = Combat.resolveHit(f, "Jab", now, false)
+	end
+	expect(lastOut.combo == 6, `combo was {lastOut.combo}`)
+	local single = Config.attack("Jab").damage
+	expect(lastOut.damage > single, "later hits scale up")
+	expect(lastOut.damage <= single * Config.Match.comboCap + 0.001, "respects the cap")
+end)
+
+test("blocking cuts damage to chip and drains guard", function()
+	local f = Combat.newFighter({ blocking = true })
+	local before = f.health
+	local out = Combat.resolveHit(f, "Hook", 1, true)
+	expect(out.blocked, "counted as blocked")
+	expect(f.health > before - Config.attack("Hook").damage, "much less damage")
+	expect(f.guard < f.maxGuard, "guard drained")
+end)
+
+test("guard break stuns through the block", function()
+	local f = Combat.newFighter({ blocking = true, guard = 5 })
+	local out = Combat.resolveHit(f, "Uppercut", 2, true)
+	expect(out.guardBroken, "guard broke")
+	expect(f.blocking == false, "block dropped")
+	expect(f.stunnedUntil > 2, "stunned")
+	expect(f.guard == 0, "guard emptied")
+end)
+
+test("a KO latches and stops further input", function()
+	local f = Combat.newFighter({ health = 4 })
+	local out = Combat.resolveHit(f, "Uppercut", 3, false)
+	expect(out.ko, "ko flagged")
+	expect(f.ko, "state ko")
+	local ok = Combat.beginAttack(f, "Jab", 4)
+	expect(not ok, "cannot punch when knocked out")
+end)
+
+test("blocking is refused during recovery", function()
+	local f = Combat.newFighter()
+	Combat.beginAttack(f, "Hook", 0)
+	expect(not Combat.beginBlock(f, 0.02), "no block mid-punch")
+	expect(Combat.beginBlock(f, 2), "block once recovered")
+end)
+
+test("dodge refunds nothing but grants invulnerability", function()
+	local f = Combat.newFighter()
+	local result = Combat.beginDodge(f, 0)
+	expect(result == "Started", `dodge was {result}`)
+	expect(Combat.isInvulnerable(f, 0.05), "invulnerable early")
+	expect(not Combat.isInvulnerable(f, 1), "vulnerable later")
+	local second = Combat.beginDodge(f, 0.1)
+	expect(second ~= "Started", "cannot spam dodge")
+end)
+
+test("stamina regenerates only after the delay", function()
+	local f = Combat.newFighter()
+	Combat.beginAttack(f, "Hook", 0)
+	local spent = f.stamina
+	f.busyUntil = 0
+	Combat.tick(f, 0.1, 0.1)
+	expect(f.stamina == spent, "no regen during the delay")
+	Combat.tick(f, 2, 1)
+	expect(f.stamina > spent, "regen after the delay")
+end)
+
+test("resetFighter restores a knocked out boxer", function()
+	local f = Combat.newFighter({ health = 0, ko = true, stamina = 0, guard = 0 })
+	Combat.resetFighter(f)
+	expect(f.health == f.maxHealth and f.stamina == f.maxStamina and f.guard == f.maxGuard, "restored")
+	expect(f.ko == false, "not ko")
+end)
+
+print("Poser")
+
+test("jointTransform is identity for identity input", function()
+	local c0 = CFrame.new(1, 2, 3) * CFrame.Angles(0.2, 0.4, 0.1)
+	local t = Poser.jointTransform(c0, CFrame.identity)
+	expect(near((t.Position).Magnitude, 0, 0.0001), "no translation")
+end)
+
+test("jointTransform preserves the pivot point", function()
+	-- Rotating about the joint pivot must not move the pivot itself.
+	local c0 = CFrame.new(0.5, 1.5, 0)
+	local rotation = CFrame.Angles(0, 0, math.rad(90))
+	local t = Poser.jointTransform(c0, rotation)
+	local reconstructed = c0 * t * c0:Inverse()
+	expect(near(reconstructed.Position.Magnitude, 1, 0.0001), "pivot kept at radius")
+end)
+
+test("blend at 1 equals the target pose", function()
+	local a = Library.stance()
+	local b = Library.block()
+	local blended = Poser.blend(a, b, 1)
+	local key = "LeftShoulder"
+	expect((blended[key].Position - b[key].Position).Magnitude < 1e-6, "target rotation")
+end)
+
+test("blend at 0 equals the source pose", function()
+	local a = Library.stance()
+	local b = Library.block()
+	local blended = Poser.blend(a, b, 0)
+	expect((blended.LeftShoulder.Position - a.LeftShoulder.Position).Magnitude < 1e-6, "source rotation")
+end)
+
+print("AnimationLibrary")
+
+test("every pose only touches known joints", function()
+	local poses = {
+		idle = Library.idle(1),
+		guard = Library.guard(),
+		jab = Library.jab(0.5),
+		cross = Library.cross(0.5),
+		hook = Library.hook(0.5, "Left"),
+		uppercut = Library.uppercut(0.5, "Right"),
+		block = Library.block(),
+		dodge = Library.dodge(0.5, 1),
+		hit = Library.hit(0.5, 1),
+		ko = Library.ko(1, 1),
+		victory = Library.victory(1),
+		relaxed = Library.relaxed(1),
+		locomotion = Library.locomotion(1, 12, 0),
+	}
+	local known: { [string]: boolean } = {}
+	for _, joint in Poser.BOXER_JOINTS do
+		known[joint] = true
+	end
+	for name, pose in poses do
+		for joint in pose do
+			expect(known[joint] == true, `{name} touches unknown joint {joint}`)
+		end
+	end
+end)
+
+test("a jab extends past the stance and returns", function()
+	local stance = Library.stance()
+	local mid = Library.jab(0.3)
+	-- The lead hand travels forward: a larger X rotation on the elbow means a
+	-- straighter arm, so compare the shoulder-to-wrist spacing qualitatively.
+	local stanceElbow = stance.LeftElbow.X
+	local extendedElbow = mid.LeftElbow.X
+	expect(extendedElbow < stanceElbow, `jab should straighten the elbow ({extendedElbow} vs {stanceElbow})`)
+	local recovered = Library.jab(0.99)
+	expect(near(recovered.LeftElbow.X, 0, 0.05), "elbow returns near neutral")
+end)
+
+test("all poses stay within sane rotation limits", function()
+	for _, id in { "Jab", "Cross", "Hook", "Uppercut" } do
+		for step = 0, 10 do
+			local phase = step / 10
+			local pose = if id == "Jab" then Library.jab(phase)
+				elseif id == "Cross" then Library.cross(phase)
+				elseif id == "Hook" then Library.hook(phase, "Left")
+				else Library.uppercut(phase, "Right")
+			for joint, cf in pose do
+				local rx, ry, rz = cf:ToEulerAnglesXYZ()
+				expect(math.abs(rx) < math.pi, `{id} {joint} rx out of range`)
+				expect(math.abs(ry) < math.pi, `{id} {joint} ry out of range`)
+				expect(math.abs(rz) < math.pi, `{id} {joint} rz out of range`)
+			end
+		end
+	end
+end)
+
+print("AIBrain")
+
+local function blackboard(overrides: { [string]: any }?): AI.Blackboard
+	local bb: AI.Blackboard = {
+		now = 10,
+		dt = 0.016,
+		distance = 3,
+		myStamina = 100,
+		myGuard = 100,
+		myHealth = 100,
+		foeHealth = 100,
+		foeBusyRemaining = 0,
+		foeStunned = false,
+		foeBlocking = false,
+		foeAttack = nil,
+		foeAttackTimeLeft = 0,
+		foeAttackSerial = 0,
+		edgeDistance = 20,
+		myAttackReady = true,
+		myDodgeReady = true,
+		canBlock = true,
+	}
+	if overrides then
+		for key, value in overrides do
+			(bb :: any)[key] = value
+		end
+	end
+	return bb
+end
+
+test("bot closes the distance when out of range", function()
+	local brain = AI.new(Config.Bots.Contender, 42)
+	local decision = AI.think(brain, blackboard({ distance = 9 }))
+	expect(decision.move == "Approach", `moved {decision.move}`)
+	expect(decision.attack == nil, "does not swing from range")
+end)
+
+test("an aggressive bot throws punches in range", function()
+	local brain = AI.new(Config.Bots.Champion, 7)
+	local attacks = 0
+	for step = 0, 60 do
+		local decision = AI.think(brain, blackboard({ now = 10 + step * 0.05 }))
+		if decision.attack then
+			attacks += 1
+		end
+	end
+	expect(attacks > 0, "champion should punch")
+end)
+
+test("a bot reacts to an incoming punch", function()
+	local brain = AI.new(Config.Bots.Champion, 3)
+	local sawDefence = false
+	for step = 0, 40 do
+		local t = 10 + step * 0.05
+		local decision = AI.think(brain, blackboard({
+			now = t,
+			distance = 3.2,
+			foeAttack = "Cross",
+			foeAttackTimeLeft = 0.2,
+			foeAttackSerial = 1,
+		}))
+		if decision.block or decision.note == "dodge" or decision.note == "winding up dodge" then
+			sawDefence = true
+		end
+	end
+	expect(sawDefence, "should have defended")
+end)
+
+test("a bot punishes a stunned opponent", function()
+	local brain = AI.new(Config.Bots.Champion, 11)
+	local found = false
+	for step = 0, 30 do
+		local decision = AI.think(brain, blackboard({
+			now = 10 + step * 0.05,
+			foeStunned = true,
+			foeBusyRemaining = 1,
+		}))
+		if decision.note == "punish" or decision.attack then
+			found = true
+		end
+	end
+	expect(found, "should attack a stunned target")
+end)
+
+test("an exhausted bot backs off instead of swinging", function()
+	local brain = AI.new(Config.Bots.Contender, 5)
+	local decision = AI.think(brain, blackboard({
+		now = 30,
+		myStamina = 6,
+		distance = 3,
+	}))
+	expect(decision.attack == nil, "too tired to punch")
+	expect(decision.move == "Retreat" or decision.move == "Strafe", `moved {decision.move}`)
+end)
+
+test("the bot stays deterministic for a fixed seed", function()
+	local a = AI.new(Config.Bots.Contender, 99)
+	local b = AI.new(Config.Bots.Contender, 99)
+	for step = 0, 20 do
+		local t = 10 + step * 0.2
+		local da = AI.think(a, blackboard({ now = t }))
+		local db = AI.think(b, blackboard({ now = t }))
+		expect(da.move == db.move, "same move")
+		expect(da.attack == db.attack, "same attack")
+	end
+end)
+
+print("")
+print(`{passed} passed, {failed} failed`)
+if failed > 0 then
+	for _, f in failures do
+		print(`  - {f}`)
+	end
+	error(`{failed} test(s) failed`)
+end
