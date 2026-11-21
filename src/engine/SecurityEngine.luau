--!strict
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local SecurityEngine = {
	BannedUsers = {} :: {[number]: boolean},
	AllowedRegions = {"US", "CA", "GB"} -- Example geofencing whitelist
}

-- Server-side sanity check for movement (basic anti-speed/teleport)
function SecurityEngine.validateMovement(player: Player, expectedPosition: Vector3, actualPosition: Vector3, maxDelta: number): boolean
	local distance = (expectedPosition - actualPosition).Magnitude
	if distance > maxDelta then
		warn(`[Security] Suspicious movement detected for {player.Name}. Delta: {distance}`)
		-- Optional: Kick or teleport back
		-- player:Kick("Suspicious movement")
		return false
	end
	return true
end

-- Geofencing check (requires a backend service or predefined allowed list)
-- Note: Roblox doesn't expose player IP natively to scripts, so this is typically 
-- handled via a ProxyService or pre-validated session token from your backend.
function SecurityEngine.isRegionAllowed(sessionToken: string): boolean
	-- Placeholder for actual backend validation
	local isAllowed = true 
	return isAllowed
end

-- Secure moderation actions (Server-authoritative)
function SecurityEngine.banUser(targetPlayer: Player, adminPlayer: Player, durationSeconds: number?)
	-- Verify admin permissions here (e.g., check Group Rank)
	
	SecurityEngine.BannedUsers[targetPlayer.UserId] = true
	targetPlayer:Kick("You have been banned from this experience.")
	
	-- In a real system, you would save this to a DataStore with an expiration timestamp
end

return SecurityEngine