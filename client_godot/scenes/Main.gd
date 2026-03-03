extends Control

var base_screen_scene := preload("res://scenes/BaseScreen.tscn")
var dungeon_screen_scene := preload("res://scenes/DungeonScreen.tscn")

@onready var content: PanelContainer = $VBox/Content
@onready var base_btn: Button = $VBox/TopBar/BaseBtn
@onready var dungeon_btn: Button = $VBox/TopBar/DungeonBtn

@onready var rpc_label: Label = $VBox/DebugPanel/VBox/RpcLabel
@onready var error_label: Label = $VBox/DebugPanel/VBox/ErrorLabel
@onready var rewards_label: Label = $VBox/DebugPanel/VBox/RewardsLabel

var _current_screen: Control = null


func _ready() -> void:
	var backend := MockBackend.new()
	GameState.set_backend(backend)

	base_btn.pressed.connect(_show_base_screen)
	dungeon_btn.pressed.connect(_show_dungeon_screen)

	GameState.debug_updated.connect(_refresh_debug)
	GameState.rewards_updated.connect(_on_rewards)

	GameState.log_rpc("bootstrap_player")
	var snapshot: Dictionary = await backend.bootstrap_player()
	if not snapshot is Dictionary or snapshot.is_empty():
		GameState.log_error("bootstrap_player returned empty snapshot")
		return

	GameState.set_snapshot(snapshot)
	_show_base_screen()


func _switch_screen(scene: PackedScene) -> void:
	if _current_screen:
		_current_screen.queue_free()
		_current_screen = null

	var instance: Control = scene.instantiate()
	content.add_child(instance)
	_current_screen = instance


func _show_base_screen() -> void:
	base_btn.disabled = true
	dungeon_btn.disabled = false
	_switch_screen(base_screen_scene)


func _show_dungeon_screen() -> void:
	base_btn.disabled = false
	dungeon_btn.disabled = true
	_switch_screen(dungeon_screen_scene)


# ── debug panel ──────────────────────────────────────────────

func _refresh_debug() -> void:
	rpc_label.text = "Last RPC: %s" % (GameState.last_rpc if GameState.last_rpc != "" else "—")
	error_label.text = "Last Error: %s" % (GameState.last_error if GameState.last_error != "" else "—")


func _on_rewards(rewards: Array) -> void:
	if not rewards is Array or rewards.is_empty():
		rewards_label.text = "Last Rewards: (none)"
		return
	var parts: PackedStringArray = []
	for r in rewards:
		if r is Dictionary:
			parts.append("%s x%d" % [r.get("item_id", "?"), int(r.get("quantity", 0))])
	rewards_label.text = "Last Rewards: %s" % ", ".join(parts)
