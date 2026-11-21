diff --git a/src/server/lib/Arena.luau b/src/server/lib/Arena.luau
new file mode 100644
index 0000000..0957e12
--- /dev/null
+++ b/src/server/lib/Arena.luau
@@ -0,0 +1,282 @@
+--!strict
+-- Builds the arena entirely in code so the place works from an empty baseplate.
+-- Ring, ropes, corner posts, house lights, crowd stands and decals.
+
+local Lighting = game:GetService("Lighting")
+local Workspace = game:GetService("Workspace")
+
+local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
+
+local Arena = {}
+
+local function part(props: { [string]: any }, parent: Instance): Part
+	local p = Instance.new("Part")
+	p.Anchored = true
+	p.CanCollide = true
+	p.TopSurface = Enum.SurfaceType.Smooth
+	p.BottomSurface = Enum.SurfaceType.Smooth
+	for key, value in pairs(props) do
+		(p :: any)[key] = value
+	end
+	p.Parent = parent
+	return p
+end
+
+local function cylinder(props: { [string]: any }, parent: Instance): Part
+	local p = part(props, parent)
+	local mesh = Instance.new("SpecialMesh")
+	mesh.MeshType = Enum.MeshType.Cylinder
+	mesh.Scale = Vector3.new(0.98, 0.98, 1)
+	mesh.Parent = p
+	return p
+end
+
+local function ropeRing(parent: Instance, radius: number, height: number, thickness: number, color: Color3)
+	-- Ropes are drawn as a ring of short cylinders so they read as rope, not
+	-- as a floating torus that clips through the fighters.
+	local segments = 28
+	for i = 1, segments do
+		local a = (i / segments) * math.pi * 2
+		local nextA = ((i + 1) / segments) * math.pi * 2
+		local p1 = Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius)
+		local p2 = Vector3.new(math.cos(nextA) * radius, height, math.sin(nextA) * radius)
+		local mid = (p1 + p2) / 2
+		local length = (p2 - p1).Magnitude + 0.06
+		local seg = cylinder({
+			Name = "Rope",
+			Size = Vector3.new(thickness, length, thickness),
+			CFrame = CFrame.lookAt(mid, p2) * CFrame.Angles(math.rad(90), 0, 0),
+			Color = color,
+			Material = Enum.Material.Fabric,
+			CanCollide = false,
+			CastShadow = false,
+		}, parent)
+		seg.Name = "Rope"
+	end
+end
+
+local function crowd(parent: Instance)
+	local seats = Instance.new("Folder")
+	seats.Name = "Crowd"
+	seats.Parent = parent
+	local rng = Random.new(7)
+	local ringRadius = Config.Match.ringSize / 2
+
+	for tier = 1, 6 do
+		local radius = ringRadius + 10 + tier * 5
+		local height = 3 + tier * 2.6
+		local count = math.floor(radius * 2.4)
+		for i = 1, count do
+			local a = (i / count) * math.pi * 2
+			-- Leave the camera-side apron clear.
+			if math.abs(math.sin(a)) > 0.16 or math.cos(a) > 0 then
+				local torso = part({
+					Name = "Fan",
+					Size = Vector3.new(1.1, 1.5, 1.1),
+					CFrame = CFrame.new(math.cos(a) * radius, height, math.sin(a) * radius) * CFrame.Angles(0, -a, 0),
+					Color = Color3.fromHSV(rng:NextNumber(0, 1), 0.35, rng:NextNumber(0.2, 0.55)),
+					Material = Enum.Material.SmoothPlastic,
+					CanCollide = false,
+					CastShadow = false,
+				}, seats)
+				local head = part({
+					Name = "Head",
+					Shape = Enum.PartType.Ball,
+					Size = Vector3.new(0.9, 0.9, 0.9),
+					CFrame = torso.CFrame * CFrame.new(0, 1.1, 0),
+					Color = Color3.fromRGB(92, 66, 54),
+					Material = Enum.Material.SmoothPlastic,
+					CanCollide = false,
+					CastShadow = false,
+				}, seats)
+				head.Name = "Head"
+			end
+		end
+	end
+end
+
+function Arena.build()
+	local existing = Workspace:FindFirstChild("KnockoutRing")
+	if existing then
+		existing:Destroy()
+	end
+
+	local root = Instance.new("Folder")
+	root.Name = "KnockoutRing"
+	root.Parent = Workspace
+
+	local ringRadius = Config.Match.ringSize / 2
+	local baseY = 6
+
+	local apron = part({
+		Name = "Apron",
+		Size = Vector3.new(ringRadius * 2 + 10, 1.4, ringRadius * 2 + 10),
+		CFrame = CFrame.new(0, baseY - 1.2, 0),
+		Color = Config.Palette.ink,
+		Material = Enum.Material.Metal,
+	}, root)
+	apron.Name = "Apron"
+
+	-- Canvas with a painted center logo.
+	local canvas = part({
+		Name = "Canvas",
+		Size = Vector3.new(ringRadius * 2, 0.7, ringRadius * 2),
+		CFrame = CFrame.new(0, baseY, 0),
+		Color = Config.Palette.ringFloor,
+		Material = Enum.Material.Fabric,
+	}, root)
+	canvas.Name = "Canvas"
+
+	local paint = Instance.new("Texture")
+	paint.Name = "CanvasPaint"
+	paint.Texture = "rbxasset://textures/ui/GuiImagePlaceholder.png"
+	paint.Transparency = 0.78
+	paint.Face = Enum.NormalId.Top
+	paint.Parent = canvas
+
+	local center = part({
+		Name = "CenterMark",
+		Shape = Enum.PartType.Cylinder,
+		Size = Vector3.new(0.12, 12, 12),
+		CFrame = CFrame.new(0, baseY + 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
+		Color = Config.Palette.gold,
+		Material = Enum.Material.SmoothPlastic,
+		CanCollide = false,
+	}, root)
+	center.Name = "CenterMark"
+
+	-- Ropes on all four sides at three heights.
+	for _, h in { 1.2, 2.15, 3.1 } do
+		ropeRing(root, ringRadius, baseY + h, 0.16, Config.Palette.ropes)
+	end
+
+	-- Corner posts in red/blue/neutral, topped with pads.
+	type CornerDef = { pos: Vector3, color: Color3 }
+	local corners: { CornerDef } = {
+		{ pos = Vector3.new(ringRadius, 0, ringRadius), color = Config.Palette.redCorner },
+		{ pos = Vector3.new(-ringRadius, 0, -ringRadius), color = Config.Palette.blueCorner },
+		{ pos = Vector3.new(ringRadius, 0, -ringRadius), color = Config.Palette.gold },
+		{ pos = Vector3.new(-ringRadius, 0, ringRadius), color = Config.Palette.gold },
+	}
+	for _, data in corners do
+		local pos = data.pos
+		local color = data.color
+		local post = cylinder({
+			Name = "Post",
+			Size = Vector3.new(0.5, 4.6, 0.5),
+			CFrame = CFrame.new(pos.X, baseY + 2.3, pos.Z),
+			Color = color,
+			Material = Enum.Material.Metal,
+		}, root)
+		post.Name = "Post"
+
+		local pad = part({
+			Name = "Pad",
+			Size = Vector3.new(1.3, 1.9, 1.3),
+			CFrame = CFrame.new(pos.X, baseY + 2.6, pos.Z),
+			Color = color,
+			Material = Enum.Material.Fabric,
+			CanCollide = false,
+		}, root)
+		pad.Name = "Pad"
+	end
+
+	-- Floor outside the ring so players never fall into the void.
+	local floor = part({
+		Name = "Floor",
+		Size = Vector3.new(420, 2, 420),
+		CFrame = CFrame.new(0, -1, 0),
+		Color = Color3.fromRGB(22, 25, 28),
+		Material = Enum.Material.Slate,
+	}, root)
+	floor.Name = "Floor"
+
+	crowd(root)
+
+	-- Lighting rig: a dark hall with hot overhead spots on the canvas.
+	Lighting.Ambient = Color3.fromRGB(18, 16, 17)
+	Lighting.OutdoorAmbient = Color3.fromRGB(12, 12, 16)
+	Lighting.Brightness = 1.1
+	Lighting.ClockTime = 20.5
+	Lighting.FogEnd = 260
+	Lighting.FogColor = Color3.fromRGB(10, 9, 12)
+	Lighting.FogStart = 60
+
+	local existingRig = Lighting:FindFirstChild("RingRig")
+	if existingRig then
+		existingRig:Destroy()
+	end
+	local rig = Instance.new("Folder")
+	rig.Name = "RingRig"
+	rig.Parent = Lighting
+
+	local function spot(offset: Vector3, target: Vector3, brightness: number, color: Color3, angle: number)
+		local light = Instance.new("SpotLight")
+		light.Brightness = brightness
+		light.Range = 120
+		light.Angle = angle
+		light.Color = color
+		light.Face = Enum.NormalId.Bottom
+		light.Shadows = true
+		local anchor = part({
+			Name = "Lamp",
+			Size = Vector3.new(2.2, 0.5, 2.2),
+			CFrame = CFrame.lookAt(offset, target) * CFrame.Angles(math.rad(-90), 0, 0),
+			Color = Color3.fromRGB(14, 14, 16),
+			Material = Enum.Material.Metal,
+			CanCollide = false,
+			CastShadow = false,
+		}, rig)
+		light.Parent = anchor
+	end
+
+	spot(Vector3.new(0, 34, 0), Vector3.new(0, 0, 0), 3.4, Color3.fromRGB(255, 236, 208), 90)
+	spot(Vector3.new(16, 26, 16), Vector3.new(0, 6, 0), 2.0, Color3.fromRGB(255, 214, 170), 70)
+	spot(Vector3.new(-16, 26, -16), Vector3.new(0, 6, 0), 2.0, Color3.fromRGB(170, 206, 255), 70)
+	spot(Vector3.new(0, 20, -26), Vector3.new(0, 6, 0), 1.2, Color3.fromRGB(255, 120, 90), 60)
+	spot(Vector3.new(0, 20, 26), Vector3.new(0, 6, 0), 1.2, Color3.fromRGB(90, 150, 255), 60)
+
+	local existingFx = Lighting:FindFirstChild("RingFx")
+	if existingFx then
+		existingFx:Destroy()
+	end
+	local fx = Instance.new("Folder")
+	fx.Name = "RingFx"
+	fx.Parent = Lighting
+
+	local bloom = Instance.new("BloomEffect")
+	bloom.Intensity = 0.55
+	bloom.Size = 28
+	bloom.Threshold = 0.9
+	bloom.Parent = fx
+
+	local colorCorrection = Instance.new("ColorCorrectionEffect")
+	colorCorrection.Contrast = 0.12
+	colorCorrection.Saturation = -0.06
+	colorCorrection.TintColor = Color3.fromRGB(255, 244, 228)
+	colorCorrection.Parent = fx
+
+	local atmosphere = Instance.new("Atmosphere")
+	atmosphere.Density = 0.42
+	atmosphere.Haze = 2.2
+	atmosphere.Color = Color3.fromRGB(122, 110, 102)
+	atmosphere.Decay = Color3.fromRGB(60, 50, 52)
+	atmosphere.Glare = 0.25
+	atmosphere.Parent = fx
+
+	-- Spawn location used only for lobby visitors, kept off the canvas.
+	local spawn = Instance.new("SpawnLocation")
+	spawn.Name = "LobbySpawn"
+	spawn.Size = Vector3.new(6, 0.4, 6)
+	spawn.CFrame = CFrame.new(0, 0.2, ringRadius + 22)
+	spawn.Anchored = true
+	spawn.CanCollide = true
+	spawn.Transparency = 1
+	spawn.Neutral = true
+	spawn.Duration = 0
+	spawn.Parent = root
+
+	return root, baseY, ringRadius
+end
+
+return Arena
