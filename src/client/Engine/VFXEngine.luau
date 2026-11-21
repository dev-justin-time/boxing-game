diff --git a/src/client/Engine/VFXEngine.luau b/src/client/Engine/VFXEngine.luau
index 98cc121..f96670d 100644
--- a/src/client/Engine/VFXEngine.luau
+++ b/src/client/Engine/VFXEngine.luau
@@ -2,19 +2,20 @@
 local VFXEngine = {}
 local pools: {[string]: {Instance}} = {}
 
-local function getFromPool(templateName: string, template: Instance): Instance
-	if not pools[templateName] then
-		pools[templateName] = {}
+local function getFromPool(template: Instance): Instance
+	local name = template.Name
+	if not pools[name] then
+		pools[name] = {}
 	end
-	
-	local pool = pools[templateName]
-	local instance = table.remove(pool)
-	
-	if not instance then
-		instance = template:Clone()
+
+	local pool = pools[name]
+	local recycled: Instance? = table.remove(pool)
+
+	if recycled then
+		return recycled
 	end
-	
-	return instance
+
+	return template:Clone()
 end
 
 local function returnToPool(templateName: string, instance: Instance)
@@ -27,7 +28,12 @@ local function returnToPool(templateName: string, instance: Instance)
 end
 
 function VFXEngine.playVFX(vfxTemplate: Model, cframe: CFrame, duration: number?)
-	local vfx = getFromPool(vfxTemplate.Name, vfxTemplate)
+	local instance = getFromPool(vfxTemplate)
+	if not instance:IsA("Model") then
+		instance:Destroy()
+		return
+	end
+	local vfx: Model = instance
 	vfx:PivotTo(cframe)
 	vfx.Parent = workspace
 	
@@ -36,7 +42,8 @@ function VFXEngine.playVFX(vfxTemplate: Model, cframe: CFrame, duration: number?
 		if child:IsA("Sound") then
 			child:Play()
 		elseif child:IsA("ParticleEmitter") then
-			child:Emit(child:GetAttribute("EmitCount") or 10)
+			local count = child:GetAttribute("EmitCount")
+			child:Emit(if type(count) == "number" then count else 10)
 		end
 	end
 	
