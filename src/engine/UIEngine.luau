--!strict
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIEngine = {
	ActiveScreen = nil,
	Screens = {} :: {[string]: ScreenGui}
}

-- Register a screen for managed toggling
function UIEngine.registerScreen(name: string, screenGui: ScreenGui)
	screenGui.Enabled = false
	UIEngine.Screens[name] = screenGui
end

-- Safely transition between screens
function UIEngine.showScreen(name: string)
	local targetScreen = UIEngine.Screens[name]
	if not targetScreen then
		warn(`[UIEngine] Screen "{name}" not registered.`)
		return
	end

	-- Hide current screen
	if UIEngine.ActiveScreen then
		UIEngine.ActiveScreen.Enabled = false
	end

	-- Show new screen
	targetScreen.Enabled = true
	UIEngine.ActiveScreen = targetScreen
end

-- High-value utility: Format seconds into HH:MM:SS (omits leading zeros)
function UIEngine.formatTime(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	elseif m > 0 then
		return string.format("%d:%02d", m, s)
	else
		return string.format("%d", s)
	end
end

return UIEngine