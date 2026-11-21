--!strict
local DataStoreService = game:GetService("DataStoreService")

local ConfigEngine = {
	ActiveConfig = {} :: {[string]: any},
	Store = DataStoreService:GetGlobalDataStore("LiveConfig_v1")
}

-- Default fallback values
local DEFAULTS = {
	MaxPlayers = 50,
	DayNightSpeed = 120,
	FeatureXEnabled = true
}

function ConfigEngine.init()
	ConfigEngine.ActiveConfig = table.clone(DEFAULTS)
	
	-- Poll for updates every 60 seconds
	task.spawn(function()
		while true do
			task.wait(60)
			local success, newConfig = pcall(function()
				return ConfigEngine.Store:GetAsync("GlobalSettings")
			end)
			
			if success and type(newConfig) == "table" then
				-- Merge new config with defaults
				for key, value in pairs(DEFAULTS) do
					ConfigEngine.ActiveConfig[key] = newConfig[key] ~= nil and newConfig[key] or value
				end
				print("[ConfigEngine] Live config updated.")
			end
		end
	end)
end

function ConfigEngine.get(key: string): any
	return ConfigEngine.ActiveConfig[key]
end

return ConfigEngine