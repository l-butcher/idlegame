## Autoload singleton that holds authoritative client-side game state.
## Register in Project → Project Settings → Autoload as "GameState".
extends Node

signal snapshot_updated(snapshot: Dictionary)
signal run_updated(run: Dictionary)
signal rewards_updated(rewards: Array)

var player_snapshot: Dictionary = {}
var active_run: Dictionary = {}
var last_rewards: Array = []


func set_snapshot(snapshot: Dictionary) -> void:
	player_snapshot = snapshot
	active_run = snapshot.get("active_run", {})
	snapshot_updated.emit(player_snapshot)


func set_active_run(run: Dictionary) -> void:
	active_run = run
	run_updated.emit(active_run)


func set_rewards(rewards: Array) -> void:
	last_rewards = rewards
	rewards_updated.emit(last_rewards)
