--!strict
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

export type CameraMode = "FirstPerson" | "ThirdPerson" | "Isometric" | "Cinematic"

local CameraEngine = {}
local CurrentCamera = Workspace.CurrentCamera
local activeConnections: {[string]: RBXScriptConnection} = {}

function CameraEngine.setMode(mode: CameraMode, target: Model?, config: any)
	-- 1. Cleanup previous mode to prevent memory leaks
	for _, conn in pairs(activeConnections) do
		conn:Disconnect()
	end
	table.clear(activeConnections)
	
	if mode == "Isometric" then
		CurrentCamera.CameraType = Enum.CameraType.Scriptable
		local distance = config.distance or 50
		local angle = config.angle or math.rad(45)
		
		activeConnections.isometric = RunService.RenderStepped:Connect(function()
			if target and target.PrimaryPart then
				local pos = target.PrimaryPart.Position
				local offset = Vector3.new(
					math.sin(angle) * distance,
					math.cos(math.rad(45)) * distance,
					math.cos(angle) * distance
				)
				-- CFrame.lookAt prevents gimbal lock issues common in basic Euler math
				CurrentCamera.CFrame = CFrame.lookAt(pos + offset, pos)
			end
		end)
	elseif mode == "ThirdPerson" then
		CurrentCamera.CameraType = Enum.CameraType.Custom
	end
end

function CameraEngine.reset()
	for _, conn in pairs(activeConnections) do
		conn:Disconnect()
	end
	table.clear(activeConnections)
	CurrentCamera.CameraType = Enum.CameraType.Custom
	CurrentCamera.CameraSubject = game.Players.LocalPlayer.Character
end

return CameraEngine