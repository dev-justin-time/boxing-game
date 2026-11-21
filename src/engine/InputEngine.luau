--!strict
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local InputEngine = {}

export type InputAction = {
	name: string,
	description: string,
	keyboardKey: Enum.KeyCode,
	gamepadKey: Enum.KeyCode,
	mobileIcon: string,
	callback: (actionName: string, inputState: Enum.UserInputState, inputObject: InputObject) -> ()
}

function InputEngine.registerAction(action: InputAction)
	local function getPrompt()
		if UserInputService.KeyboardEnabled then
			return action.keyboardKey.Name
		elseif UserInputService.GamepadEnabled then
			return action.gamepadKey.Name
		else
			return action.mobileIcon
		end
	end

	ContextActionService:BindAction(
		action.name,
		action.callback,
		true, -- Create mobile button
		action.keyboardKey,
		action.gamepadKey
	)
	
	-- Dynamically update button text based on device
	ContextActionService:SetTitle(action.name, action.description .. " [" .. getPrompt() .. "]")
end

function InputEngine.unregisterAction(name: string)
	ContextActionService:UnbindAction(name)
end

return InputEngine