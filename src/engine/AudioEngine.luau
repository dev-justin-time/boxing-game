--!strict
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AudioEngine = {
	SoundPool = {} :: {[string]: Sound},
	MaxPoolSize = 10
}

-- Pre-warm sounds to prevent runtime instantiation lag
function AudioEngine.preloadSound(soundId: string, name: string): Sound
	if not AudioEngine.SoundPool[name] then
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Parent = Workspace
		sound:PreloadAsync()
		AudioEngine.SoundPool[name] = sound
	end
	return AudioEngine.SoundPool[name]
end

-- Smooth crossfade between two named sounds
function AudioEngine.crossfade(outName: string, inName: string, duration: number)
	local soundOut = AudioEngine.SoundPool[outName]
	local soundIn = AudioEngine.SoundPool[inName]
	
	if not soundOut or not soundIn then return end
	
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local fadeOut = TweenService:Create(soundOut, tweenInfo, { Volume = 0 })
	local fadeIn = TweenService:Create(soundIn, tweenInfo, { Volume = soundIn.Volume })
	
	fadeOut:Play()
	fadeIn:Play()
	
	fadeOut.Completed:Connect(function()
		soundOut:Stop()
	end)
end

return AudioEngine