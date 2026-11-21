diff --git a/src/server/init.server.luau b/src/server/init.server.luau
new file mode 100644
index 0000000..a8ae5f8
--- /dev/null
+++ b/src/server/init.server.luau
@@ -0,0 +1,22 @@
+--!strict
+-- Server entry point.
+
+local Players = game:GetService("Players")
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+
+local Shared = ReplicatedStorage:WaitForChild("Shared")
+local Net = require(Shared.Net)
+local Match = require(script.lib.Match)
+
+Net.ensureCreated()
+Match.start()
+
+-- Lobby bookkeeping: players stand outside the ring until they queue.
+Players.PlayerAdded:Connect(function(player: Player)
+	player.CharacterAdded:Connect(function(character: Model)
+		local humanoid = character:WaitForChild("Humanoid", 8)
+		if humanoid and humanoid:IsA("Humanoid") then
+			humanoid.WalkSpeed = 16
+		end
+	end)
+end)
