diff --git a/src/server/Engine/ObjectFactory.luau b/src/server/Engine/ObjectFactory.luau
index 09ba0e9..51718f4 100644
--- a/src/server/Engine/ObjectFactory.luau
+++ b/src/server/Engine/ObjectFactory.luau
@@ -39,10 +39,15 @@ function ObjectFactory.createFollower(target: Model, follower: BasePart)
 	alignPosition.Responsiveness = 100
 	alignPosition.Parent = follower
 	
-	-- Auto-cleanup when target dies or is removed
-	local conn = game:GetService("RunService").Heartbeat:Connect(function()
+	-- Auto-cleanup when the target dies or is removed. The connection variable
+	-- has to exist before the callback that closes over it.
+	local conn: RBXScriptConnection? = nil
+	conn = game:GetService("RunService").Heartbeat:Connect(function()
 		if not target.Parent or not target:IsDescendantOf(workspace) then
-			conn:Disconnect()
+			if conn then
+				conn:Disconnect()
+				conn = nil
+			end
 			follower:Destroy()
 		end
 	end)
