diff --git a/src/client/CombatInput.luau b/src/client/CombatInput.luau
new file mode 100644
index 0000000..cb5454a
--- /dev/null
+++ b/src/client/CombatInput.luau
@@ -0,0 +1,150 @@
+--!strict
+-- Client combat input.
+--
+-- Keyboard: J jab, K cross, L hook, U uppercut, Space dodge, hold F block,
+--          Shift sprint while moving.
+-- Gamepad: X/Y/A/B punches, RB dodge, LB block.
+-- Touch: the HUD action buttons call the same handlers.
+--
+-- Every action sends an intent to the server. The client never guesses at
+-- damage; it only asks.
+
+local ContextActionService = game:GetService("ContextActionService")
+local UserInputService = game:GetService("UserInputService")
+
+local Shared = game:GetService("ReplicatedStorage").Shared
+local Net = require(Shared.Net)
+
+local InputController = {}
+
+type Handlers = {
+	punch: (attack: string) -> (),
+	block: (blocking: boolean) -> (),
+	dodge: () -> (),
+	sprint: (sprinting: boolean) -> (),
+}
+
+local handlers: Handlers? = nil
+local blocking = false
+
+local function setBlock(next: boolean)
+	if blocking == next then
+		return
+	end
+	blocking = next
+	if handlers then
+		handlers.block(next)
+	end
+end
+
+local function punch(attack: string)
+	if handlers then
+		handlers.punch(attack)
+	end
+end
+
+local function action(name: string, state: Enum.UserInputState): Enum.ContextActionResult
+	if state ~= Enum.UserInputState.Begin and state ~= Enum.UserInputState.End then
+		return Enum.ContextActionResult.Pass
+	end
+	if not handlers then
+		return Enum.ContextActionResult.Pass
+	end
+
+	if name == "BoxBlock" then
+		setBlock(state == Enum.UserInputState.Begin)
+		return Enum.ContextActionResult.Sink
+	elseif name == "BoxDodge" then
+		if state == Enum.UserInputState.Begin then
+			handlers.dodge()
+		end
+		return Enum.ContextActionResult.Sink
+	elseif name == "BoxSprint" then
+		handlers.sprint(state == Enum.UserInputState.Begin)
+		return Enum.ContextActionResult.Sink
+	end
+
+	for _, attack in { "Jab", "Cross", "Hook", "Uppercut" } do
+		if name == `Box{attack}` then
+			if state == Enum.UserInputState.Begin then
+				punch(attack)
+			end
+			return Enum.ContextActionResult.Sink
+		end
+	end
+
+	return Enum.ContextActionResult.Pass
+end
+
+function InputController.bind(callbacks: Handlers)
+	handlers = callbacks
+
+	ContextActionService:BindAction("BoxJab", action, true, Enum.KeyCode.J, Enum.KeyCode.ButtonX)
+	ContextActionService:BindAction("BoxCross", action, true, Enum.KeyCode.K, Enum.KeyCode.ButtonY)
+	ContextActionService:BindAction("BoxHook", action, true, Enum.KeyCode.L, Enum.KeyCode.ButtonA)
+	ContextActionService:BindAction("BoxUppercut", action, true, Enum.KeyCode.U, Enum.KeyCode.ButtonB)
+	ContextActionService:BindAction("BoxBlock", action, true, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)
+	ContextActionService:BindAction("BoxDodge", action, true, Enum.KeyCode.Space, Enum.KeyCode.ButtonR1)
+	ContextActionService:BindAction("BoxSprint", action, true, Enum.KeyCode.LeftShift)
+
+	-- Make the mobile buttons read as actions, not as key names.
+	ContextActionService:SetTitle("BoxJab", "JAB")
+	ContextActionService:SetTitle("BoxCross", "CROSS")
+	ContextActionService:SetTitle("BoxHook", "HOOK")
+	ContextActionService:SetTitle("BoxUppercut", "UPPER")
+	ContextActionService:SetTitle("BoxBlock", "BLOCK")
+	ContextActionService:SetTitle("BoxDodge", "DODGE")
+	ContextActionService:SetTitle("BoxSprint", "SPRINT")
+	ContextActionService:SetPosition("BoxSprint", UDim2.new(1, -80, 1, -210))
+
+	-- The HUD supplies its own touch controls, so drop the generic buttons on
+	-- touch devices to avoid two sets of controls.
+	if UserInputService.TouchEnabled then
+		ContextActionService:SetTitle("BoxJab", "")
+		ContextActionService:SetTitle("BoxCross", "")
+		ContextActionService:SetTitle("BoxHook", "")
+		ContextActionService:SetTitle("BoxUppercut", "")
+		ContextActionService:SetTitle("BoxBlock", "")
+		ContextActionService:SetTitle("BoxDodge", "")
+		ContextActionService:SetTitle("BoxSprint", "")
+	end
+end
+
+function InputController.unbind()
+	handlers = nil
+	blocking = false
+	for _, name in { "BoxJab", "BoxCross", "BoxHook", "BoxUppercut", "BoxBlock", "BoxDodge", "BoxSprint" } do
+		ContextActionService:UnbindAction(name)
+	end
+end
+
+function InputController.isBlocking(): boolean
+	return blocking
+end
+
+-- Exposed for the HUD's touch buttons.
+function InputController.press(attack: string)
+	punch(attack)
+end
+
+function InputController.setBlockTouch(next: boolean)
+	setBlock(next)
+end
+
+function InputController.dodge()
+	if handlers then
+		handlers.dodge()
+	end
+end
+
+function InputController.setSprint(next: boolean)
+	if handlers then
+		handlers.sprint(next)
+	end
+end
+
+function InputController.sendAttack(attack: string)
+	Net.requestAttack():FireServer(attack)
+end
+
+return InputController
