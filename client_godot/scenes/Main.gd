extends Control

var base_screen_scene := preload("res://scenes/BaseScreen.tscn")
var dungeon_screen_scene := preload("res://scenes/DungeonScreen.tscn")

@onready var content: PanelContainer = %"Content" if has_node("%Content") else $VBox/Content
@onready var base_btn: Button = $VBox/TopBar/BaseBtn
@onready var dungeon_btn: Button = $VBox/TopBar/DungeonBtn

var _current_screen: Control = null


func _ready() -> void:
	var backend := MockBackend.new()
	GameState.set_backend(backend)

	base_btn.pressed.connect(_show_base_screen)
	dungeon_btn.pressed.connect(_show_dungeon_screen)

	var snapshot: Dictionary = await backend.bootstrap_player()
	if snapshot.is_empty():
		push_error("bootstrap_player returned empty snapshot")
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
