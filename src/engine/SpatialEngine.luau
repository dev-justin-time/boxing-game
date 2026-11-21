--!strict
local Workspace = game:GetService("Workspace")

export type RaycastParamsConfig = {
	FilterDescendantsInstances: {Instance}?,
	FilterType: Enum.RaycastFilterType?,
	CollisionGroup: string?,
	IgnoreWater: boolean?
}

local SpatialEngine = {}

-- Optimized, reusable RaycastParams cache
local defaultParams = RaycastParams.new()
defaultParams.FilterType = Enum.RaycastFilterType.Exclude
defaultParams.IgnoreWater = true

function SpatialEngine.castRay(
	origin: Vector3, 
	direction: Vector3, 
	config: RaycastParamsConfig?
): RaycastResult?
	local params = defaultParams
	if config then
		if config.FilterDescendantsInstances then
			params.FilterDescendantsInstances = config.FilterDescendantsInstances
		end
		if config.FilterType then
			params.FilterType = config.FilterType
		end
		if config.CollisionGroup then
			params.CollisionGroup = config.CollisionGroup
		end
		if config.IgnoreWater ~= nil then
			params.IgnoreWater = config.IgnoreWater
		end
	end
	
	return Workspace:Raycast(origin, direction, params)
end

-- High-value: Attribute-based searching (faster and safer than string matching)
function SpatialEngine.findFirstChildWithAttribute(parent: Instance, attrName: string, attrValue: any): Instance?
	for _, child in ipairs(parent:GetChildren()) do
		local value = child:GetAttribute(attrName)
		if value == attrValue then
			return child
		end
	end
	return nil
end

return SpatialEngine