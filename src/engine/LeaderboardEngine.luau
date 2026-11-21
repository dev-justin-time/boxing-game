--!strict
local DataStoreService = game:GetService("DataStoreService")

local LeaderboardEngine = {
	Cache = {} :: {[string]: {[string]: number}},
	Store = DataStoreService:GetOrderedDataStore("GlobalLeaderboard_v1")
}

-- Update local cache immediately, schedule async save
function LeaderboardEngine.incrementStat(playerId: string, statName: string, amount: number)
	if not LeaderboardEngine.Cache[statName] then
		LeaderboardEngine.Cache[statName] = {}
	end
	
	local current = LeaderboardEngine.Cache[statName][playerId] or 0
	LeaderboardEngine.Cache[statName][playerId] = current + amount
	
	-- Async save (fire and forget, with retry handled by DataEngine if needed)
	task.spawn(function()
		local success, err = pcall(function()
			LeaderboardEngine.Store:UpdateAsync(playerId .. "_" .. statName, function(oldValue)
				return (oldValue or 0) + amount
			end)
		end)
		if not success then warn(`[Leaderboard] Sync failed: {err}`) end
	end)
end

function LeaderboardEngine.getTopPlayers(statName: string, pageSize: number): {any}
	local pages = LeaderboardEngine.Store:GetSortedAsync(false, pageSize)
	local topPlayers = pages:GetCurrentPage()
	return topPlayers
end

return LeaderboardEngine