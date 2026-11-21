diff --git a/src/client/init.client.luau b/src/client/init.client.luau
new file mode 100644
index 0000000..83ad7ba
--- /dev/null
+++ b/src/client/init.client.luau
@@ -0,0 +1,206 @@
+--!strict
+-- Client entry point.
+--
+-- Flow: lobby -> queue -> intro (cinematic) -> fight (third person) -> round
+-- end -> next round or match end -> back to lobby. All match state arrives in
+-- the server snapshot; the client renders it and sends intents.
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+local Workspace = game:GetService("Workspace")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Net = require(Shared.Net)
+local Types = require(Shared.Types)
+
+local Hud = require(script.Hud)
+local CombatInput = require(script.CombatInput)
+local CameraEngine = require(script.Engine.CameraEngine)
+local AudioEngine = require(script.Engine.AudioEngine)
+
+local player = Players.LocalPlayer
+
+local latest: Types.Snapshot? = nil
+local cameraModeSet = ""
+
+-- ------------------------------------------------------------------ helpers
+
+local function stagedCharacter()
+	local character = player.Character
+	if not character then
+		return nil
+	end
+	return character
+end
+
+local function applyCameraForSnapshot(snapshot: Types.Snapshot)
+	if snapshot.cameraMode == cameraModeSet and cameraModeSet ~= "" then
+		return
+	end
+	cameraModeSet = snapshot.cameraMode
+
+	local character = stagedCharacter()
+	if snapshot.cameraMode == "Cinematic" then
+		CameraEngine.setMode("Cinematic", character)
+	elseif snapshot.cameraMode == "Isometric" then
+		CameraEngine.setMode("Isometric", character, { distance = 44, angle = math.rad(34) })
+	else
+		CameraEngine.setMode("ThirdPerson", character)
+	end
+end
+
+local function sendCamera(mode: string)
+	if mode == "FirstPerson" then
+		CameraEngine.setMode("FirstPerson", stagedCharacter())
+	elseif mode == "Isometric" then
+		CameraEngine.setMode("Isometric", stagedCharacter(), { distance = 44, angle = math.rad(34) })
+	elseif mode == "Cinematic" then
+		CameraEngine.setMode("Cinematic", stagedCharacter())
+	else
+		CameraEngine.setMode("ThirdPerson", stagedCharacter())
+	end
+	cameraModeSet = ""
+end
+
+-- ------------------------------------------------------------------ build UI
+
+Hud.build()
+
+Hud.bind({
+	queue = function(mode: string, difficulty: string?)
+		Net.requestQueue():FireServer(mode, difficulty)
+	end,
+	cancelQueue = function()
+		Net.requestCancelQueue():FireServer()
+	end,
+	punch = function(attack: string)
+		Net.requestAttack():FireServer(attack)
+	end,
+	block = function(blocking: boolean)
+		Net.requestBlock():FireServer(blocking)
+	end,
+	dodge = function()
+		Net.requestDodge():FireServer(1)
+	end,
+	setCamera = function(mode: string)
+		sendCamera(mode)
+	end,
+})
+
+CombatInput.bind({
+	punch = function(attack: string)
+		Net.requestAttack():FireServer(attack)
+	end,
+	block = function(blocking: boolean)
+		Net.requestBlock():FireServer(blocking)
+	end,
+	dodge = function()
+		Net.requestDodge():FireServer(1)
+	end,
+	sprint = function(_sprinting: boolean)
+		-- Sprint speed is server-owned; the input exists so held-Shift does not
+		-- fight the default character controller.
+	end,
+})
+
+-- ------------------------------------------------------------------ events
+
+local function fighterIsMine(fighterId: string?): boolean
+	local snapshot = latest
+	if not snapshot or not fighterId then
+		return false
+	end
+	return snapshot.you == fighterId
+end
+
+Net.snapshot().OnClientEvent:Connect(function(snapshot: Types.Snapshot)
+	latest = snapshot
+	Hud.applySnapshot(snapshot)
+	applyCameraForSnapshot(snapshot)
+
+	if snapshot.banner == "FIGHT" and snapshot.phase == "Round" then
+		CameraEngine.addShake(0.6)
+	end
+end)
+
+Net.combatEvent().OnClientEvent:Connect(function(event: Types.CombatEvent)
+	local kind = event.kind
+	if kind == "hit" then
+		if fighterIsMine(event.target) then
+			Hud.onHitYou(event.damage or 0)
+			CameraEngine.addShake(event.shake or 0.3)
+			AudioEngine.playHit(true)
+		elseif fighterIsMine(event.attacker) then
+			Hud.onHitThem(event.damage or 0, event.combo or 0)
+			AudioEngine.playHit(false)
+		end
+	elseif kind == "block" then
+		if fighterIsMine(event.target) or fighterIsMine(event.attacker) then
+			Hud.onBlocked()
+			AudioEngine.playBlock()
+		end
+	elseif kind == "guardBreak" then
+		if fighterIsMine(event.target) then
+			Hud.onGuardBreak()
+			CameraEngine.addShake(0.9)
+		end
+	elseif kind == "dodge" then
+		if fighterIsMine(event.target) then
+			Hud.onDodge()
+		end
+	elseif kind == "swing" then
+		AudioEngine.playWhoosh()
+	elseif kind == "roundEnd" then
+		AudioEngine.playBell()
+	end
+end)
+
+Net.setCameraMode().OnClientEvent:Connect(function(mode: unknown)
+	if type(mode) == "string" then
+		Hud.setCameraMode(mode)
+		sendCamera(mode)
+	end
+end)
+
+-- ------------------------------------------------------------------ character
+
+local function onCharacter(character: Model)
+	local humanoid = character:WaitForChild("Humanoid", 8)
+	if not humanoid or not humanoid:IsA("Humanoid") then
+		return
+	end
+
+	-- The ring is a seated arena: players walk in the lobby and are pulled
+	-- onto the canvas by the match. Keep the default controller sane.
+	humanoid.WalkSpeed = 16
+	humanoid.JumpPower = 0
+	humanoid.UseJumpPower = true
+
+	local snapshot = latest
+	if snapshot and snapshot.phase ~= "Lobby" and snapshot.phase ~= "Queued" then
+		CameraEngine.setMode("ThirdPerson", character)
+		cameraModeSet = ""
+	end
+end
+
+if player.Character then
+	task.spawn(onCharacter, player.Character)
+end
+player.CharacterAdded:Connect(onCharacter)
+
+-- Keep every screen resize sane; the HUD is anchored, so this only refreshes
+-- the camera FOV for very tall or wide windows.
+local function onViewport()
+	local camera = Workspace.CurrentCamera
+	if not camera then
+		return
+	end
+	local aspect = camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y)
+	camera.FieldOfView = if aspect < 1 then 82 else 70
+end
+Workspace.CurrentCamera.Changed:Connect(function(prop)
+	if prop == "ViewportSize" then
+		onViewport()
+	end
+end)
+onViewport()
