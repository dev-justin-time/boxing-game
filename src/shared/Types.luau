diff --git a/src/shared/Types.luau b/src/shared/Types.luau
new file mode 100644
index 0000000..b895767
--- /dev/null
+++ b/src/shared/Types.luau
@@ -0,0 +1,50 @@
+--!strict
+-- Shared data shapes sent between server and client.
+
+export type Corner = "Red" | "Blue"
+
+export type FighterInfo = {
+	id: string,
+	name: string,
+	corner: Corner,
+	health: number,
+	maxHealth: number,
+	stamina: number,
+	maxStamina: number,
+	guard: number,
+	maxGuard: number,
+	blocking: boolean,
+	combo: number,
+	isBot: boolean,
+	connected: boolean,
+}
+
+export type Phase = "Lobby" | "Queued" | "Intro" | "Round" | "RoundEnd" | "MatchEnd"
+
+export type Snapshot = {
+	phase: Phase,
+	round: number,
+	maxRounds: number,
+	clock: number,
+	countdown: number,
+	redScore: number,
+	blueScore: number,
+	redId: string?,
+	blueId: string?,
+	fighters: { FighterInfo },
+	you: string?,
+	corner: Corner?,
+	banner: string?,
+	bannerDetail: string?,
+	queueSize: number,
+	cameraMode: string,
+}
+
+-- Tagged dictionary; kept loose so new event kinds don't require a union
+-- rewrite in every consumer.
+export type CombatEvent = { [string]: any }
+
+export type QueueRequest = {
+	mode: "PvP" | "AI",
+	difficulty: string?,
+}
