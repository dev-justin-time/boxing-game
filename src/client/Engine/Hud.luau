diff --git a/src/client/Hud.luau b/src/client/Hud.luau
new file mode 100644
index 0000000..f8d2c67
--- /dev/null
+++ b/src/client/Hud.luau
@@ -0,0 +1,872 @@
+--!strict
+-- Match HUD, lobby and hit feedback.
+--
+-- Visual direction: a 1970s title-fight poster crossed with a broadcast
+-- lower third. Bone paper, ink black, blood red and gold; condensed display
+-- type; corner plates with score pips; segmented bars. Deliberately not a
+-- rounded card kit.
+--
+-- Structure note: every element lives on one HudState record built once in
+-- Hud.build(). That keeps element references concrete and non-optional, which
+-- is what strict mode wants, and makes the render path a straight read.
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+local RunService = game:GetService("RunService")
+local TweenService = game:GetService("TweenService")
+local UserInputService = game:GetService("UserInputService")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Types = require(Shared.Types)
+
+local Hud = {}
+
+local PLAYER = Players.LocalPlayer
+
+local PAPER = Color3.fromRGB(240, 232, 216)
+local INK = Color3.fromRGB(18, 20, 24)
+local INK_SOFT = Color3.fromRGB(34, 37, 43)
+local RED = Color3.fromRGB(198, 52, 42)
+local BLUE = Color3.fromRGB(48, 96, 172)
+local GOLD = Color3.fromRGB(234, 187, 84)
+local GREEN = Color3.fromRGB(126, 176, 94)
+local GUARD_BLUE = Color3.fromRGB(96, 152, 196)
+local MUTED = Color3.fromRGB(150, 144, 132)
+local TRACK = Color3.fromRGB(58, 54, 50)
+
+local DISPLAY = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
+local BODY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
+
+export type Handlers = {
+	queue: (mode: string, difficulty: string?) -> (),
+	cancelQueue: () -> (),
+	punch: (attack: string) -> (),
+	block: (blocking: boolean) -> (),
+	dodge: () -> (),
+	setCamera: (mode: string) -> (),
+}
+
+local function newFrame(parent: Instance, name: string, color: Color3, transparency: number?): Frame
+	local f = Instance.new("Frame")
+	f.Name = name
+	f.BackgroundColor3 = color
+	f.BackgroundTransparency = transparency or 0
+	f.BorderSizePixel = 0
+	f.Parent = parent
+	return f
+end
+
+local function newLabel(parent: Instance, name: string, text: string, size: number, color: Color3, font: Font?): TextLabel
+	local l = Instance.new("TextLabel")
+	l.Name = name
+	l.BackgroundTransparency = 1
+	l.BorderSizePixel = 0
+	l.Text = text
+	l.FontFace = font or DISPLAY
+	l.TextSize = size
+	l.TextColor3 = color
+	l.TextXAlignment = Enum.TextXAlignment.Left
+	l.TextYAlignment = Enum.TextYAlignment.Center
+	l.Parent = parent
+	return l
+end
+
+local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
+	local s = Instance.new("UIStroke")
+	s.Color = color
+	s.Thickness = thickness
+	s.Transparency = transparency or 0
+	s.Parent = parent
+	return s
+end
+
+-- A bar is a track with a fill that grows from the left. Returning both lets
+-- the render path set only the fill.
+local function newBar(parent: Instance, name: string, color: Color3): (Frame, Frame)
+	local track = newFrame(parent, name, TRACK, 0.15)
+	track.ClipsDescendants = true
+	local fill = newFrame(track, "Fill", color, 0)
+	fill.Size = UDim2.fromScale(1, 1)
+	return track, fill
+end
+
+-- Corner plate: name, health bar, stamina/guard strip and score pips.
+type CornerPlate = {
+	plate: Frame,
+	name: TextLabel,
+	health: Frame,
+	stamina: Frame,
+	guard: Frame,
+	pips: { Frame },
+	alignRight: boolean,
+}
+
+local function buildCornerPlate(
+	parent: Instance,
+	name: string,
+	color: Color3,
+	alignRight: boolean
+): CornerPlate
+	local plate = newFrame(parent, name, INK_SOFT)
+	plate.Size = UDim2.new(0.34, -12, 0, 92)
+	if alignRight then
+		plate.Position = UDim2.new(1, -18, 0, 12)
+		plate.AnchorPoint = Vector2.new(1, 0)
+	else
+		plate.Position = UDim2.fromOffset(18, 12)
+	end
+
+	local stripe = newFrame(plate, "Stripe", color)
+	stripe.Size = UDim2.new(0, 6, 1, 0)
+	if alignRight then
+		stripe.Position = UDim2.new(1, -6, 0, 0)
+	end
+
+	local title = newLabel(plate, "CornerName", "CORNER", 30, PAPER)
+	title.Size = UDim2.new(1, -28, 0, 34)
+	title.Position = UDim2.fromOffset(16, 2)
+	if alignRight then
+		title.TextXAlignment = Enum.TextXAlignment.Right
+		title.Position = UDim2.fromOffset(8, 2)
+	end
+
+	local healthTrack, healthFill = newBar(plate, "HealthTrack", color)
+	healthTrack.Size = UDim2.new(1, -34, 0, 16)
+	healthTrack.Position = UDim2.fromOffset(16, 42)
+	if alignRight then
+		healthFill.AnchorPoint = Vector2.new(1, 0)
+		healthFill.Position = UDim2.new(1, 0, 0, 0)
+	end
+
+	local staminaTrack, staminaFill = newBar(plate, "StaminaTrack", GREEN)
+	staminaTrack.Size = UDim2.new(0.6, -14, 0, 6)
+	staminaTrack.Position = UDim2.fromOffset(16, 66)
+	if alignRight then
+		staminaFill.AnchorPoint = Vector2.new(1, 0)
+		staminaFill.Position = UDim2.new(1, 0, 0, 0)
+	end
+
+	local guardTrack, guardFill = newBar(plate, "GuardTrack", GUARD_BLUE)
+	guardTrack.Size = UDim2.new(0.4, -18, 0, 6)
+	guardTrack.Position = UDim2.new(0.6, 6, 0, 66)
+	if alignRight then
+		guardFill.AnchorPoint = Vector2.new(1, 0)
+		guardFill.Position = UDim2.new(1, 0, 0, 0)
+	end
+
+	local pips: { Frame } = {}
+	for i = 1, 2 do
+		local pip = newFrame(plate, `Pip{i}`, TRACK)
+		pip.Size = UDim2.fromOffset(13, 13)
+		pip.Position = if alignRight
+			then UDim2.new(0, 16 + (i - 1) * 19, 0, 26)
+			else UDim2.new(1, -20 - (i - 1) * 19, 0, 26)
+		table.insert(pips, pip)
+	end
+
+	return {
+		plate = plate,
+		name = title,
+		health = healthFill,
+		stamina = staminaFill,
+		guard = guardFill,
+		pips = pips,
+		alignRight = alignRight,
+	}
+end
+
+type TouchButton = {
+	button: TextButton,
+	attack: string?,
+	hold: boolean,
+}
+
+export type HudState = {
+	screen: ScreenGui,
+	lobby: Frame,
+	lobbyCancel: TextButton,
+	queueStatus: TextLabel,
+	hud: Frame,
+	red: CornerPlate,
+	blue: CornerPlate,
+	roundLabel: TextLabel,
+	clockLabel: TextLabel,
+	modeTag: TextLabel,
+	localStamina: Frame,
+	localGuard: Frame,
+	comboLabel: TextLabel,
+	banner: Frame,
+	bannerText: TextLabel,
+	bannerSub: TextLabel,
+	hitFlash: Frame,
+	vignette: Frame,
+	cameraButtons: { TextButton },
+	touchButtons: { TouchButton },
+}
+
+local state: HudState? = nil
+local handlers: Handlers? = nil
+local difficulty = "Contender"
+local currentMode = "ThirdPerson"
+local lastPhase = ""
+local bannerUntil = 0
+local comboUntil = 0
+local comboBaseSize = 44
+
+-- ------------------------------------------------------------------ build
+
+local function buildMatchHud(parent: Instance): HudState
+	local hud = newFrame(parent, "MatchHud", INK, 1)
+	hud.Size = UDim2.fromScale(1, 1)
+	hud.Visible = false
+
+	local top = newFrame(hud, "TopRail", INK, 0.12)
+	top.Size = UDim2.new(1, 0, 0, 118)
+
+	local hairline = newFrame(top, "Hairline", GOLD)
+	hairline.Size = UDim2.new(1, 0, 0, 2)
+	hairline.Position = UDim2.new(0, 0, 1, -2)
+
+	local red = buildCornerPlate(top, "RedCorner", RED, false)
+	local blue = buildCornerPlate(top, "BlueCorner", BLUE, true)
+
+	local center = newFrame(top, "CenterPlate", INK)
+	center.Size = UDim2.fromOffset(196, 92)
+	center.Position = UDim2.new(0.5, 0, 0, 12)
+	center.AnchorPoint = Vector2.new(0.5, 0)
+	stroke(center, GOLD, 2)
+
+	local roundLabel = newLabel(center, "Round", "ROUND 1", 15, GOLD)
+	roundLabel.Size = UDim2.new(1, 0, 0, 20)
+	roundLabel.Position = UDim2.fromOffset(0, 8)
+	roundLabel.TextXAlignment = Enum.TextXAlignment.Center
+
+	local clockLabel = newLabel(center, "Clock", "1:00", 46, PAPER)
+	clockLabel.Size = UDim2.new(1, 0, 0, 52)
+	clockLabel.Position = UDim2.fromOffset(0, 26)
+	clockLabel.TextXAlignment = Enum.TextXAlignment.Center
+
+	local modeTag = newLabel(center, "ModeTag", "P V P", 13, MUTED)
+	modeTag.Size = UDim2.new(1, 0, 0, 16)
+	modeTag.Position = UDim2.fromOffset(0, 74)
+	modeTag.TextXAlignment = Enum.TextXAlignment.Center
+
+	-- Local fighter readouts, bottom left.
+	local readouts = newFrame(hud, "Readouts", INK, 1)
+	readouts.Size = UDim2.fromOffset(320, 76)
+	readouts.Position = UDim2.new(0, 22, 1, -110)
+
+	local staminaCaption = newLabel(readouts, "StaminaCaption", "STAMINA", 12, GREEN)
+	staminaCaption.Size = UDim2.fromOffset(150, 14)
+	local guardCaption = newLabel(readouts, "GuardCaption", "GUARD", 12, GUARD_BLUE)
+	guardCaption.Position = UDim2.fromOffset(166, 0)
+	guardCaption.Size = UDim2.fromOffset(140, 14)
+
+	local localStaminaTrack, localStamina = newBar(readouts, "LocalStamina", GREEN)
+	localStaminaTrack.Size = UDim2.fromOffset(150, 12)
+	localStaminaTrack.Position = UDim2.fromOffset(0, 18)
+	local localGuardTrack, localGuard = newBar(readouts, "LocalGuard", GUARD_BLUE)
+	localGuardTrack.Size = UDim2.fromOffset(140, 12)
+	localGuardTrack.Position = UDim2.fromOffset(166, 18)
+
+	local legend = newLabel(
+		readouts,
+		"Legend",
+		"J  JAB    K  CROSS    L  HOOK    U  UPPER    F  GUARD    SPACE  SLIP",
+		11,
+		MUTED,
+		BODY
+	)
+	legend.Size = UDim2.fromOffset(320, 14)
+	legend.Position = UDim2.fromOffset(0, 44)
+
+	local comboLabel = newLabel(hud, "Combo", "", 44, GOLD)
+	comboLabel.Size = UDim2.fromOffset(340, 60)
+	comboLabel.Position = UDim2.new(1, -26, 1, -132)
+	comboLabel.TextXAlignment = Enum.TextXAlignment.Right
+
+	local banner = newFrame(hud, "Banner", INK, 0.1)
+	banner.Size = UDim2.fromOffset(640, 136)
+	banner.Position = UDim2.new(0.5, 0, 0.32, 0)
+	banner.AnchorPoint = Vector2.new(0.5, 0.5)
+	banner.Visible = false
+	stroke(banner, GOLD, 2)
+
+	local bannerText = newLabel(banner, "BannerText", "FIGHT", 64, PAPER)
+	bannerText.Size = UDim2.new(1, -24, 0, 76)
+	bannerText.Position = UDim2.fromOffset(12, 6)
+	bannerText.TextXAlignment = Enum.TextXAlignment.Center
+
+	local bannerSub = newLabel(banner, "BannerSub", "", 15, GOLD)
+	bannerSub.Size = UDim2.new(1, -24, 0, 24)
+	bannerSub.Position = UDim2.fromOffset(12, 86)
+	bannerSub.TextXAlignment = Enum.TextXAlignment.Center
+
+	local vignette = newFrame(hud, "Vignette", RED, 1)
+	vignette.Size = UDim2.fromScale(1, 1)
+	vignette.ZIndex = 2
+
+	local hitFlash = newFrame(hud, "HitFlash", Color3.fromRGB(255, 240, 220), 1)
+	hitFlash.Size = UDim2.fromScale(1, 1)
+	hitFlash.ZIndex = 3
+
+	-- Camera switcher, small and out of the way.
+	local camRow = newFrame(hud, "CameraRow", INK, 1)
+	camRow.Size = UDim2.fromOffset(372, 26)
+	camRow.Position = UDim2.new(0.5, 0, 1, -36)
+	camRow.AnchorPoint = Vector2.new(0.5, 0)
+
+	local camModes = { "ThirdPerson", "FirstPerson", "Isometric", "Cinematic" }
+	local camNames = { "SHOULDER", "FIRST PERSON", "TOP DOWN", "BROADCAST" }
+	local cameraButtons: { TextButton } = {}
+	for i, mode in camModes do
+		local btn = Instance.new("TextButton")
+		btn.Name = mode
+		btn.Size = UDim2.fromOffset(90, 24)
+		btn.Position = UDim2.fromOffset((i - 1) * 94, 0)
+		btn.BackgroundColor3 = INK
+		btn.BackgroundTransparency = 0.2
+		btn.Text = camNames[i]
+		btn.TextColor3 = if mode == currentMode then GOLD else MUTED
+		btn.FontFace = DISPLAY
+		btn.TextSize = 12
+		btn.BorderSizePixel = 0
+		btn.Parent = camRow
+		table.insert(cameraButtons, btn)
+
+		local captured = mode
+		btn.Activated:Connect(function()
+			currentMode = captured
+			if handlers then
+				handlers.setCamera(captured)
+			end
+			for j, other in cameraButtons do
+				other.TextColor3 = if camModes[j] == currentMode then GOLD else MUTED
+			end
+		end)
+	end
+
+	local touchButtons: { TouchButton } = {}
+	if UserInputService.TouchEnabled then
+		local pad = newFrame(hud, "TouchPad", INK, 1)
+		pad.Size = UDim2.fromOffset(272, 220)
+		pad.Position = UDim2.new(1, -288, 1, -288)
+
+		local punchButtons = {
+			{ text = "JAB", attack = "Jab", x = 0, y = 132 },
+			{ text = "CROSS", attack = "Cross", x = 92, y = 132 },
+			{ text = "HOOK", attack = "Hook", x = 184, y = 132 },
+			{ text = "UPPER", attack = "Uppercut", x = 92, y = 44 },
+		}
+		for _, def in punchButtons do
+			local btn = Instance.new("TextButton")
+			btn.Size = UDim2.fromOffset(80, 80)
+			btn.Position = UDim2.fromOffset(def.x, def.y)
+			btn.BackgroundColor3 = INK_SOFT
+			btn.BackgroundTransparency = 0.15
+			btn.Text = def.text
+			btn.TextColor3 = PAPER
+			btn.FontFace = DISPLAY
+			btn.TextSize = 16
+			btn.BorderSizePixel = 0
+			btn.Parent = pad
+			stroke(btn, GOLD, 1.5, 0.4)
+			local attack = def.attack
+			btn.Activated:Connect(function()
+				if handlers then
+					handlers.punch(attack)
+				end
+			end)
+			table.insert(touchButtons, { button = btn, attack = attack, hold = false })
+		end
+
+		local guardBtn = Instance.new("TextButton")
+		guardBtn.Size = UDim2.fromOffset(80, 80)
+		guardBtn.Position = UDim2.fromOffset(0, 44)
+		guardBtn.BackgroundColor3 = Color3.fromRGB(30, 54, 76)
+		guardBtn.Text = "GUARD"
+		guardBtn.TextColor3 = PAPER
+		guardBtn.FontFace = DISPLAY
+		guardBtn.TextSize = 15
+		guardBtn.BorderSizePixel = 0
+		guardBtn.Parent = pad
+		guardBtn.MouseButton1Down:Connect(function()
+			if handlers then
+				handlers.block(true)
+			end
+		end)
+		guardBtn.MouseButton1Up:Connect(function()
+			if handlers then
+				handlers.block(false)
+			end
+		end)
+
+		local slipBtn = Instance.new("TextButton")
+		slipBtn.Size = UDim2.fromOffset(80, 80)
+		slipBtn.Position = UDim2.fromOffset(184, 44)
+		slipBtn.BackgroundColor3 = Color3.fromRGB(74, 40, 40)
+		slipBtn.Text = "SLIP"
+		slipBtn.TextColor3 = PAPER
+		slipBtn.FontFace = DISPLAY
+		slipBtn.TextSize = 15
+		slipBtn.BorderSizePixel = 0
+		slipBtn.Parent = pad
+		slipBtn.Activated:Connect(function()
+			if handlers then
+				handlers.dodge()
+			end
+		end)
+	end
+
+	return {
+		screen = parent :: ScreenGui,
+		lobby = newFrame(parent, "placeholder", INK, 1),
+		lobbyCancel = Instance.new("TextButton"),
+		queueStatus = newLabel(parent, "placeholder", "", 12, GOLD),
+		hud = hud,
+		red = red,
+		blue = blue,
+		roundLabel = roundLabel,
+		clockLabel = clockLabel,
+		modeTag = modeTag,
+		localStamina = localStamina,
+		localGuard = localGuard,
+		comboLabel = comboLabel,
+		banner = banner,
+		bannerText = bannerText,
+		bannerSub = bannerSub,
+		hitFlash = hitFlash,
+		vignette = vignette,
+		cameraButtons = cameraButtons,
+		touchButtons = touchButtons,
+	}
+end
+
+type LobbyParts = {
+	root: Frame,
+	cancel: TextButton,
+	status: TextLabel,
+}
+
+local function buildLobby(parent: Instance): LobbyParts
+	local root = newFrame(parent, "Lobby", INK, 0.04)
+	root.Size = UDim2.fromScale(1, 1)
+
+	-- Slanted poster band behind the wordmark.
+	local band = newFrame(root, "Band", RED, 0.08)
+	band.Size = UDim2.new(1, 0, 0, 176)
+	band.Position = UDim2.new(0, 0, 0, 108)
+	band.Rotation = -1.6
+
+	local eyebrow = newLabel(root, "Eyebrow", "ROUND ONE  ·  THREE ROUNDS  ·  ONE WINNER", 13, GOLD)
+	eyebrow.Size = UDim2.fromOffset(620, 18)
+	eyebrow.Position = UDim2.new(0.5, 0, 0, 60)
+	eyebrow.AnchorPoint = Vector2.new(0.5, 0)
+	eyebrow.TextXAlignment = Enum.TextXAlignment.Center
+
+	local title = newLabel(root, "Title", "KNOCKOUT", 112, PAPER)
+	title.Size = UDim2.new(1, 0, 0, 124)
+	title.Position = UDim2.new(0, 0, 0, 104)
+	title.TextXAlignment = Enum.TextXAlignment.Center
+
+	local subtitle = newLabel(root, "Subtitle", "R  I  N  G", 24, INK)
+	subtitle.Size = UDim2.new(1, 0, 0, 28)
+	subtitle.Position = UDim2.new(0, 0, 0, 222)
+	subtitle.TextXAlignment = Enum.TextXAlignment.Center
+
+	local row = newFrame(root, "Modes", INK, 1)
+	row.Size = UDim2.fromOffset(700, 252)
+	row.Position = UDim2.new(0.5, 0, 0, 292)
+	row.AnchorPoint = Vector2.new(0.5, 0)
+
+	local function modePlate(name: string, x: number, stripeColor: Color3, heading: string, copy: string): Frame
+		local plate = newFrame(row, name, INK_SOFT)
+		plate.Size = UDim2.fromOffset(330, 252)
+		plate.Position = UDim2.fromOffset(x, 0)
+
+		local stripe = newFrame(plate, "Stripe", stripeColor)
+		stripe.Size = UDim2.new(1, 0, 0, 5)
+
+		local head = newLabel(plate, "Heading", heading, 38, PAPER)
+		head.Size = UDim2.new(1, -40, 0, 44)
+		head.Position = UDim2.fromOffset(20, 18)
+
+		local body = newLabel(plate, "Copy", copy, 14, Color3.fromRGB(196, 190, 178), BODY)
+		body.Size = UDim2.new(1, -40, 0, 62)
+		body.Position = UDim2.fromOffset(20, 66)
+		body.TextWrapped = true
+		body.TextYAlignment = Enum.TextYAlignment.Top
+
+		return plate
+	end
+
+	local pvp = modePlate(
+		"PvP",
+		0,
+		RED,
+		"FACE OFF",
+		"Queue against another player. Best of three, real guard breaks, real slips."
+	)
+	local pvpButton = Instance.new("TextButton")
+	pvpButton.Size = UDim2.new(1, -40, 0, 54)
+	pvpButton.Position = UDim2.fromOffset(20, 168)
+	pvpButton.BackgroundColor3 = RED
+	pvpButton.Text = "ENTER THE QUEUE"
+	pvpButton.TextColor3 = PAPER
+	pvpButton.FontFace = DISPLAY
+	pvpButton.TextSize = 20
+	pvpButton.BorderSizePixel = 0
+	pvpButton.Parent = pvp
+	pvpButton.Activated:Connect(function()
+		if handlers then
+			handlers.queue("PvP", nil)
+		end
+	end)
+
+	local ai = modePlate(
+		"AI",
+		370,
+		BLUE,
+		"RING BOT",
+		"The house bot reads your wind-up, blocks, slips and punishes whiffs."
+	)
+
+	local diffs = { "Rookie", "Contender", "Champion" }
+	local diffButtons: { TextButton } = {}
+	for i, name in diffs do
+		local btn = Instance.new("TextButton")
+		btn.Name = name
+		btn.Size = UDim2.fromOffset(92, 32)
+		btn.Position = UDim2.fromOffset(20 + (i - 1) * 100, 128)
+		btn.BackgroundColor3 = INK
+		btn.Text = string.upper(name)
+		btn.TextColor3 = if name == difficulty then GOLD else MUTED
+		btn.FontFace = DISPLAY
+		btn.TextSize = 13
+		btn.BorderSizePixel = 0
+		btn.Parent = ai
+		stroke(btn, if name == difficulty then GOLD else TRACK, 1)
+		table.insert(diffButtons, btn)
+		local chosen = name
+		btn.Activated:Connect(function()
+			difficulty = chosen
+			for j, other in diffButtons do
+				local selected = diffs[j] == chosen
+				other.TextColor3 = if selected then GOLD else MUTED
+				local outline = other:FindFirstChildOfClass("UIStroke")
+				if outline then
+					outline.Color = if selected then GOLD else TRACK
+				end
+			end
+		end)
+	end
+
+	local aiButton = Instance.new("TextButton")
+	aiButton.Size = UDim2.new(1, -40, 0, 54)
+	aiButton.Position = UDim2.fromOffset(20, 168)
+	aiButton.BackgroundColor3 = BLUE
+	aiButton.Text = "FIGHT THE BOT"
+	aiButton.TextColor3 = PAPER
+	aiButton.FontFace = DISPLAY
+	aiButton.TextSize = 20
+	aiButton.BorderSizePixel = 0
+	aiButton.Parent = ai
+	aiButton.Activated:Connect(function()
+		if handlers then
+			handlers.queue("AI", difficulty)
+		end
+	end)
+
+	local status = newLabel(root, "QueueStatus", "", 15, GOLD)
+	status.Size = UDim2.fromOffset(620, 22)
+	status.Position = UDim2.new(0.5, 0, 0, 560)
+	status.AnchorPoint = Vector2.new(0.5, 0)
+	status.TextXAlignment = Enum.TextXAlignment.Center
+
+	local cancel = Instance.new("TextButton")
+	cancel.Name = "CancelQueue"
+	cancel.Size = UDim2.fromOffset(190, 34)
+	cancel.Position = UDim2.new(0.5, 0, 0, 590)
+	cancel.AnchorPoint = Vector2.new(0.5, 0)
+	cancel.BackgroundColor3 = INK_SOFT
+	cancel.Text = "LEAVE QUEUE"
+	cancel.TextColor3 = PAPER
+	cancel.FontFace = DISPLAY
+	cancel.TextSize = 14
+	cancel.BorderSizePixel = 0
+	cancel.Visible = false
+	cancel.Parent = root
+	stroke(cancel, GOLD, 1, 0.5)
+	cancel.Activated:Connect(function()
+		if handlers then
+			handlers.cancelQueue()
+		end
+	end)
+
+	local footer = newLabel(
+		root,
+		"Footer",
+		"J  JAB      K  CROSS      L  HOOK      U  UPPERCUT      F  GUARD      SPACE  SLIP      SHIFT  SPRINT",
+		13,
+		MUTED
+	)
+	footer.Size = UDim2.fromOffset(940, 18)
+	footer.Position = UDim2.new(0.5, 0, 1, -46)
+	footer.AnchorPoint = Vector2.new(0.5, 0)
+	footer.TextXAlignment = Enum.TextXAlignment.Center
+
+	return { root = root, cancel = cancel, status = status }
+end
+
+-- ------------------------------------------------------------------ effects
+
+local function flash(color: Color3, peak: number, fade: number)
+	local s = state
+	if not s then
+		return
+	end
+	local overlay = s.hitFlash
+	overlay.BackgroundColor3 = color
+	overlay.BackgroundTransparency = 1 - peak
+	TweenService:Create(overlay, TweenInfo.new(fade, Enum.EasingStyle.Quad), {
+		BackgroundTransparency = 1,
+	}):Play()
+end
+
+local function popText(text: string, color: Color3, size: number)
+	local s = state
+	if not s then
+		return
+	end
+	local pop = newLabel(s.screen, "Pop", text, size, color)
+	pop.AnchorPoint = Vector2.new(0.5, 0.5)
+	pop.Position = UDim2.new(0.5, math.random(-90, 90), 0.44, math.random(-24, 24))
+	pop.Size = UDim2.fromOffset(320, 56)
+	pop.TextXAlignment = Enum.TextXAlignment.Center
+	pop.Rotation = math.random(-5, 5)
+	pop.ZIndex = 4
+
+	TweenService:Create(pop, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
+		Position = pop.Position - UDim2.fromOffset(0, 44),
+		TextTransparency = 1,
+	}):Play()
+	task.delay(0.62, function()
+		if pop.Parent then
+			pop:Destroy()
+		end
+	end)
+end
+
+local function showBanner(text: string, detail: string?, duration: number)
+	local s = state
+	if not s then
+		return
+	end
+	s.bannerText.Text = text
+	s.bannerSub.Text = detail or ""
+	s.banner.Visible = true
+	s.banner.BackgroundTransparency = 0.12
+	s.bannerText.TextTransparency = 0
+	s.bannerSub.TextTransparency = 0
+	bannerUntil = os.clock() + duration
+	s.banner.Size = UDim2.fromOffset(560, 120)
+	TweenService:Create(s.banner, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
+		Size = UDim2.fromOffset(640, 136),
+	}):Play()
+end
+
+local function hideBanner()
+	local s = state
+	if s then
+		s.banner.Visible = false
+	end
+end
+
+local function setBar(fill: Frame, value: number, max: number)
+	local ratio = if max > 0 then math.clamp(value / max, 0, 1) else 0
+	fill.Size = UDim2.fromScale(ratio, 1)
+end
+
+local function setPips(pips: { Frame }, score: number)
+	for i, pip in pips do
+		pip.BackgroundColor3 = if i <= score then GOLD else TRACK
+	end
+end
+
+local function findFighter(snapshot: Types.Snapshot, id: string?): Types.FighterInfo?
+	if not id then
+		return nil
+	end
+	for _, info in snapshot.fighters do
+		if info.id == id then
+			return info
+		end
+	end
+	return nil
+end
+
+-- ------------------------------------------------------------------ public
+
+function Hud.bind(callbacks: Handlers)
+	handlers = callbacks
+end
+
+function Hud.build()
+	if state then
+		return
+	end
+	local screen = Instance.new("ScreenGui")
+	screen.Name = "KnockoutHud"
+	screen.ResetOnSpawn = false
+	screen.IgnoreGuiInset = true
+	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
+	screen.DisplayOrder = 10
+	screen.Parent = PLAYER:WaitForChild("PlayerGui")
+
+	local built = buildMatchHud(screen)
+	local lobby = buildLobby(screen)
+	built.lobby = lobby.root
+	built.lobbyCancel = lobby.cancel
+	built.queueStatus = lobby.status
+	state = built
+
+	RunService.RenderStepped:Connect(function()
+		if bannerUntil > 0 and os.clock() > bannerUntil then
+			bannerUntil = 0
+			hideBanner()
+		end
+		if comboUntil > 0 and os.clock() > comboUntil then
+			comboUntil = 0
+			built.comboLabel.Text = ""
+		end
+	end)
+end
+
+function Hud.applySnapshot(snapshot: Types.Snapshot)
+	local s = state
+	if not s then
+		return
+	end
+	local inMatch = snapshot.phase ~= "Lobby" and snapshot.phase ~= "Queued"
+	s.lobby.Visible = not inMatch
+	s.hud.Visible = inMatch
+	s.lobbyCancel.Visible = snapshot.phase == "Queued"
+
+	if not inMatch then
+		s.queueStatus.Text = if snapshot.phase == "Queued"
+			then `IN THE QUEUE  ·  {snapshot.queueSize} WAITING`
+			else ""
+		return
+	end
+
+	local red = findFighter(snapshot, snapshot.redId)
+	local blue = findFighter(snapshot, snapshot.blueId)
+
+	if red then
+		s.red.name.Text = string.upper(red.name)
+		setBar(s.red.health, red.health, red.maxHealth)
+		setBar(s.red.stamina, red.stamina, red.maxStamina)
+		setBar(s.red.guard, red.guard, red.maxGuard)
+	end
+	if blue then
+		s.blue.name.Text = string.upper(blue.name)
+		setBar(s.blue.health, blue.health, blue.maxHealth)
+		setBar(s.blue.stamina, blue.stamina, blue.maxStamina)
+		setBar(s.blue.guard, blue.guard, blue.maxGuard)
+	end
+	setPips(s.red.pips, snapshot.redScore)
+	setPips(s.blue.pips, snapshot.blueScore)
+
+	s.roundLabel.Text = `ROUND {snapshot.round} OF {snapshot.maxRounds}`
+	local seconds = math.max(0, math.floor(snapshot.clock))
+	s.clockLabel.Text = string.format("%d:%02d", seconds // 60, seconds % 60)
+	s.modeTag.Text = if red and red.isBot and blue and blue.isBot then "BOT BOUT" else "P V P"
+
+	local mine = if snapshot.corner == "Red" then red else blue
+	if mine then
+		setBar(s.localStamina, mine.stamina, mine.maxStamina)
+		setBar(s.localGuard, mine.guard, mine.maxGuard)
+	end
+
+	local phaseKey = `{snapshot.phase}:{snapshot.round}`
+	if phaseKey ~= lastPhase then
+		lastPhase = phaseKey
+		if snapshot.phase == "Intro" then
+			local title = snapshot.banner or `ROUND {snapshot.round}`
+			showBanner(string.upper(title), snapshot.bannerDetail, 2.6)
+		elseif snapshot.phase == "Round" then
+			showBanner("FIGHT", nil, 1.1)
+		elseif snapshot.phase == "RoundEnd" or snapshot.phase == "MatchEnd" then
+			showBanner(string.upper(snapshot.banner or "ROUND OVER"), snapshot.bannerDetail, 4)
+		end
+	end
+end
+
+function Hud.onHitYou(damage: number)
+	flash(RED, math.min(0.4, 0.12 + damage / 60), 0.36)
+	popText(`-{math.floor(damage)}`, GOLD, 40)
+end
+
+function Hud.onHitThem(_damage: number, combo: number)
+	flash(PAPER, 0.1, 0.2)
+	local s = state
+	if combo > 1 and s then
+		s.comboLabel.Text = `{combo} HIT COMBO`
+		comboUntil = os.clock() + 1.8
+		TweenService:Create(s.comboLabel, TweenInfo.new(0.14, Enum.EasingStyle.Back), {
+			TextSize = comboBaseSize + 8,
+		}):Play()
+		task.delay(0.16, function()
+			if state then
+				TweenService:Create(state.comboLabel, TweenInfo.new(0.2), {
+					TextSize = comboBaseSize,
+				}):Play()
+			end
+		end)
+	end
+end
+
+function Hud.onBlocked()
+	popText("BLOCKED", GUARD_BLUE, 26)
+	flash(GUARD_BLUE, 0.08, 0.2)
+end
+
+function Hud.onGuardBreak()
+	flash(GOLD, 0.3, 0.5)
+	showBanner("GUARD BREAK", "HE IS OPEN", 1.4)
+end
+
+function Hud.onDodge()
+	local s = state
+	if not s then
+		return
+	end
+	local slip = newLabel(s.screen, "Slip", "SLIP", 20, GUARD_BLUE)
+	slip.AnchorPoint = Vector2.new(0.5, 0.5)
+	slip.Position = UDim2.new(0.5, 0, 0.62, 0)
+	slip.Size = UDim2.fromOffset(180, 24)
+	slip.TextXAlignment = Enum.TextXAlignment.Center
+	TweenService:Create(slip, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
+	task.delay(0.55, function()
+		if slip.Parent then
+			slip:Destroy()
+		end
+	end)
+end
+
+function Hud.setCameraMode(mode: string)
+	currentMode = mode
+	local s = state
+	if not s then
+		return
+	end
+	for _, btn in s.cameraButtons do
+		btn.TextColor3 = if btn.Name == mode then GOLD else MUTED
+	end
+end
+
+function Hud.getCameraMode(): string
+	return currentMode
+end
+
+return Hud
