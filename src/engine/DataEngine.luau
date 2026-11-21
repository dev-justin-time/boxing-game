--!strict
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

export type PlayerData = {
	Coins: number,
	Level: number,
	Inventory: {string}
}

local DEFAULT_DATA: PlayerData = { Coins = 0, Level = 1, Inventory = {} }
local STORE = DataStoreService:GetDataStore("PlayerData_v1")

local DataEngine = {}

-- Exponential backoff retry wrapper (from Roblox samples)
local function retryAsync(func: () -> (any), maxAttempts: number, initialDelay: number): (boolean, any)
	local delayTime = initialDelay
	for attempt = 1, maxAttempts do
		local success, result = pcall(func)
		if success then return true, result end
		if attempt == maxAttempts then return false, result end
		task.wait(delayTime)
		delayTime *= 2 -- Exponential backoff
	end
	return false, "Max attempts reached"
end

function DataEngine.loadPlayerData(player: Player): PlayerData
	local userId = "Player_" .. player.UserId
	local success, data = retryAsync(function()
		return STORE:GetAsync(userId)
	end, 5, 2)
	
	if success and type(data) == "table" then
		return data :: PlayerData
	end
	warn(`[DataEngine] Failed to load data for {player.Name}. Issuing default.`)
	return DEFAULT_DATA
end

function DataEngine.savePlayerData(player: Player, data: PlayerData): boolean
	local userId = "Player_" .. player.UserId
	local success, err = retryAsync(function()
		return STORE:UpdateAsync(userId, function(oldData)
			return data -- Session locking should be added here for production
		end)
	end, 5, 2)
	
	if not success then
		warn(`[DataEngine] Failed to save data for {player.Name}: {err}`)
	end
	return success
end

return DataEngine