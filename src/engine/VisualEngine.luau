--!strict
local TweenService = game:GetService("TweenService")

local VisualEngine = {}

-- Safely tweens an entire model by anchoring/welding to a PrimaryPart
function VisualEngine.tweenModel(model: Model, tweenInfo: TweenInfo, properties: {[string]: any}): RBXScriptConnection?
	if not model.PrimaryPart then
		warn("[VisualEngine] Model lacks a PrimaryPart. Cannot tween.")
		return nil
	end

	local primary = model.PrimaryPart
	local wasAnchored = primary.Anchored
	primary.Anchored = true -- Prevent physics explosions during tween

	local tween = TweenService:Create(primary, tweenInfo, properties)
	
	local connection = tween.Completed:Connect(function()
		primary.Anchored = wasAnchored -- Restore original state
	end)
	
	tween:Play()
	return connection
end

-- Smooth audio crossfading (prevents audio clipping/popping)
function VisualEngine.crossfadeSounds(soundOut: Sound, soundIn: Sound, duration: number)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	
	local fadeOut = TweenService:Create(soundOut, tweenInfo, { Volume = 0 })
	local fadeIn = TweenService:Create(soundIn, tweenInfo, { Volume = soundIn.Volume }) -- Assumes target volume is set
	
	fadeOut:Play()
	fadeIn:Play()
	
	fadeOut.Completed:Connect(function()
		soundOut:Stop()
	end)
end

return VisualEngine