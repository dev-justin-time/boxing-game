--!strict
local Players = game:GetService("Players")

local TeleportEngine = {}

export type PortalConfig = {
	entryPart: BasePart,
	exitPart: BasePart,
	maintainVelocity: boolean?,
}

function TeleportEngine.registerPortal(config: PortalConfig)
	local debounce = false
	
	config.entryPart.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = Players:GetPlayerFromCharacter(character)
		
		if player and not debounce then
			debounce = true
			
			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local exitCFrame = config.exitPart.CFrame
				local relativeOffset = config.entryPart.CFrame:ToObjectSpace(hrp.CFrame)
				
				-- Calculate new CFrame preserving relative orientation and position
				local newCFrame = exitCFrame * relativeOffset
				
				if config.maintainVelocity then
					-- Vector rotation to match exit orientation
					local velocity = hrp.AssemblyLinearVelocity
					local rotation = exitCFrame.Rotation * config.entryPart.CFrame.Rotation:Inverse()
					hrp.AssemblyLinearVelocity = rotation * velocity
				end
				
				hrp.CFrame = newCFrame
			end
			
			task.wait(0.5) -- Prevent immediate re-trigger
			debounce = false
		end
	end)
end

return TeleportEngine