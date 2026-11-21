--!strict
-- Turns torso-space pose rotations into Motor6D.Transform values for a rig.
--
-- Why this exists: R6 and R15 rigs have different joint offsets and different
-- baked rotations inside their C0 values. Writing Motor6D.Transform directly
-- would mean every pose needed a different version per rig. Instead we rotate
-- around the joint's pivot expressed in *torso space*, which is the space the
-- poses in AnimationLibrary are authored in.
--
-- For a Motor6D joint with parts Part0 (parent) and Part1 (limb), Roblox
-- computes:
--     Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
-- The rest pose is Transform = identity. Rotating the limb about the pivot p
-- (in Part0 space) by R gives:
--     Transform = C0:Inverse() * T(p) * R * T(-p) * C0
-- which is exactly what jointTransform() below computes. Every function here is
-- pure so it can be unit tested (see tests/poser.spec.luau).

local Poser = {}

export type JointTransform = CFrame

-- Some rigs (R15 especially) name the parent part differently but the motor
-- name is stable, so poses are keyed by Motor6D name.
export type PoseMap = { [string]: CFrame }

-- Rotate a joint about a pivot in parent-part space.
function Poser.jointTransform(c0: CFrame, rotation: CFrame): CFrame
	local pivot = c0.Position
	local aboutPivot = CFrame.new(pivot) * rotation * CFrame.new(-pivot)
	return c0:Inverse() * aboutPivot * c0
end

-- Compose an additive offset (like a small root bob) with the rotation.
function Poser.jointTransformWithOffset(c0: CFrame, rotation: CFrame, offset: Vector3): CFrame
	local pivot = c0.Position
	local move = CFrame.new(pivot + offset) * rotation * CFrame.new(-pivot)
	return c0:Inverse() * move * c0
end

-- Build the full set of Motor6D.Transform values for a pose.
-- `c0Of` supplies the stored rest C0 for a motor; it is injected so this stays
-- testable without Instances.
function Poser.computeTransforms(
	pose: PoseMap,
	c0Of: (motorName: string) -> CFrame?
): { [string]: CFrame }
	local result: { [string]: CFrame } = {}
	for motorName, rotation in pose do
		local c0 = c0Of(motorName)
		if c0 then
			result[motorName] = Poser.jointTransform(c0, rotation)
		end
	end
	return result
end

-- Blend two poses. Joints present in only one pose are blended against the
-- identity, so a guard pose can fade into a jab cleanly.
function Poser.blend(a: PoseMap, b: PoseMap, t: number): PoseMap
	local alpha = math.clamp(t, 0, 1)
	local out: PoseMap = {}
	for name, cf in a do
		out[name] = cf:Lerp(b[name] or CFrame.identity, alpha)
	end
	for name, cf in b do
		if not out[name] then
			out[name] = CFrame.identity:Lerp(cf, alpha)
		end
	end
	return out
end

-- Boxer rigs the game builds itself. Standard names so Humanoid and the
-- Animator both understand them, with extra segments for elbows and knees.
Poser.BOXER_JOINTS = {
	"RootJoint",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

-- Maps pose joint names to the Motor6D names used by each rig family.
local R6_MOTORS: { [string]: string } = {
	RootJoint = "RootJoint",
	Waist = "RootJoint", -- R6 has no waist; torso rotation rides the root.
	Neck = "Neck",
	LeftShoulder = "Left Shoulder",
	RightShoulder = "Right Shoulder",
	LeftHip = "Left Hip",
	RightHip = "Right Hip",
}

function Poser.motorNameFor(joint: string, rigType: "R6" | "R15" | "Boxer"): string?
	if rigType == "Boxer" then
		return if table.find(Poser.BOXER_JOINTS, joint) then joint else nil
	end
	if rigType == "R15" then
		return joint
	end
	return R6_MOTORS[joint]
end

-- Detect which family a humanoid rig belongs to.
function Poser.detectRigType(model: Model): "R6" | "R15" | "Boxer"
	if model:GetAttribute("BoxerRig") == true then
		return "Boxer"
	end
	local torso = model:FindFirstChild("UpperTorso")
	if torso then
		return "R15"
	end
	return "R6"
end

function Poser.rigTypeNames(rigType: "R6" | "R15" | "Boxer"): { [string]: string }
	local map: { [string]: string } = {}
	if rigType == "Boxer" then
		for _, joint in Poser.BOXER_JOINTS do
			map[joint] = joint
		end
	elseif rigType == "R15" then
		for _, joint in Poser.BOXER_JOINTS do
			map[joint] = joint
		end
	else
		for joint, motor in R6_MOTORS do
			map[joint] = motor
		end
	end
	return map
end

return Poser
