diff --git a/src/shared/Net.luau b/src/shared/Net.luau
new file mode 100644
index 0000000..473f09f
--- /dev/null
+++ b/src/shared/Net.luau
@@ -0,0 +1,99 @@
+--!strict
+-- Single place that owns the RemoteEvent names. Modules call these helpers
+-- instead of scattering WaitForChild calls around the codebase.
+
+local ReplicatedStorage = game:GetService("ReplicatedStorage")
+local RunService = game:GetService("RunService")
+
+local Net = {}
+
+local NAMES = {
+	RequestAttack = "RequestAttack",
+	RequestBlock = "RequestBlock",
+	RequestDodge = "RequestDodge",
+	RequestQueue = "RequestQueue",
+	RequestCancelQueue = "RequestCancelQueue",
+	RequestCamera = "RequestCamera",
+	Snapshot = "Snapshot",
+	CombatEvent = "CombatEvent",
+	SetCameraMode = "SetCameraMode",
+}
+
+local folder: Folder? = nil
+
+local function remotesFolder(): Folder
+	if folder then
+		return folder
+	end
+	local existing = ReplicatedStorage:FindFirstChild("Remotes")
+	if existing and existing:IsA("Folder") then
+		folder = existing
+		return existing
+	end
+	if RunService:IsServer() then
+		local created = Instance.new("Folder")
+		created.Name = "Remotes"
+		created.Parent = ReplicatedStorage
+		folder = created
+		return created
+	end
+	local waited = ReplicatedStorage:WaitForChild("Remotes", 30)
+	if not waited or not waited:IsA("Folder") then
+		error("Remotes folder never arrived; is the server script running?")
+	end
+	folder = waited
+	return waited
+end
+
+function Net.ensureCreated()
+	local parent = remotesFolder()
+	for _, name in NAMES do
+		if not parent:FindFirstChild(name) then
+			local remote = Instance.new("RemoteEvent")
+			remote.Name = name
+			remote.Parent = parent
+		end
+	end
+end
+
+local function remote(name: string): RemoteEvent
+	local found = remotesFolder():WaitForChild(name, 30)
+	if not found or not found:IsA("RemoteEvent") then
+		error(`RemoteEvent {name} missing`)
+	end
+	return found
+end
+
+function Net.requestAttack(): RemoteEvent
+	return remote(NAMES.RequestAttack)
+end
+
+function Net.requestBlock(): RemoteEvent
+	return remote(NAMES.RequestBlock)
+end
+
+function Net.requestDodge(): RemoteEvent
+	return remote(NAMES.RequestDodge)
+end
+
+function Net.requestQueue(): RemoteEvent
+	return remote(NAMES.RequestQueue)
+end
+
+function Net.requestCancelQueue(): RemoteEvent
+	return remote(NAMES.RequestCancelQueue)
+end
+
+function Net.snapshot(): RemoteEvent
+	return remote(NAMES.Snapshot)
+end
+
+function Net.combatEvent(): RemoteEvent
+	return remote(NAMES.CombatEvent)
+end
+
+function Net.setCameraMode(): RemoteEvent
+	return remote(NAMES.SetCameraMode)
+end
+
+return Net
