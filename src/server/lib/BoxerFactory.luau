diff --git a/src/server/lib/BoxerFactory.luau b/src/server/lib/BoxerFactory.luau
new file mode 100644
index 0000000..532dc72
--- /dev/null
+++ b/src/server/lib/BoxerFactory.luau
@@ -0,0 +1,318 @@
+--!strict
+-- Builds the boxing rigs used in the ring.
+--
+-- Why a custom rig instead of player avatars: boxers need real elbows, knees,
+-- ankles and wrist joints for the pose layer, plus consistent proportions for
+-- Mixamo retargeting. A custom rig also means no accessory or package geometry
+-- clipping through gloves, and fights look identical for every player.
+--
+-- Joint names match R15's Motor6D names (LeftShoulder, LeftElbow, LeftWrist,
+-- LeftHip, LeftKnee, LeftAnkle, Waist, Neck) so a rigged Mixamo FBX can retarget
+-- onto it directly. The root motor is named RootJoint to match the pose keys.
+
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Config = require(ReplicatedStorage.Shared.Config)
+
+local BoxerFactory = {}
+
+export type Rig = {
+	model: Model,
+	humanoid: Humanoid,
+	root: BasePart,
+	joints: { [string]: Motor6D },
+	c0: { [string]: CFrame },
+	rigType: "R6" | "R15" | "Boxer",
+}
+
+local SKINS = {
+	Color3.fromRGB(226, 178, 140),
+	Color3.fromRGB(198, 145, 106),
+	Color3.fromRGB(158, 106, 72),
+	Color3.fromRGB(112, 74, 50),
+	Color3.fromRGB(232, 196, 162),
+}
+
+local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
+	local p = Instance.new("Part")
+	p.Name = name
+	p.Size = size
+	p.Color = color
+	p.Material = material
+	p.TopSurface = Enum.SurfaceType.Smooth
+	p.BottomSurface = Enum.SurfaceType.Smooth
+	p.CanCollide = false
+	p.CanQuery = false
+	p.CanTouch = false
+	p.Massless = true
+	p.Parent = parent
+	return p
+end
+
+local function weldJoint(
+	name: string,
+	part0: BasePart,
+	part1: BasePart,
+	jointWorld: CFrame,
+	parent: Instance
+): (Motor6D, CFrame)
+	local motor = Instance.new("Motor6D")
+	motor.Name = name
+	motor.Part0 = part0
+	motor.Part1 = part1
+	local c0 = part0.CFrame:Inverse() * jointWorld
+	local c1 = part1.CFrame:Inverse() * jointWorld
+	motor.C0 = c0
+	motor.C1 = c1
+	motor.Parent = parent
+	return motor, c0
+end
+
+-- One arm chain: shoulder -> elbow -> wrist, all authored at rest with the arm
+-- hanging at the fighter's side so the pose layer can swing it up.
+local function buildArm(
+	parent: Instance,
+	side: "Left" | "Right",
+	sign: number,
+	torso: BasePart,
+	skin: Color3,
+	glove: Color3
+): ({ [string]: Motor6D }, { [string]: CFrame })
+	local shoulderX = sign * 1.42
+	local shoulderY = 4.62
+	local upper = makePart(`{side}UpperArm`, Vector3.new(0.78, 1.28, 0.78), skin, Enum.Material.SmoothPlastic, parent)
+	upper.CFrame = CFrame.new(shoulderX, 3.94, 0)
+	local lower = makePart(`{side}LowerArm`, Vector3.new(0.7, 1.12, 0.7), skin, Enum.Material.SmoothPlastic, parent)
+	lower.CFrame = CFrame.new(shoulderX, 2.86, 0)
+	local hand = makePart(`{side}Hand`, Vector3.new(0.98, 0.98, 0.98), glove, Enum.Material.Leather, parent)
+	hand.Shape = Enum.PartType.Ball
+	hand.CFrame = CFrame.new(shoulderX, 2.06, 0)
+
+	local joints: { [string]: Motor6D } = {}
+	local c0s: { [string]: CFrame } = {}
+
+	local shoulder, shoulderC0 = weldJoint(
+		`{side}Shoulder`,
+		torso,
+		upper,
+		CFrame.new(shoulderX, shoulderY, 0),
+		parent
+	)
+	joints[`{side}Shoulder`] = shoulder
+	c0s[`{side}Shoulder`] = shoulderC0
+
+	local elbow, elbowC0 = weldJoint(`{side}Elbow`, upper, lower, CFrame.new(shoulderX, 3.3, 0), parent)
+	joints[`{side}Elbow`] = elbow
+	c0s[`{side}Elbow`] = elbowC0
+
+	local wrist, wristC0 = weldJoint(`{side}Wrist`, lower, hand, CFrame.new(shoulderX, 2.42, 0), parent)
+	joints[`{side}Wrist`] = wrist
+	c0s[`{side}Wrist`] = wristC0
+
+	-- Wrist strap so the glove reads as a glove, not a floating ball.
+	local cuff = makePart(`{side}Cuff`, Vector3.new(0.84, 0.26, 0.84), glove, Enum.Material.Leather, parent)
+	cuff.CFrame = CFrame.new(shoulderX, 2.56, 0)
+	cuff.Massless = true
+	local cuffWeld = Instance.new("WeldConstraint")
+	cuffWeld.Part0 = cuff
+	cuffWeld.Part1 = lower
+	cuffWeld.Parent = cuff
+
+	return joints, c0s
+end
+
+local function buildLeg(
+	parent: Instance,
+	side: "Left" | "Right",
+	sign: number,
+	torso: BasePart,
+	skin: Color3,
+	boot: Color3
+): ({ [string]: Motor6D }, { [string]: CFrame })
+	local hipX = sign * 0.56
+	local upper = makePart(`{side}UpperLeg`, Vector3.new(0.86, 1.55, 0.86), skin, Enum.Material.SmoothPlastic, parent)
+	upper.CFrame = CFrame.new(hipX, 2.1, 0)
+	local lower = makePart(`{side}LowerLeg`, Vector3.new(0.76, 1.42, 0.76), skin, Enum.Material.SmoothPlastic, parent)
+	lower.CFrame = CFrame.new(hipX, 0.66, 0)
+	local foot = makePart(`{side}Foot`, Vector3.new(0.82, 0.44, 1.3), boot, Enum.Material.Leather, parent)
+	foot.CFrame = CFrame.new(hipX, -0.28, -0.22)
+
+	local joints: { [string]: Motor6D } = {}
+	local c0s: { [string]: CFrame } = {}
+
+	local hip, hipC0 = weldJoint(`{side}Hip`, torso, upper, CFrame.new(hipX, 2.86, 0), parent)
+	joints[`{side}Hip`] = hip
+	c0s[`{side}Hip`] = hipC0
+
+	local knee, kneeC0 = weldJoint(`{side}Knee`, upper, lower, CFrame.new(hipX, 1.36, 0), parent)
+	joints[`{side}Knee`] = knee
+	c0s[`{side}Knee`] = kneeC0
+
+	local ankle, ankleC0 = weldJoint(`{side}Ankle`, lower, foot, CFrame.new(hipX, -0.02, 0), parent)
+	joints[`{side}Ankle`] = ankle
+	c0s[`{side}Ankle`] = ankleC0
+
+	return joints, c0s
+end
+
+function BoxerFactory.build(name: string, corner: "Red" | "Blue", seed: number?, parent: Instance?): Rig
+	local model = Instance.new("Model")
+	model.Name = `Boxer_{name}`
+	model:SetAttribute("BoxerRig", true)
+
+	local rng = Random.new(seed or math.random(1, 1_000_000))
+	local skin = SKINS[rng:NextInteger(1, #SKINS)]
+	local trunks = if corner == "Red" then Config.Palette.redCorner else Config.Palette.blueCorner
+	local trim = if corner == "Red" then Color3.fromRGB(245, 232, 220) else Color3.fromRGB(236, 240, 250)
+	local glove = if corner == "Red" then Color3.fromRGB(150, 34, 30) else Color3.fromRGB(32, 66, 124)
+	local boot = Color3.fromRGB(28, 28, 32)
+
+	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), Color3.new(0.3, 0.3, 0.3), Enum.Material.SmoothPlastic, model)
+	root.CFrame = CFrame.new(0, 3.1, 0)
+	root.Transparency = 1
+
+	local pelvis = makePart("LowerTorso", Vector3.new(1.92, 1.05, 1.02), trunks, Enum.Material.Fabric, model)
+	pelvis.CFrame = CFrame.new(0, 2.9, 0)
+
+	local torso = makePart("UpperTorso", Vector3.new(2.05, 1.5, 1.12), skin, Enum.Material.SmoothPlastic, model)
+	torso.CFrame = CFrame.new(0, 4.05, 0)
+
+	local head = makePart("Head", Vector3.new(1.42, 1.55, 1.38), skin, Enum.Material.SmoothPlastic, model)
+	head.CFrame = CFrame.new(0, 5.35, 0)
+
+	local joints: { [string]: Motor6D } = {}
+	local c0s: { [string]: CFrame } = {}
+
+	local rootJoint, rootC0 = weldJoint("RootJoint", root, pelvis, CFrame.new(0, 3.05, 0), model)
+	joints.RootJoint = rootJoint
+	c0s.RootJoint = rootC0
+
+	local waist, waistC0 = weldJoint("Waist", pelvis, torso, CFrame.new(0, 3.4, 0), model)
+	joints.Waist = waist
+	c0s.Waist = waistC0
+
+	local neck, neckC0 = weldJoint("Neck", torso, head, CFrame.new(0, 4.78, 0), model)
+	joints.Neck = neck
+	c0s.Neck = neckC0
+
+	local leftArmJoints, leftArmC0 = buildArm(model, "Left", -1, torso, skin, glove)
+	local rightArmJoints, rightArmC0 = buildArm(model, "Right", 1, torso, skin, glove)
+	local leftLegJoints, leftLegC0 = buildLeg(model, "Left", -1, pelvis, skin, boot)
+	local rightLegJoints, rightLegC0 = buildLeg(model, "Right", 1, pelvis, skin, boot)
+
+	for joint, motor in leftArmJoints do
+		joints[joint] = motor
+	end
+	for joint, motor in rightArmJoints do
+		joints[joint] = motor
+	end
+	for joint, motor in leftLegJoints do
+		joints[joint] = motor
+	end
+	for joint, motor in rightLegJoints do
+		joints[joint] = motor
+	end
+	for joint, c0 in leftArmC0 do
+		c0s[joint] = c0
+	end
+	for joint, c0 in rightArmC0 do
+		c0s[joint] = c0
+	end
+	for joint, c0 in leftLegC0 do
+		c0s[joint] = c0
+	end
+	for joint, c0 in rightLegC0 do
+		c0s[joint] = c0
+	end
+
+	-- Trunks: waistband, side stripes and a belt so the corner colours read at
+	-- a distance in third person.
+	local waistband = makePart("Waistband", Vector3.new(2.0, 0.3, 1.1), trim, Enum.Material.Fabric, model)
+	waistband.CFrame = CFrame.new(0, 3.42, 0)
+	local bandWeld = Instance.new("WeldConstraint")
+	bandWeld.Part0 = waistband
+	bandWeld.Part1 = pelvis
+	bandWeld.Parent = waistband
+
+	local belt = makePart("Belt", Vector3.new(2.02, 0.16, 1.08), Config.Palette.gold, Enum.Material.Metal, model)
+	belt.CFrame = CFrame.new(0, 3.5, 0)
+	local beltWeld = Instance.new("WeldConstraint")
+	beltWeld.Part0 = belt
+	beltWeld.Part1 = pelvis
+	beltWeld.Parent = belt
+
+	-- Headguard: a thin band across the brow keeps the silhouette boxer-like
+	-- without hiding the face.
+	local guardBand = makePart("Headguard", Vector3.new(1.5, 0.3, 1.46), glove, Enum.Material.Leather, model)
+	guardBand.CFrame = CFrame.new(0, 5.78, 0)
+	local guardWeld = Instance.new("WeldConstraint")
+	guardWeld.Part0 = guardBand
+	guardWeld.Part1 = head
+	guardWeld.Parent = guardBand
+
+	-- Name tag.
+	local billboard = Instance.new("BillboardGui")
+	billboard.Name = "NameTag"
+	billboard.Size = UDim2.fromOffset(180, 34)
+	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.45, 0)
+	billboard.AlwaysOnTop = true
+	billboard.MaxDistance = 90
+	billboard.Parent = head
+
+	local label = Instance.new("TextLabel")
+	label.Size = UDim2.fromScale(1, 1)
+	label.BackgroundTransparency = 1
+	label.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
+	label.Text = string.upper(name)
+	label.TextScaled = true
+	label.TextColor3 = trim
+	label.TextStrokeTransparency = 0.4
+	label.TextStrokeColor3 = Color3.new(0, 0, 0)
+	label.Parent = billboard
+
+	-- A Humanoid is useful for nameplate scaling and future ragdoll work, but
+	-- bots are moved manually, so it is configured to stay out of the way.
+	local humanoid = Instance.new("Humanoid")
+	humanoid.DisplayName = name
+	humanoid.HipHeight = 0
+	humanoid.WalkSpeed = 0
+	humanoid.PlatformStand = true
+	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
+	humanoid.Parent = model
+	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
+
+	local animator = Instance.new("Animator")
+	animator.Parent = humanoid
+
+	model.PrimaryPart = root
+	if parent then
+		model.Parent = parent
+	end
+
+	return {
+		model = model,
+		humanoid = humanoid,
+		root = root,
+		joints = joints,
+		c0 = c0s,
+		rigType = "Boxer",
+	}
+end
+
+-- Put a rig at a spot, facing a target point.
+function BoxerFactory.place(rig: Rig, position: Vector3, face: Vector3)
+	local look = CFrame.lookAt(position, Vector3.new(face.X, position.Y, face.Z))
+	rig.model:PivotTo(look)
+end
+
+-- Drop the rig (used on KO so the boxer lies on the canvas rather than
+-- standing up through it). Purely visual; combat state is authoritative.
+function BoxerFactory.setAnchored(rig: Rig, anchored: boolean)
+	for _, part in rig.model:GetDescendants() do
+		if part:IsA("BasePart") then
+			part.Anchored = anchored
+		end
+	end
+end
+
+return BoxerFactory
