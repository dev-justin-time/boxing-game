--!strict
-- Server-side pose driver for every boxer in the ring.
--
-- Two animation layers, in priority order:
--   1. Mixamo tracks. If Config.Animations[slot] is a non-empty id, that
--      AnimationTrack is played and the pose layer steps out of the way,
--      because Animator and Motor6D.Transform both write to the same channel.
--   2. Procedural poses from AnimationLibrary. Always available, so the game
--      is fully playable on a fresh place with zero uploaded assets.
--
-- The pose layer crossfades between states, so a jab resolves smoothly back to
-- the stance without a hard snap.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Config = require(Shared.Config)
local Library = require(Shared.AnimationLibrary)
local Poser = require(Shared.Poser)

export type Slot =
	"Idle"
	| "Guard"
	| "Jab"
	| "Cross"
	| "Hook"
	| "Uppercut"
	| "Block"
	| "Dodge"
	| "Hit"
	| "KO"
	| "Victory"
	| "Intro"
	| "Stun"

local PoseAnimator = {}
PoseAnimator.__index = PoseAnimator

export type Rig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	joints: { [string]: Motor6D },
	c0: { [string]: CFrame },
	rigType: "R6" | "R15" | "Boxer",
}

export type State = {
	slot: Slot,
	startedAt: number,
	duration: number,
	attack: string?,
	severity: number,
	dodgeDir: number,
	phaseOffset: number,
}

function PoseAnimator.new(rig: Rig)
	local self = setmetatable({}, PoseAnimator) :: any
	self.rig = rig
	self.blend = 1
	self.current = Library.stance()
	self.target = Library.stance()
	self.slot = "Idle" :: Slot
	self.startedAt = os.clock()
	self.duration = 0
	self.attack = nil :: string?
	self.severity = 1
	self.dodgeDir = 1
	self.time = math.random() * 10
	self.track = nil :: AnimationTrack?
	self.trackSlot = nil :: Slot?
	self.animator = rig.humanoid:FindFirstChildOfClass("Animator")
	self.stepConnection = nil :: RBXScriptConnection?
	self.mixamoBusyUntil = 0
	self.movingSpeed = 0
	self.strafe = 0
	self.enabled = true
	return self
end

-- Reset a rig to its rest pose. Used when a fighter leaves the ring so they do
-- not keep the boxer stance in the lobby.
function PoseAnimator.rest(rig: Rig)
	for name, motor in rig.joints do
		motor.Transform = CFrame.identity
		-- Motor6D.Transform is relative to C0/C1 so identity is the rest pose.
		_ = name
	end
end

function PoseAnimator:setState(slot: Slot, duration: number, opts: { attack: string?, severity: number?, dodgeDir: number? }?)
	if self.slot == slot and slot ~= "Jab" and slot ~= "Cross" and slot ~= "Hook" and slot ~= "Uppercut" then
		return
	end
	self.slot = slot
	self.startedAt = os.clock()
	self.duration = duration
	self.attack = if opts and opts.attack then opts.attack else nil
	self.severity = if opts and opts.severity then opts.severity else 1
	self.dodgeDir = if opts and opts.dodgeDir then opts.dodgeDir else 1
	self.blend = 0
	self.trackSlot = nil

	local animId = (Config.Animations :: any)[slot]
	if animId and animId ~= "" and self.animator then
		self:playMixamo(slot, animId, duration)
	end
end

function PoseAnimator:playMixamo(slot: Slot, animationId: string, duration: number)
	if self.track then
		self.track:Stop(0.08)
		self.track:Destroy()
		self.track = nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = if string.find(animationId, "rbxassetid://") then animationId else `rbxassetid://{animationId}`
	local ok, track = pcall(function()
		return (self.animator :: Animator):LoadAnimation(animation)
	end)
	if not ok or not track then
		return
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0.08, 1, 1)
	self.track = track
	self.trackSlot = slot
	self.mixamoBusyUntil = os.clock() + math.max(duration, 0.15)
end

function PoseAnimator:rootOffsetPose(pose: { [string]: CFrame }, offset: Vector3)
	if offset.Magnitude < 0.0001 then
		return pose
	end
	local out: { [string]: CFrame } = {}
	for joint, cf in pose do
		out[joint] = cf
	end
	local root = out.RootJoint
	if root then
		out.RootJoint = CFrame.new(root.Position + offset) * (root - root.Position)
	else
		out.RootJoint = CFrame.new(offset)
	end
	return out
end

function PoseAnimator:evaluate(now: number): { [string]: CFrame }
	local t = now - self.startedAt
	local phase = if self.duration > 0 then math.clamp(t / self.duration, 0, 1) else 0
	local base = Library.stance()
	local moving = self.movingSpeed > 0.6

	local function locomotionLayer(): { [string]: CFrame }
		if not moving then
			return {}
		end
		local k = math.clamp(self.movingSpeed / Config.Match.walkSpeed, 0, 1.4)
		local walk = Library.locomotion(self.time, self.movingSpeed, self.strafe)
		-- Arms stay in guard while the legs walk: strip the arm swing so the
		-- guard does not pump with the stride.
		walk.LeftShoulder = nil
		walk.RightShoulder = nil
		walk.Waist = CFrame.Angles(0, (walk.Waist and walk.Waist.Y) or 0, 0)
		_ = k
		return walk
	end

	local pose: { [string]: CFrame }
	local slot = self.slot

	if slot == "Idle" then
		pose = Library.stance()
		local breath = Library.idle(self.time, 1)
		pose = Poser.blend(pose, breath, 1)
		pose = Poser.blend(pose, locomotionLayer(), 1)
	elseif slot == "Guard" then
		pose = Poser.blend(Library.stance(), Library.guard(), 1)
		pose = Poser.blend(pose, locomotionLayer(), 1)
	elseif slot == "Block" then
		pose = Poser.blend(Library.stance(), Library.block(), 1)
	elseif slot == "Jab" then
		pose = Poser.blend(Library.stance(), Library.jab(phase), 1)
	elseif slot == "Cross" then
		pose = Poser.blend(Library.stance(), Library.cross(phase), 1)
	elseif slot == "Hook" then
		local side: "Left" | "Right" = if self.attack == "Right" then "Right" else "Left"
		pose = Poser.blend(Library.stance(), Library.hook(phase, side), 1)
	elseif slot == "Uppercut" then
		local side: "Left" | "Right" = if self.attack == "Left" then "Left" else "Right"
		pose = Poser.blend(Library.stance(), Library.uppercut(phase, side), 1)
	elseif slot == "Dodge" then
		pose = Poser.blend(Library.stance(), Library.dodge(phase, self.dodgeDir), 1)
	elseif slot == "Hit" then
		pose = Poser.blend(Library.stance(), Library.hit(phase, self.severity), 1)
	elseif slot == "Stun" then
		local wobble = math.sin(self.time * 14) * 0.12
		pose = Poser.blend(Library.stance(), Library.hit(0.65, 0.5), 1)
		pose = Poser.blend(pose, { Waist = CFrame.Angles(0, wobble, wobble * 0.6), Neck = CFrame.Angles(wobble, 0, 0) }, 1)
		pose = Poser.blend(pose, locomotionLayer(), 0.5)
	elseif slot == "KO" then
		-- Hold the final frame: the KO pose is authored as a full topple.
		pose = Poser.blend(Library.stance(), Library.ko(1, self.dodgeDir), 1)
	elseif slot == "Victory" then
		pose = Poser.blend(Library.stance(), Library.victory(phase), 1)
	elseif slot == "Intro" then
		pose = Poser.blend(Library.stance(), Library.idle(self.time * 1.6, 0.8), 1)
	else
		pose = base
	end

	return pose
end

function PoseAnimator:update(dt: number)
	if not self.enabled then
		return
	end
	self.time += dt

	local now = os.clock()
	local rig = self.rig
	if not rig.model.Parent or not rig.humanoid.Parent then
		if self.stepConnection then
			self.stepConnection:Disconnect()
			self.stepConnection = nil
		end
		return
	end

	-- Mixamo owns the joints while its track runs.
	if self.track and self.trackSlot and now < self.mixamoBusyUntil then
		if self.track.Length > 0 and self.track.Time >= self.track.Length then
			self.mixamoBusyUntil = 0
		else
			return
		end
	end

	local targetPose = self:evaluate(now)

	-- Crossfade toward the target pose. Faster for strikes, slower for idles.
	local blendRate = if self.slot == "Jab" or self.slot == "Cross" or self.slot == "Hook" or self.slot == "Uppercut" then 22
		elseif self.slot == "Hit" or self.slot == "Dodge" then 18
		elseif self.slot == "KO" then 6
		else 10
	self.blend = math.min(1, self.blend + dt * blendRate)
	local a = math.clamp(self.blend, 0, 1)

	local transforms: { [string]: Motor6D } = {}
	for joint, rotation in targetPose do
		local motor = rig.joints[joint]
		local c0 = rig.c0[joint]
		if motor and c0 then
			local blendedRotation = CFrame.identity:Lerp(rotation, a)
			local transform = Poser.jointTransform(c0, blendedRotation)
			local previous = motor.Transform
			motor.Transform = previous:Lerp(transform, math.min(1, dt * 30))
			transforms[joint] = motor
		end
	end

	-- Joints the target pose does not touch relax back to rest.
	for joint, motor in rig.joints do
		if not targetPose[joint] then
			motor.Transform = motor.Transform:Lerp(CFrame.identity, math.min(1, dt * 8))
		end
	end
end

function PoseAnimator:start()
	if self.stepConnection then
		return
	end
	self.stepConnection = RunService.Stepped:Connect(function(_, dt)
		self:update(dt)
	end)
end

function PoseAnimator:stop()
	if self.stepConnection then
		self.stepConnection:Disconnect()
		self.stepConnection = nil
	end
	if self.track then
		self.track:Stop()
		self.track:Destroy()
		self.track = nil
	end
	PoseAnimator.rest(self.rig)
end

function PoseAnimator:destroy()
	self:stop()
	setmetatable(self, nil)
end

return PoseAnimator
