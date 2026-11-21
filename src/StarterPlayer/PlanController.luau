--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlanEngine = require(ReplicatedStorage.PlanSystem.PlanEngine)
local PlanRemote = ReplicatedStorage.PlanSystem.PlanRemote

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- GUI References
local gui = player:WaitForChild("PlayerGui"):WaitForChild("PlanScreenGui")
local canvas = gui:WaitForChild("GridCanvas")
local previewLayer = canvas:WaitForChild("PreviewLayer")
local placedLayer = canvas:WaitForChild("PlacedItems")

-- Configuration
local CELL_SIZE_PX = 40 -- Pixels per grid cell in the UI
local GRID_WIDTH = 20   -- Cells
local GRID_HEIGHT = 20  -- Cells

-- State
local currentTool: string? = nil
local isDragging = false
local dragStartCell = {X = 0, Y = 0}
local previewFrame: Frame? = nil

-- Camera Setup (Top-Down Orthographic-like)
local function setupCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	-- Position camera high up, looking straight down at the grid center
	local center = Vector3.new(GRID_WIDTH * 2, 0, GRID_HEIGHT * 2)
	camera.CFrame = CFrame.new(center.X, 80, center.Z) * CFrame.Angles(math.rad(-90), 0, 0)
	camera.FieldOfView = 30
end

local function resetCamera()
	camera.CameraType = Enum.CameraType.Custom
end

-- Helper: Screen Pixel to Grid Cell
local function getCellFromMouse(mouseX: number, mouseY: number): (number, number)
	local relativeX = mouseX - canvas.AbsolutePosition.X
	local relativeY = mouseY - canvas.AbsolutePosition.Y
	
	local cellX = math.floor(relativeX / CELL_SIZE_PX)
	local cellY = math.floor(relativeY / CELL_SIZE_PX)
	
	-- Clamp to grid bounds
	cellX = math.clamp(cellX, 0, GRID_WIDTH - 1)
	cellY = math.clamp(cellY, 0, GRID_HEIGHT - 1)
	
	return cellX, cellY
end

-- Helper: Update the visual preview frame during drag
local function updatePreview(cellX: number, cellY: number)
	if not currentTool or not isDragging then return end
	
	local dx = cellX - dragStartCell.X
	local dy = cellY - dragStartCell.Y
	
	-- Determine if drawing horizontally or vertically based on dominant axis
	local isHorizontal = math.abs(dx) >= math.abs(dy)
	local length = (isHorizontal and math.abs(dx) or math.abs(dy)) + 1
	local rotation = isHorizontal and 0 or 90
	
	local startX = isHorizontal and math.min(dragStartCell.X, cellX) or dragStartCell.X
	local startY = isHorizontal and dragStartCell.Y or math.min(dragStartCell.Y, cellY)
	
	if not previewFrame then
		previewFrame = Instance.new("Frame")
		previewFrame.BackgroundTransparency = 0.5
		previewFrame.BorderSizePixel = 1
		previewFrame.Parent = previewLayer
	end
	
	previewFrame.Position = UDim2.new(0, startX * CELL_SIZE_PX, 0, startY * CELL_SIZE_PX)
	
	if currentTool == "Floor" then
		previewFrame.Size = UDim2.new(0, (math.abs(dx) + 1) * CELL_SIZE_PX, 0, (math.abs(dy) + 1) * CELL_SIZE_PX)
		previewFrame.BackgroundColor3 = Color3.fromRGB(150, 100, 50)
	else
		previewFrame.Size = UDim2.new(
			0, (isHorizontal and length or 1) * CELL_SIZE_PX,
			0, (isHorizontal and 1 or length) * CELL_SIZE_PX
		)
		previewFrame.BackgroundColor3 = currentTool == "Wall" and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(139, 69, 19)
	end
end

local function clearPreview()
	if previewFrame then
		previewFrame:Destroy()
		previewFrame = nil
	end
end

-- Render committed items from PlanEngine
local function renderPlan()
	-- Clear existing
	for _, child in ipairs(placedLayer:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	
	local data = PlanEngine.getPlanData()
	for _, item in ipairs(data) do
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 1
		frame.Position = UDim2.new(0, item.X * CELL_SIZE_PX, 0, item.Y * CELL_SIZE_PX)
		
		if item.Type == "Floor" then
			frame.Size = UDim2.new(0, (item.Width or 1) * CELL_SIZE_PX, 0, (item.Height or 1) * CELL_SIZE_PX)
			frame.BackgroundColor3 = Color3.fromRGB(150, 100, 50)
		else
			local length = item.Length or 1
			frame.Size = UDim2.new(
				0, (item.Rotation == 0 and length or 1) * CELL_SIZE_PX,
				0, (item.Rotation == 0 and 1 or length) * CELL_SIZE_PX
			)
			frame.BackgroundColor3 = item.Type == "Wall" and Color3.fromRGB(200, 200, 200) or Color3.fromRGB(139, 69, 19)
		end
		
		frame.Parent = placedLayer
	end
end

-- Input Handling
canvas.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and currentTool then
		isDragging = true
		dragStartCell.X, dragStartCell.Y = getCellFromMouse(input.Position.X, input.Position.Y)
		updatePreview(dragStartCell.X, dragStartCell.Y)
	end
end)

canvas.InputChanged:Connect(function(input: InputObject)
	if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local cellX, cellY = getCellFromMouse(input.Position.X, input.Position.Y)
		updatePreview(cellX, cellY)
	end
end)

canvas.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and isDragging then
		isDragging = false
		local cellX, cellY = getCellFromMouse(input.Position.X, input.Position.Y)
		
		local dx = cellX - dragStartCell.X
		local dy = cellY - dragStartCell.Y
		local isHorizontal = math.abs(dx) >= math.abs(dy)
		local length = (isHorizontal and math.abs(dx) or math.abs(dy)) + 1
		local startX = isHorizontal and math.min(dragStartCell.X, cellX) or dragStartCell.X
		local startY = isHorizontal and dragStartCell.Y or math.min(dragStartCell.Y, cellY)
		
		-- Only commit if length > 0
		if length > 0 then
			local newItem: PlanEngine.PlanItem = {
				Type = currentTool,
				X = startX,
				Y = startY,
				Rotation = isHorizontal and 0 or 90,
			}
			
			if currentTool == "Floor" then
				newItem.Width = math.abs(dx) + 1
				newItem.Height = math.abs(dy) + 1
			else
				newItem.Length = length
			end
			
			PlanEngine.addItem(newItem)
			renderPlan()
		end
		
		clearPreview()
	end
end)

-- Toolbar Connections
gui.Toolbar.ToolWall.MouseButton1Click:Connect(function() currentTool = "Wall" end)
gui.Toolbar.ToolFloor.MouseButton1Click:Connect(function() currentTool = "Floor" end)
gui.Toolbar.ToolDoor.MouseButton1Click:Connect(function() currentTool = "Door" end)

gui.Toolbar.BtnUndo.MouseButton1Click:Connect(function()
	if PlanEngine.undo() then renderPlan() end
end)

gui.Toolbar.BtnRedo.MouseButton1Click:Connect(function()
	if PlanEngine.redo() then renderPlan() end
end)

gui.Toolbar.BtnClear.MouseButton1Click:Connect(function()
	PlanEngine.clear()
	renderPlan()
end)

gui.Toolbar.BtnBuild3D.MouseButton1Click:Connect(function()
	local instructions = PlanEngine.generate3DInstructions()
	
	-- Send to server for validation and instantiation
	local success, result = PlanRemote:InvokeServer(instructions)
	
	if success then
		print("House constructed successfully!")
		resetCamera()
		gui.Enabled = false
	else
		warn("Construction failed: " .. tostring(result))
	end
end)

-- Activation function (call this when entering build mode)
function PlanController.activate()
	gui.Enabled = true
	setupCamera()
	renderPlan()
end

-- Deactivation function
function PlanController.deactivate()
	gui.Enabled = false
	resetCamera()
	clearPreview()
end

return PlanController

-- Add these to the Toolbar in the GUI setup:
-- 🔘 BtnSave (TextButton, "Save Plan")
-- 🔘 BtnLoad (TextButton, "Load Plan")
-- 🔘 BtnClear3D (TextButton, "Clear 3D Build")

-- Add these connections in PlanController.luau:

gui.Toolbar.BtnSave.MouseButton1Click:Connect(function()
	local instructions = PlanEngine.getPlanData()
	local success, message = PlanRemote:InvokeServer("BUILD", instructions)
	if success then
		print("✅", message)
		-- Optional: Show a success toast GUI
	else
		warn("❌", message)
	end
end)

gui.Toolbar.BtnLoad.MouseButton1Click:Connect(function()
	local success, dataOrErr = PlanRemote:InvokeServer("LOAD", nil)
	if success then
		PlanEngine.loadPlanData(dataOrErr)
		renderPlan() -- Re-draw the 2D grid
		print("✅ Plan loaded successfully!")
	else
		warn("❌ Failed to load:", dataOrErr)
	end
end)

gui.Toolbar.BtnClear3D.MouseButton1Click:Connect(function()
	local success, message = PlanRemote:InvokeServer("CLEAR", nil)
	if success then
		PlanEngine.clear()
		renderPlan()
		print("✅", message)
	else
		warn("❌", message)
	end
end)