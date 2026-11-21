--!strict
local PathfindingService = game:GetService("PathfindingService")

local NavigationEngine = {}

export type PathResult = {
	Success: boolean,
	Waypoints: {PathWaypoint}?,
	Error: string?
}

function NavigationEngine.computePath(startPos: Vector3, endPos: Vector3, agentParams: PathfindingAgentParameters?): PathResult
	local path = PathfindingService:CreatePath(agentParams)
	local success, err = pcall(function()
		path:ComputeAsync(startPos, endPos)
	end)
	
	if success and path.Status == Enum.PathStatus.Success then
		return { Success = true, Waypoints = path:GetWaypoints() }
	else
		return { Success = false, Error = tostring(err or path.Status) }
	end
end

-- Fallback: Direct vector following with constraints (from "Model Following a Player" sample)
function NavigationEngine.attachFollower(model: Model, targetAttachment: Attachment, maxDistance: number)
	if not model.PrimaryPart then return end
	
	local alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = model.PrimaryPart:FindFirstChildWhichIsA("Attachment") or Instance.new("Attachment", model.PrimaryPart)
	alignPos.Attachment1 = targetAttachment
	alignPos.MaxForce = 10000
	alignPos.Responsiveness = 25
	alignPos.Parent = model.PrimaryPart
	
	local alignOrient = Instance.new("AlignOrientation")
	alignOrient.Attachment0 = alignPos.Attachment0
	alignOrient.Attachment1 = targetAttachment
	alignOrient.Parent = model.PrimaryPart
end

return NavigationEngine