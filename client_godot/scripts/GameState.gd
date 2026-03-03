## Autoload singleton that holds authoritative client-side game state.
## Register in Project → Project Settings → Autoload as "GameState".
extends Node

signal snapshot_updated(snapshot: Dictionary)
signal run_updated(run: Dictionary)
signal rewards_updated(rewards: Array)
signal debug_updated()

var player_snapshot: Dictionary = {}
var active_run: Dictionary = {}
var last_rewards: Array = []

var last_rpc: String = ""
var last_error: String = ""

var _backend: Backend = null


func set_backend(b: Backend) -> void:
	_backend = b


func get_backend() -> Backend:
	return _backend


func log_rpc(rpc_name: String) -> void:
	last_rpc = rpc_name
	last_error = ""
	debug_updated.emit()


func log_error(msg: String) -> void:
	last_error = msg
	push_error(msg)
	debug_updated.emit()


func set_snapshot(snapshot: Dictionary) -> void:
	player_snapshot = snapshot if snapshot is Dictionary else {}
	active_run = player_snapshot.get("active_run", {})
	snapshot_updated.emit(player_snapshot)


func set_active_run(run: Dictionary) -> void:
	active_run = run if run is Dictionary else {}
	run_updated.emit(active_run)


func set_rewards(rewards: Array) -> void:
	last_rewards = rewards if rewards is Array else []
	rewards_updated.emit(last_rewards)
	debug_updated.emit()


## Safe accessors for snapshot sub-keys (never return null).

func get_player_state() -> Dictionary:
	return player_snapshot.get("player_state", {}) if player_snapshot is Dictionary else {}


func get_bases() -> Array:
	return player_snapshot.get("bases", []) if player_snapshot is Dictionary else []


func get_inventories() -> Array:
	return player_snapshot.get("inventories", []) if player_snapshot is Dictionary else []


func get_unlocks() -> Array:
	return player_snapshot.get("unlocks", []) if player_snapshot is Dictionary else []


func get_combat_skills() -> Array:
	return player_snapshot.get("combat_skills", []) if player_snapshot is Dictionary else []


func get_production_skills() -> Array:
	return player_snapshot.get("production_skills", []) if player_snapshot is Dictionary else []
