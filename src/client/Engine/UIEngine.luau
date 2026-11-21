diff --git a/src/client/Engine/UIEngine.luau b/src/client/Engine/UIEngine.luau
index ee25930..d13cec8 100644
--- a/src/client/Engine/UIEngine.luau
+++ b/src/client/Engine/UIEngine.luau
@@ -1,11 +1,7 @@
 --!strict
-local Players = game:GetService("Players")
-local player = Players.LocalPlayer
-local playerGui = player:WaitForChild("PlayerGui")
-
 local UIEngine = {
-	ActiveScreen = nil,
-	Screens = {} :: {[string]: ScreenGui}
+	ActiveScreen = nil :: ScreenGui?,
+	Screens = {} :: {[string]: ScreenGui},
 }
 
 -- Register a screen for managed toggling
