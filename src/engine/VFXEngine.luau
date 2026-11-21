--!strict
local VFXEngine = {}
local pools: {[string]: {Instance}} = {}

local function getFromPool(templateName: string, template: Instance): Instance
	if not pools[templateName] then
		pools[templateName] = {}
	end
	
	local pool = pools[templateName]
	local instance = table.remove(pool)
	
	if not instance then
		instance = template:Clone()
	end
	
	return instance
end

local function returnToPool(templateName: string, instance: Instance)
	if not pools[templateName] then
		pools[templateName] = {}
	end
	
	instance.Parent = nil
	table.insert(pools[templateName], instance)
end

function VFXEngine.playVFX(vfxTemplate: Model, cframe: CFrame, duration: number?)
	local vfx = getFromPool(vfxTemplate.Name, vfxTemplate)
	vfx:PivotTo(cframe)
	vfx.Parent = workspace
	
	-- Play all sounds and particle emitters inside the pooled model
	for _, child in ipairs(vfx:GetDescendants()) do
		if child:IsA("Sound") then
			child:Play()
		elseif child:IsA("ParticleEmitter") then
			child:Emit(child:GetAttribute("EmitCount") or 10)
		end
	end
	
	-- Return to pool after duration instead of destroying
	task.delay(duration or 3, function()
		if vfx.Parent then
			returnToPool(vfxTemplate.Name, vfx)
		end
	end)
end

function VFXEngine.crossfadeSounds(soundA: Sound, soundB: Sound, duration: number)
	task.spawn(function()
		soundB.Volume = 0
		soundB:Play()
		
		local start = os.clock()
		while os.clock() - start < duration do
			local alpha = (os.clock() - start) / duration
			soundA.Volume = math.clamp(1 - alpha, 0, 1)
			soundB.Volume = math.clamp(alpha, 0, 1)
			task.wait()
		end
		
		soundA:Stop()
		soundA.Volume = 1
	end)
end

return VFXEngine