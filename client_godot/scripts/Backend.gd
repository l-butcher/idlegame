## Abstract base class defining the backend RPC interface.
## Subclass this with MockBackend or a real SupabaseBackend.
class_name Backend
extends RefCounted


func bootstrap_player() -> Dictionary:
	push_error("Backend.bootstrap_player() not implemented")
	return {}


func get_player_snapshot() -> Dictionary:
	push_error("Backend.get_player_snapshot() not implemented")
	return {}


func claim_all(base_type: Variant) -> Dictionary:
	push_error("Backend.claim_all() not implemented")
	return {}


func start_dungeon_run(tier: int) -> Dictionary:
	push_error("Backend.start_dungeon_run() not implemented")
	return {}


func submit_run_choice(run_id: String, choice_key: String, skills_used: Array) -> Dictionary:
	push_error("Backend.submit_run_choice() not implemented")
	return {}


func submit_multiplier(run_id: String, multiplier: float, source: String) -> Dictionary:
	push_error("Backend.submit_multiplier() not implemented")
	return {}


func complete_dungeon_run(run_id: String, outcome: String) -> Dictionary:
	push_error("Backend.complete_dungeon_run() not implemented")
	return {}
