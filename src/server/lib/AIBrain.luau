diff --git a/src/shared/AIBrain.luau b/src/shared/AIBrain.luau
index cb5849b..da2e7c4 100644
--- a/src/shared/AIBrain.luau
+++ b/src/shared/AIBrain.luau
@@ -39,7 +39,7 @@ export type Blackboard = {
 	foeBusyRemaining: number,
 	foeStunned: boolean,
 	foeBlocking: boolean,
+	foeAttack: string?,
 	foeAttackTimeLeft: number,
 	foeAttackSerial: number,
 	edgeDistance: number,
@@ -66,6 +66,8 @@ export type Brain = {
 local Brain = {}
 Brain.__index = Brain
 
+local AI = {}
+
 local ORDER: { string } = { "Jab", "Cross", "Hook", "Uppercut" }
 
 local ATTACK_RANGE: { [string]: number } = {
@@ -295,4 +297,11 @@ function Brain.think(self: Brain, bb: Blackboard): Decision
 	return decision
 end
 
+-- Public surface. `new` and `think` are the only entry points the server
+-- needs; the Brain type itself stays internal. Assigned after the functions
+-- exist so the table is never populated with nils.
+AI.new = Brain.new
+AI.think = Brain.think
+AI.Brain = Brain
+
+return AI
