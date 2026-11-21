diff --git a/src/client/Engine/AnimationEngine.luau b/src/client/Engine/AnimationEngine.luau
index 0bc1dfc..faa3d4c 100644
--- a/src/client/Engine/AnimationEngine.luau
+++ b/src/client/Engine/AnimationEngine.luau
@@ -1,5 +1,4 @@
 --!strict
-local Players = game:GetService("Players")
 
 export type AnimationTrackMap = {[string]: AnimationTrack}
 
