diff --git a/src/server/lib/PoseAnimator.luau b/src/server/lib/PoseAnimator.luau
new file mode 100644
index 0000000..caa3c70
--- /dev/null
+++ b/src/server/lib/PoseAnimator.luau
@@ -0,0 +1,297 @@
+--!strict
+-- Server-side pose driver for every boxer in the ring.
+--
+-- Two animation layers, in priority order:
+--   1. Mixamo tracks. If Config.Animations[slot] is a non-empty id, that
+--      AnimationTrack is played and the pose layer steps aside, because the
+--      Animator and Motor6D.Transform both write to the same joints.
+--   2. Procedural poses from AnimationLibrary. Always available, so the game
+--      is fully playable on a fresh place with zero uploaded assets.
+--
+-- The pose layer crossfades between states so a jab resolves back into the
+-- stance without a hard snap.
+
+local RunService = game:GetService("RunService")
+
+local Shared = game:GetService("ReplicatedStorage").Shared
+local Config = require(Shared.Config)
+local Library = require(Shared.AnimationLibrary)
+local Poser = require(Shared.Poser)
+
+export type Slot =
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
+export type Rig = {
+	model: Model,
+	humanoid: Humanoid,
+	root: BasePart,
+	joints: { [string]: Motor6D },
+	c0: { [string]: CFrame },
+	rigType: "R6" | "R15" | "Boxer",
+}
+
+local PoseAnimator = {}
+PoseAnimator.__index = PoseAnimator
+
+export type PoseDriver = typeof(setmetatable(
+	{} :: {
+		rig: Rig,
+		blend: number,
+		slot: Slot,
+		startedAt: number,
+		duration: number,
+		attackSide: string?,
+		severity: number,
+		dodgeDir: number,
+		time: number,
+		track: AnimationTrack?,
+		trackSlot: Slot?,
+		animator: Animator?,
+		stepConnection: RBXScriptConnection?,
+		mixamoBusyUntil: number,
+		movingSpeed: number,
+		strafe: number,
+		enabled: boolean,
+	},
+	PoseAnimator
+))
+
+-- Wipe every joint back to its rest pose. Used when a fighter leaves the ring
+-- so nobody keeps the boxer stance in the lobby.
+function PoseAnimator.rest(rig: Rig)
+	for _, motor in rig.joints do
+		motor.Transform = CFrame.identity
+	end
+end
+
+function PoseAnimator.new(rig: Rig): PoseDriver
+	local self = setmetatable({}, PoseAnimator) :: any
+	self.rig = rig
+	self.blend = 1
+	self.slot = "Idle"
+	self.startedAt = os.clock()
+	self.duration = 0
+	self.attackSide = nil
+	self.severity = 1
+	self.dodgeDir = 1
+	self.time = math.random() * 10
+	self.track = nil
+	self.trackSlot = nil
+	self.animator = rig.humanoid:FindFirstChildOfClass("Animator")
+	self.stepConnection = nil
+	self.mixamoBusyUntil = 0
+	self.movingSpeed = 0
+	self.strafe = 0
+	self.enabled = true
+	return self :: PoseDriver
+end
+
+function PoseAnimator.setSlot(self: PoseDriver, slot: Slot, duration: number, opts: { attack: string?, severity: number?, dodgeDir: number? }?)
+	local striking = slot == "Jab" or slot == "Cross" or slot == "Hook" or slot == "Uppercut"
+	if self.slot == slot and not striking then
+		return
+	end
+	self.slot = slot
+	self.startedAt = os.clock()
+	self.duration = duration
+	self.attackSide = if opts and opts.attack then opts.attack else nil
+	self.severity = if opts and opts.severity then opts.severity else 1
+	self.dodgeDir = if opts and opts.dodgeDir then opts.dodgeDir else 1
+	self.blend = 0
+
+	local animId = Config.Animations[slot]
+	if animId ~= "" and self.animator then
+		self:playMixamo(slot, animId, duration)
+	end
+end
+
+function PoseAnimator.playMixamo(self: PoseDriver, slot: Slot, animationId: string, duration: number)
+	if self.track then
+		self.track:Stop(0.08)
+		self.track:Destroy()
+		self.track = nil
+	end
+	local animator = self.animator :: Instance?
+	if not animator or not animator:IsA("Animator") then
+		return
+	end
+	local animation = Instance.new("Animation")
+	animation.AnimationId = if string.find(animationId, "rbxassetid://", 1, true)
+		then animationId
+		else `rbxassetid://{animationId}`
+	local ok, track = pcall(function()
+		return (animator :: Animator):LoadAnimation(animation)
+	end)
+	animation:Destroy()
+	if not ok or typeof(track) ~= "Instance" then
+		return
+	end
+	local loaded = track :: AnimationTrack
+	loaded.Priority = Enum.AnimationPriority.Action
+	loaded.Looped = false
+	loaded:Play(0.08, 1, 1)
+	self.track = loaded
+	self.trackSlot = slot
+	self.mixamoBusyUntil = os.clock() + math.max(duration, 0.15)
+end
+
+function PoseAnimator.setMotion(self: PoseDriver, speed: number, strafe: number)
+	self.movingSpeed = speed
+	self.strafe = strafe
+end
+
+local function locomotionLayer(animator: PoseDriver): { [string]: CFrame }
+	if animator.movingSpeed <= 0.6 then
+		return {}
+	end
+	local source = Library.locomotion(animator.time, animator.movingSpeed, animator.strafe)
+	-- Arms stay in guard while the legs walk: copy only the lower body and
+	-- spine so the guard does not pump with the stride.
+	local walk: { [string]: CFrame } = {}
+	for joint, cf in source do
+		if joint ~= "LeftShoulder" and joint ~= "RightShoulder" then
+			walk[joint] = cf
+		end
+	end
+	walk.Waist = CFrame.Angles(0, 0, 0)
+	return walk
+end
+
+function PoseAnimator.evaluate(self: PoseDriver, now: number): { [string]: CFrame }
+	local t = now - self.startedAt
+	local phase = if self.duration > 0 then math.clamp(t / self.duration, 0, 1) else 0
+	local stance = Library.stance()
+	local slot = self.slot
+	local pose: { [string]: CFrame }
+
+	if slot == "Idle" then
+		pose = Poser.blend(stance, Library.idle(self.time, 1), 1)
+		pose = Poser.blend(pose, locomotionLayer(self), 1)
+	elseif slot == "Guard" then
+		pose = Poser.blend(Poser.blend(stance, Library.guard(), 1), locomotionLayer(self), 1)
+	elseif slot == "Block" then
+		pose = Poser.blend(stance, Library.block(), 1)
+	elseif slot == "Jab" then
+		pose = Poser.blend(stance, Library.jab(phase), 1)
+	elseif slot == "Cross" then
+		pose = Poser.blend(stance, Library.cross(phase), 1)
+	elseif slot == "Hook" then
+		local side: "Left" | "Right" = if self.attackSide == "Right" then "Right" else "Left"
+		pose = Poser.blend(stance, Library.hook(phase, side), 1)
+	elseif slot == "Uppercut" then
+		local side: "Left" | "Right" = if self.attackSide == "Left" then "Left" else "Right"
+		pose = Poser.blend(stance, Library.uppercut(phase, side), 1)
+	elseif slot == "Dodge" then
+		pose = Poser.blend(stance, Library.dodge(phase, self.dodgeDir), 1)
+	elseif slot == "Hit" then
+		pose = Poser.blend(stance, Library.hit(phase, self.severity), 1)
+	elseif slot == "Stun" then
+		local wobble = math.sin(self.time * 14) * 0.12
+		pose = Poser.blend(stance, Library.hit(0.65, 0.5), 1)
+		pose = Poser.blend(pose, {
+			Waist = CFrame.Angles(0, wobble, wobble * 0.6),
+			Neck = CFrame.Angles(wobble, 0, 0),
+		}, 1)
+	elseif slot == "KO" then
+		pose = Poser.blend(stance, Library.ko(math.min(1, phase + 0.35), self.dodgeDir), 1)
+	elseif slot == "Victory" then
+		pose = Poser.blend(stance, Library.victory(phase), 1)
+	elseif slot == "Intro" then
+		pose = Poser.blend(stance, Library.idle(self.time * 1.6, 0.8), 1)
+	else
+		pose = stance
+	end
+
+	return pose
+end
+
+function PoseAnimator.update(self: PoseDriver, dt: number)
+	if not self.enabled then
+		return
+	end
+	self.time += dt
+
+	local now = os.clock()
+	local rig = self.rig
+	if not rig.model.Parent or not rig.humanoid.Parent then
+		self:stop()
+		return
+	end
+
+	-- Mixamo owns the joints while its track runs.
+	if self.track and self.trackSlot and now < self.mixamoBusyUntil then
+		local track: AnimationTrack = self.track :: AnimationTrack
+		local elapsed: number = (track :: any).Time or 0
+		local length: number = (track :: any).Length or 0
+		if length > 0 and elapsed >= length then
+			self.mixamoBusyUntil = 0
+		else
+			return
+		end
+	end
+
+	local targetPose = self:evaluate(now)
+
+	local slot = self.slot
+	local blendRate = if slot == "Jab" or slot == "Cross" or slot == "Hook" or slot == "Uppercut"
+		then 22
+		elseif slot == "Hit" or slot == "Dodge" then 18
+		elseif slot == "KO" then 6
+		else 10
+	self.blend = math.min(1, self.blend + dt * blendRate)
+	local alpha = math.clamp(self.blend, 0, 1)
+
+	for joint, rotation in targetPose do
+		local motor = rig.joints[joint]
+		local c0: CFrame? = rig.c0[joint]
+		if motor and c0 then
+			local blendedRotation = CFrame.identity:Lerp(rotation, alpha)
+			local transform = Poser.jointTransform(c0 :: CFrame, blendedRotation)
+			motor.Transform = motor.Transform:Lerp(transform, math.min(1, dt * 30))
+		end
+	end
+
+	-- Joints the target pose does not touch relax back to rest.
+	for joint, motor in rig.joints do
+		if not targetPose[joint] then
+			motor.Transform = motor.Transform:Lerp(CFrame.identity, math.min(1, dt * 8))
+		end
+	end
+end
+
+function PoseAnimator.start(self: PoseDriver)
+	if self.stepConnection then
+		return
+	end
+	self.stepConnection = RunService.Stepped:Connect(function(_, dt)
+		self:update(dt)
+	end)
+end
+
+function PoseAnimator.stop(self: PoseDriver)
+	if self.stepConnection then
+		self.stepConnection:Disconnect()
+		self.stepConnection = nil
+	end
+	if self.track then
+		self.track:Stop()
+		self.track:Destroy()
+		self.track = nil
+	end
+	self.trackSlot = nil
+	PoseAnimator.rest(self.rig)
+end
+
+return PoseAnimator
