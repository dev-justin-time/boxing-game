--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- High-Performance Signal (replaces BindableEvent)
export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: Signal, ...any) -> (),
	Destroy: (self: Signal) -> ()
}

local function createSignal(): Signal
	local listeners = {}
	local signal = {}
	
	function signal:Connect(callback: (...any) -> ()): RBXScriptConnection
		table.insert(listeners, callback)
		return {
			Connected = true,
			Disconnect = function(self)
				self.Connected = false
				for i, cb in ipairs(listeners) do
					if cb == callback then
						table.remove(listeners, i)
						break
					end
				end
			end
		}
	end
	
	function signal:Fire(...args: any)
		for _, callback in ipairs(listeners) do
			task.spawn(callback, ...)
		end
	end
	
	function signal:Destroy()
		table.clear(listeners)
	end
	
	return signal :: any
end

-- Secure Network Handler
local NetworkEngine = {
	Remotes = ReplicatedStorage:WaitForChild("Remotes"),
	Signals = {}
}

function NetworkEngine.createRemoteEvent(name: string)
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = NetworkEngine.Remotes
	NetworkEngine.Signals[name] = createSignal()
	
	event.OnServerEvent:Connect(function(player: Player, ...args: any)
		-- High-value: Add validation/sanitization here before firing
		NetworkEngine.Signals[name]:Fire(player, ...)
	end)
	
	return event
end

return NetworkEngine