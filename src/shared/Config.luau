diff --git a/src/shared/Config.luau b/src/shared/Config.luau
new file mode 100644
index 0000000..3281f12
--- /dev/null
+++ b/src/shared/Config.luau
@@ -0,0 +1,179 @@
+--!strict
+-- Knckout Ring tuning. Everything the game balances around lives here.
+
+export type AttackId = "Jab" | "Cross" | "Hook" | "Uppercut"
+
+export type AttackDef = {
+	damage: number,
+	stamina: number,
+	windup: number,
+	active: number,
+	recovery: number,
+	range: number,
+	arcDegrees: number,
+	knockback: number,
+	lift: number,
+	stun: number,
+	guardDamage: number,
+	shake: number,
+	lunge: number,
+}
+
+export type AnimSlot =
+	"Idle"
+	| "Guard"
+	| "Jab"
+	| "Cross"
+	| "Hook"
+	| "Uppercut"
+	| "Block"
+	| "Dodge"
+	| "Hit"
+	| "KO"
+	| "Victory"
+	| "Intro"
+	| "Stun"
+
+local Attacks: { [AttackId]: AttackDef } = {
+	Jab = {
+		damage = 5,
+		stamina = 7,
+		windup = 0.10,
+		active = 0.08,
+		recovery = 0.16,
+		range = 3.8,
+		arcDegrees = 60,
+		knockback = 4,
+		lift = 0,
+		stun = 0.16,
+		guardDamage = 8,
+		shake = 0.22,
+		lunge = 0.6,
+	},
+	Cross = {
+		damage = 9,
+		stamina = 11,
+		windup = 0.16,
+		active = 0.09,
+		recovery = 0.24,
+		range = 4.1,
+		arcDegrees = 50,
+		knockback = 7,
+		lift = 0,
+		stun = 0.26,
+		guardDamage = 14,
+		shake = 0.4,
+		lunge = 1.0,
+	},
+	Hook = {
+		damage = 12,
+		stamina = 15,
+		windup = 0.22,
+		active = 0.10,
+		recovery = 0.30,
+		range = 3.8,
+		arcDegrees = 95,
+		knockback = 9,
+		lift = 0.5,
+		stun = 0.32,
+		guardDamage = 20,
+		shake = 0.6,
+		lunge = 1.2,
+	},
+	Uppercut = {
+		damage = 16,
+		stamina = 22,
+		windup = 0.28,
+		active = 0.10,
+		recovery = 0.40,
+		range = 3.4,
+		arcDegrees = 45,
+		knockback = 13,
+		lift = 7,
+		stun = 0.45,
+		guardDamage = 30,
+		shake = 0.9,
+		lunge = 1.4,
+	},
+}
+
+local Match = {
+	roundsToWin = 2,
+	maxRounds = 3,
+	roundTime = 60,
+	introTime = 3,
+	betweenRounds = 5,
+	maxHealth = 100,
+	maxStamina = 100,
+	maxGuard = 100,
+	staminaRegen = 15,
+	staminaRegenDelay = 0.75,
+	guardRegen = 9,
+	guardRegenDelay = 1.1,
+	walkSpeed = 15,
+	sprintSpeed = 21,
+	blockWalkSpeed = 6,
+	dodgeStamina = 18,
+	dodgeDuration = 0.32,
+	dodgeInvulnerable = 0.24,
+	dodgeCooldown = 0.35,
+	dodgeSpeed = 34,
+	guardBreakStun = 1.15,
+	comboWindow = 1.6,
+	comboStep = 0.05,
+	comboCap = 1.3,
+	ringSize = 36,
+	ringRopeHeight = 3.4,
+	spawnGap = 9,
+}
+
+-- Fill these with Animation asset ids after importing your Mixamo FBX files.
+-- See README.md ("Mixamo pipeline"). Empty ids use the built-in procedural
+-- fallback, so the game is playable before you import anything.
+local Animations: { [AnimSlot]: string } = {
+	Idle = "",
+	Guard = "",
+	Jab = "",
+	Cross = "",
+	Hook = "",
+	Uppercut = "",
+	Block = "",
+	Dodge = "",
+	Hit = "",
+	KO = "",
+	Victory = "",
+	Intro = "",
+	Stun = "",
+}
+
+local Palette = {
+	canvas = Color3.fromRGB(236, 226, 206),
+	ink = Color3.fromRGB(20, 24, 29),
+	paper = Color3.fromRGB(246, 240, 229),
+	redCorner = Color3.fromRGB(200, 54, 44),
+	blueCorner = Color3.fromRGB(42, 92, 168),
+	gold = Color3.fromRGB(232, 185, 76),
+	staminaGreen = Color3.fromRGB(126, 176, 94),
+	guardBlue = Color3.fromRGB(96, 152, 196),
+	ringFloor = Color3.fromRGB(36, 52, 54),
+	ropes = Color3.fromRGB(226, 214, 190),
+}
+
+local Config = {
+	Attacks = Attacks,
+	AttackOrder = { "Jab", "Cross", "Hook", "Uppercut" } :: { AttackId },
+	Match = Match,
+	Animations = Animations,
+	Palette = Palette,
+
+	-- Bot profiles. reaction = seconds between decisions, blockChance and
+	-- dodgeChance are responses to an incoming punch, aggression scales
+	-- how often it throws instead of resetting to range.
+	Bots = {
+		Rookie = { reaction = 0.42, blockChance = 0.35, dodgeChance = 0.10, aggression = 0.35, comboLove = 0.25, punish = 0.2, speed = 11 },
+		Contender = { reaction = 0.28, blockChance = 0.55, dodgeChance = 0.22, aggression = 0.55, comboLove = 0.5, punish = 0.5, speed = 13 },
+		Champion = { reaction = 0.17, blockChance = 0.7, dodgeChance = 0.38, aggression = 0.72, comboLove = 0.8, punish = 0.85, speed = 15 },
+	},
+}
+
+return Config
