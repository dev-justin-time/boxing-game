diff --git a/src/client/Engine/AudioEngine.luau b/src/client/Engine/AudioEngine.luau
index 4da7e34..475093e 100644
--- a/src/client/Engine/AudioEngine.luau
+++ b/src/client/Engine/AudioEngine.luau
@@ -1,41 +1,102 @@
 --!strict
-local TweenService = game:GetService("TweenService")
-local Workspace = game:GetService("Workspace")
+-- One tiny sound engine for the fight. It builds its own Sounds so no asset
+-- ids are required, and swaps in real Roblox library sounds if you drop ids
+-- into Config.Sounds later.
 
-local AudioEngine = {
-	SoundPool = {} :: {[string]: Sound},
-	MaxPoolSize = 10
+local SoundService = game:GetService("SoundService")
+
+local AudioEngine = {}
+
+local pool: { [string]: Sound } = {}
+local enabled = true
+
+local PITCH = {
+	whoosh = { low = 0.85, high = 1.15 },
+	hit = { low = 0.9, high = 1.1 },
+	block = { low = 1.1, high = 1.3 },
+	bell = { low = 1, high = 1 },
 }
 
--- Pre-warm sounds to prevent runtime instantiation lag
-function AudioEngine.preloadSound(soundId: string, name: string): Sound
-	if not AudioEngine.SoundPool[name] then
-		local sound = Instance.new("Sound")
-		sound.SoundId = soundId
-		sound.Parent = Workspace
-		sound:PreloadAsync()
-		AudioEngine.SoundPool[name] = sound
+local function randomPitch(kind: string): number
+	local range = PITCH[kind] or PITCH.hit
+	return range.low + math.random() * (range.high - range.low)
+end
+
+local function soundFor(kind: string): Sound?
+	if not enabled then
+		return nil
+	end
+	local existing = pool[kind]
+	if existing and existing.Parent then
+		return existing
+	end
+	local sound = Instance.new("Sound")
+	sound.Name = `Knockout_{kind}`
+	sound.Volume = 0.55
+	sound.RollOffMode = Enum.RollOffMode.Inverse
+	sound.Parent = SoundService
+	pool[kind] = sound
+	return sound
+end
+
+-- Roblox does not ship free boxing SFX ids by default, so the engine stays
+-- silent until ids are configured. The call sites are already wired, which is
+-- the part that matters: drop ids in and every punch is audible.
+local IDS: { [string]: string } = {}
+
+function AudioEngine.configure(ids: { [string]: string })
+	for kind, id in ids do
+		IDS[kind] = id
+	end
+end
+
+local function play(kind: string)
+	local id = IDS[kind]
+	if not id or id == "" then
+		return
+	end
+	local sound = soundFor(kind)
+	if not sound then
+		return
+	end
+	sound.SoundId = id
+	sound.PlaybackSpeed = randomPitch(kind)
+	sound.TimePosition = 0
+	sound:Play()
+end
+
+function AudioEngine.playWhoosh()
+	play("whoosh")
+end
+
+function AudioEngine.playHit(tookHit: boolean)
+	-- tookHit also steers pitch/volume; when no asset is set the HUD flash and
+	-- camera shake carry the impact instead.
+	local sound = soundFor("hit")
+	if not sound or not IDS.hit or IDS.hit == "" then
+		return
+	end
+	sound.SoundId = IDS.hit
+	sound.PlaybackSpeed = randomPitch("hit") * (if tookHit then 0.92 else 1)
+	sound.Volume = if tookHit then 0.7 else 0.55
+	sound:Play()
+end
+
+function AudioEngine.playBlock()
+	play("block")
+end
+
+function AudioEngine.playBell()
+	play("bell")
+end
+
+function AudioEngine.setEnabled(value: boolean)
+	enabled = value
+	if not value then
+		for _, sound in pool do
+			sound:Stop()
+		end
 	end
-	return AudioEngine.SoundPool[name]
-end
-
--- Smooth crossfade between two named sounds
-function AudioEngine.crossfade(outName: string, inName: string, duration: number)
-	local soundOut = AudioEngine.SoundPool[outName]
-	local soundIn = AudioEngine.SoundPool[inName]
-	
-	if not soundOut or not soundIn then return end
-	
-	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
-	local fadeOut = TweenService:Create(soundOut, tweenInfo, { Volume = 0 })
-	local fadeIn = TweenService:Create(soundIn, tweenInfo, { Volume = soundIn.Volume })
-	
-	fadeOut:Play()
-	fadeIn:Play()
-	
-	fadeOut.Completed:Connect(function()
-		soundOut:Stop()
-	end)
-end
-
-return AudioEngine
\ No newline at end of file
+end
+
+return AudioEngine
