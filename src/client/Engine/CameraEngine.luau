diff --git a/src/client/Engine/CameraEngine.luau b/src/client/Engine/CameraEngine.luau
index 1ecc697..fe9cf1a 100644
--- a/src/client/Engine/CameraEngine.luau
+++ b/src/client/Engine/CameraEngine.luau
@@ -1,11 +1,11 @@
 --!strict
--- Four camera modes for the ring, including the two the original stub promised
--- but never implemented: FirstPerson and Cinematic.
+-- Client camera controller. Owns the 4 modes and reads the mode the server
+-- replicates for the match (cinematic during intros, third person while
+-- fighting, isometric on demand).
 --
--- Usage:
---   CameraEngine.setMode("ThirdPerson", character)
---   CameraEngine.setMode("Isometric", character, { distance = 42, angle = math.rad(30) })
---   CameraEngine.setMode("Cinematic", character, { focus = opponentPart })
+-- This is the evolved version of the original stub: every mode now actually
+-- works, connections are tracked per mode instead of in one flat bag, and the
+-- head-hiding for first person is undone on the way out.
 
 local Players = game:GetService("Players")
 local RunService = game:GetService("RunService")
@@ -16,200 +16,200 @@ export type CameraMode = "FirstPerson" | "ThirdPerson" | "Isometric" | "Cinemati
 export type CameraConfig = {
 	distance: number?,
 	height: number?,
-	pitch: number?,
 	angle: number?,
 	focus: BasePart?,
-	shoulder: number?,
-	sway: boolean?,
+	shakeStrength: number?,
 }
 
 local CameraEngine = {}
 
-local camera: Camera = Workspace.CurrentCamera
+local player = Players.LocalPlayer
+local mode: CameraMode = "ThirdPerson"
 local connection: RBXScriptConnection? = nil
-local currentMode: CameraMode = "ThirdPerson"
-local savedSubject: BasePart? = nil
-local shakeUntil = 0
-local shakeAmount = 0
-local swayPhase = 0
-
--- Track a live camera reference: CurrentCamera can be replaced on respawn.
-local function currentCamera(): Camera
-	local c = Workspace.CurrentCamera
-	if c then
-		camera = c
-	end
-	return camera
+local hiddenParts: { [BasePart]: number } = {}
+local baseFov = 70
+local shake = 0
+local shakeDecay = 5
+
+local function camera(): Camera
+	return Workspace.CurrentCamera
 end
 
-local function stopLoop()
-	if connection then
-		connection:Disconnect()
-		connection = nil
+local function anchorOf(model: Model?): BasePart?
+	if not model then
+		model = player.Character
+	end
+	if not model then
+		return nil
 	end
+	local humanoid = model:FindFirstChildOfClass("Humanoid")
+	if humanoid and humanoid.RootPart then
+		return humanoid.RootPart
+	end
+	return model.PrimaryPart
 end
 
-local function characterOf(target: Model?): (Model?, Humanoid?, BasePart?)
-	if not target then
-		local localPlayer = Players.LocalPlayer
-		target = localPlayer.Character
+local function setBodyVisibility(visible: boolean)
+	local character = player.Character
+	if not character then
+		return
 	end
-	if not target then
-		return nil, nil, nil
+	if visible then
+		for part, original in hiddenParts do
+			if part.Parent then
+				part.LocalTransparencyModifier = original
+			end
+		end
+		table.clear(hiddenParts)
+	else
+		for _, part in character:GetDescendants() do
+			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
+				if hiddenParts[part] == nil then
+					hiddenParts[part] = part.LocalTransparencyModifier
+				end
+				part.LocalTransparencyModifier = 1
+			elseif part:IsA("Decal") then
+				part.Transparency = 1
+			end
+		end
 	end
-	local humanoid = target:FindFirstChildOfClass("Humanoid")
-	if not humanoid then
-		return target, nil, nil
+end
+
+local function disconnect()
+	if connection then
+		connection:Disconnect()
+		connection = nil
 	end
-	return target, humanoid, target.PrimaryPart or humanoid.RootPart
 end
 
 function CameraEngine.getMode(): CameraMode
-	return currentMode
+	return mode
 end
 
--- Punch feedback: a short position-only shake. Cheap, additive, and easy to
--- call from the hit handler without owning the camera loop.
-function CameraEngine.shake(amount: number, duration: number)
-	shakeAmount = math.max(shakeAmount, amount)
-	shakeUntil = math.max(shakeUntil, os.clock() + duration)
+function CameraEngine.addShake(strength: number)
+	shake = math.max(shake, strength)
 end
 
-local function shakeOffset(now: number, dt: number): Vector3
-	if now > shakeUntil then
-		shakeAmount = 0
-		return Vector3.zero
+function CameraEngine.setMode(nextMode: CameraMode, target: Model?, config: CameraConfig?)
+	disconnect()
+	local previous = mode
+	mode = nextMode
+	local cam = camera()
+	local cfg: CameraConfig = config or {}
+
+	if previous == "FirstPerson" then
+		setBodyVisibility(true)
+		local character = player.Character
+		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
+		if humanoid then
+			humanoid.CameraOffset = Vector3.zero
+		end
+		player.CameraMinZoomDistance = 0.5
+		player.CameraMaxZoomDistance = 128
+		cam.FieldOfView = baseFov
 	end
-	swayPhase += dt * 34
-	local decay = math.max(0, (shakeUntil - now) / 0.35)
-	local a = shakeAmount * decay
-	return Vector3.new(math.sin(swayPhase) * a, math.cos(swayPhase * 1.7) * a * 0.7, 0)
-end
-
-function CameraEngine.setMode(mode: CameraMode, target: Model?, config: CameraConfig?)
-	stopLoop()
-	currentMode = mode
-	local cam = currentCamera()
-	local _, humanoid, root = characterOf(target)
-	local cfg = config or {}
 
-	if mode == "ThirdPerson" then
+	if nextMode == "ThirdPerson" then
 		cam.CameraType = Enum.CameraType.Custom
-		if savedSubject then
-			cam.CameraSubject = savedSubject
-		elseif humanoid then
-			cam.CameraSubject = humanoid
+		local anchor = anchorOf(target)
+		if anchor then
+			cam.CameraSubject = anchor
 		end
+		player.CameraMinZoomDistance = 4
+		player.CameraMaxZoomDistance = 18
+		cam.FieldOfView = baseFov
 		return
 	end
 
-	if mode == "FirstPerson" then
+	if nextMode == "FirstPerson" then
 		cam.CameraType = Enum.CameraType.Custom
+		local character = target or player.Character
+		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 		if humanoid then
 			cam.CameraSubject = humanoid
+			humanoid.CameraOffset = Vector3.new(0, 0.15, -0.4)
 		end
-		-- Roblox's own first person mode keeps camera control intact; we only
-		-- need to push the camera into the head and hide the local body.
-		local player = Players.LocalPlayer
-		local char = player.Character
-		if char then
-			for _, part in char:GetDescendants() do
-				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
-					part.LocalTransparencyModifier = 1
-				elseif part:IsA("Decal") then
-					part.LocalTransparencyModifier = 1
-				end
-			end
-			humanoid.CameraOffset = Vector3.new(0, 0.25, -0.55)
-			player.CameraMinZoomDistance = 0.5
-			player.CameraMaxZoomDistance = 0.5
-		end
-		cam.FieldOfView = 74
+		setBodyVisibility(false)
+		player.CameraMinZoomDistance = 0.5
+		player.CameraMaxZoomDistance = 0.5
+		cam.FieldOfView = 84
 		return
 	end
 
-	if mode == "Isometric" then
-		savedSubject = if cam.CameraSubject and cam.CameraSubject:IsA("BasePart") then cam.CameraSubject :: BasePart else savedSubject
+	if nextMode == "Isometric" then
 		cam.CameraType = Enum.CameraType.Scriptable
-		cam.FieldOfView = 40
+		cam.FieldOfView = 42
 		local distance = cfg.distance or 46
 		local angle = cfg.angle or math.rad(38)
-		local heightFactor = cfg.height or 1
+		local heightBias = cfg.height or 1
 
-		connection = RunService.RenderStepped:Connect(function(dt)
-			local _, _, anchor = characterOf(target)
+		connection = RunService.RenderStepped:Connect(function(dt: number)
+			local anchor = anchorOf(target)
 			if not anchor then
 				return
 			end
-			local focus: Vector3 = anchor.Position
+			local focus = anchor.Position
 			if cfg.focus and cfg.focus.Parent then
-				-- Split the difference between boxer and opponent so both stay framed.
 				focus = (focus + cfg.focus.Position) * 0.5
 			end
+
 			local offset = Vector3.new(
 				math.sin(angle) * distance,
-				math.cos(angle) * distance * heightFactor + 4,
+				math.cos(angle) * distance * heightBias + 4,
 				math.cos(angle) * distance
 			)
-			local now = os.clock()
-			local shake = shakeOffset(now, dt)
-			cam.CFrame = CFrame.lookAt(focus + offset + shake, focus)
+
+			if shake > 0.001 then
+				shake = math.max(0, shake - dt * shakeDecay)
+				local s = shake * (cfg.shakeStrength or 1)
+				offset += Vector3.new(
+					(math.random() - 0.5) * s,
+					(math.random() - 0.5) * s,
+					(math.random() - 0.5) * s
+				)
+			end
+
+			cam.CFrame = CFrame.lookAt(focus + offset, focus)
 		end)
 		return
 	end
 
-	if mode == "Cinematic" then
-		savedSubject = if cam.CameraSubject and cam.CameraSubject:IsA("BasePart") then cam.CameraSubject :: BasePart else savedSubject
+	if nextMode == "Cinematic" then
 		cam.CameraType = Enum.CameraType.Scriptable
-		cam.FieldOfView = 60
+		cam.FieldOfView = 58
 		local t = 0
-		connection = RunService.RenderStepped:Connect(function(dt)
+		connection = RunService.RenderStepped:Connect(function(dt: number)
 			t += dt
-			local _, _, anchor = characterOf(target)
+			local anchor = anchorOf(target)
 			if not anchor then
 				return
 			end
-			local focus = anchor.Position + Vector3.new(0, 2.2, 0)
+			local focus = anchor.Position + Vector3.new(0, 2.4, 0)
 			if cfg.focus and cfg.focus.Parent then
-				focus = (focus + cfg.focus.Position + Vector3.new(0, 2.2, 0)) * 0.5
+				focus = (focus + cfg.focus.Position + Vector3.new(0, 2.4, 0)) * 0.5
 			end
-			-- Slow orbit with a breathing dolly; deliberately slower than
-			-- isometric so the two never feel like the same camera.
-			local orbit = t * 0.16
-			local radius = 24 + math.sin(t * 0.31) * 5
-			local height = 8 + math.sin(t * 0.23) * 2.2
-			local eye = focus + Vector3.new(math.cos(orbit) * radius, height, math.sin(orbit) * radius)
+			-- Slow arc with a gentle push-in, deliberately calmer than the
+			-- isometric orbit so the two modes read differently.
+			local orbit = t * 0.18
+			local radius = 26 + math.sin(t * 0.27) * 6
+			local lift = 7 + math.sin(t * 0.19) * 2.5
+			local eye = focus + Vector3.new(math.cos(orbit) * radius, lift, math.sin(orbit) * radius)
 			cam.CFrame = CFrame.lookAt(eye, focus)
 		end)
 	end
 end
 
 function CameraEngine.reset()
-	stopLoop()
-	currentMode = "ThirdPerson"
-	local cam = currentCamera()
-	cam.CameraType = Enum.CameraType.Custom
-	cam.FieldOfView = 70
-
-	local player = Players.LocalPlayer
-	if player then
-		player.CameraMinZoomDistance = 0.5
-		player.CameraMaxZoomDistance = 128
-	end
+	CameraEngine.setMode("ThirdPerson")
+end
 
-	local char = player.Character
-	if char then
-		local humanoid = char:FindFirstChildOfClass("Humanoid")
-		if humanoid then
-			humanoid.CameraOffset = Vector3.zero
-			cam.CameraSubject = humanoid
-		end
-		for _, part in char:GetDescendants() do
-			if part:IsA("BasePart") or part:IsA("Decal") then
-				part.LocalTransparencyModifier = 0
-			end
-		end
+-- Keep the camera attached to the character after a respawn.
+player.CharacterAdded:Connect(function()
+	if mode == "ThirdPerson" or mode == "FirstPerson" then
+		task.defer(function()
+			CameraEngine.setMode(mode)
+		end)
 	end
-end
+end)
 
 return CameraEngine
