--!strict
local Players = game:GetService("Players")

export type AnimationTrackMap = {[string]: AnimationTrack}

local AnimationEngine = {}

-- Safely load and play an animation, stopping conflicting tracks
function AnimationEngine.playAnimation(humanoid: Humanoid, animationId: string, trackName: string, priority: Enum.AnimationPriority): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end

	local existingTrack = animator:GetPlayingAnimationTracks()
	for _, track in existingTrack do
		if track.Name == trackName and track.IsPlaying then
			return track -- Already playing
		end
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	
	local track = animator:LoadAnimation(animation)
	track.Name = trackName
	track.Priority = priority
	track:Play()
	
	return track
end

function AnimationEngine.stopAnimation(humanoid: Humanoid, trackName: string)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Name == trackName then
			track:Stop(0.1) -- Smooth fade out
			track:Destroy()
		end
	end
end

return AnimationEngine