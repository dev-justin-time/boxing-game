--!strict
local Players = game:GetService("Players")

local CharacterEngine = {}

-- Waits for all critical components to exist
function CharacterEngine.waitForFullCharacter(player: Player): Model
	local character = player.Character or player.CharacterAdded:Wait()
	
	-- Wait for PrimaryPart (usually HumanoidRootPart)
	while not character.PrimaryPart do
		character.AncestryChanged:Wait()
	end
	
	-- Wait for Humanoid
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn(`[CharacterEngine] Humanoid not found for {player.Name}`)
	end
	
	return character
end

-- Safe player iteration (handles players already in game + new joins)
function CharacterEngine.onPlayerReady(callback: (Player, Model) -> ())
	local function onCharacterAdded(player: Player)
		local character = CharacterEngine.waitForFullCharacter(player)
		task.spawn(callback, player, character)
	end

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			onCharacterAdded(player)
		end
	end
	
	-- Handle future players
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacterAdded(player)
		end)
	end)
end

return CharacterEngine