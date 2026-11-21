--!strict
local ObjectFactory = {}

export type InstanceConfig = {
	className: string,
	properties: {[string]: any}?,
	children: {InstanceConfig}?,
}

function ObjectFactory.build(config: InstanceConfig): Instance
	local instance = Instance.new(config.className)
	
	if config.properties then
		for prop, value in pairs(config.properties) do
			(instance :: any)[prop] = value
		end
	end
	
	if config.children then
		for _, childConfig in ipairs(config.children) do
			local child = ObjectFactory.build(childConfig)
			child.Parent = instance
		end
	end
	
	return instance
end

-- High-value constraint follower
function ObjectFactory.createFollower(target: Model, follower: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Parent = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	
	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = attachment
	alignPosition.Attachment1 = follower:FindFirstChildWhichIsA("Attachment") or Instance.new("Attachment", follower)
	alignPosition.MaxForce = math.huge
	alignPosition.MaxVelocity = 50
	alignPosition.Responsiveness = 100
	alignPosition.Parent = follower
	
	-- Auto-cleanup when target dies or is removed
	local conn = game:GetService("RunService").Heartbeat:Connect(function()
		if not target.Parent or not target:IsDescendantOf(workspace) then
			conn:Disconnect()
			follower:Destroy()
		end
	end)
	
	return attachment
end

return ObjectFactory