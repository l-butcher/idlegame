extends ScrollContainer

@onready var setup_panel: PanelContainer = $Root/SetupPanel
@onready var tier_option: OptionButton = $Root/SetupPanel/VBox/TierRow/TierOption
@onready var start_btn: Button = $Root/SetupPanel/VBox/StartBtn

@onready var run_panel: PanelContainer = $Root/RunPanel
@onready var status_label: Label = $Root/RunPanel/VBox/StatusLabel
@onready var choices_container: VBoxContainer = $Root/RunPanel/VBox/ChoicesContainer
@onready var mult_container: HBoxContainer = $Root/RunPanel/VBox/MultContainer
@onready var complete_container: HBoxContainer = $Root/RunPanel/VBox/CompleteContainer

@onready var rewards_panel: PanelContainer = $Root/RewardsPanel
@onready var rewards_list: VBoxContainer = $Root/RewardsPanel/VBox/RewardsList
@onready var new_run_btn: Button = $Root/RewardsPanel/VBox/NewRunBtn

var _run_id: String = ""
var _choice_step: int = 0

const CHOICE_SKILLS := {
	"path_a": ["attack"],
	"path_b": ["defense"],
	"path_c": ["health"],
}


func _ready() -> void:
	start_btn.pressed.connect(_on_start)
	new_run_btn.pressed.connect(_on_new_run)
	GameState.snapshot_updated.connect(_on_snapshot_updated)
	_refresh_tier_selector()
	_show_setup()


func _on_snapshot_updated(_snapshot: Dictionary) -> void:
	if _run_id == "":
		_refresh_tier_selector()


func _refresh_tier_selector() -> void:
	tier_option.clear()
	var ps: Dictionary = GameState.get_player_state()
	var max_tier: int = int(ps.get("highest_dungeon_tier", 0)) + 1
	max_tier = mini(max_tier, 25)
	if max_tier < 1:
		max_tier = 1
	for t in range(1, max_tier + 1):
		tier_option.add_item("Tier %d" % t, t)
	if tier_option.item_count > 0:
		tier_option.selected = tier_option.item_count - 1


func _show_setup() -> void:
	setup_panel.visible = true
	run_panel.visible = false
	rewards_panel.visible = false


func _show_run() -> void:
	setup_panel.visible = false
	run_panel.visible = true
	rewards_panel.visible = false


func _show_rewards() -> void:
	setup_panel.visible = false
	run_panel.visible = false
	rewards_panel.visible = true


# ── start ────────────────────────────────────────────────────

func _on_start() -> void:
	var backend := GameState.get_backend()
	if backend == null:
		GameState.log_error("No backend available")
		return

	var tier: int = tier_option.get_selected_id()
	if tier <= 0:
		tier = 1

	start_btn.disabled = true
	GameState.log_rpc("start_dungeon_run(%d)" % tier)
	var result: Dictionary = await backend.start_dungeon_run(tier)
	start_btn.disabled = false

	if not result is Dictionary or result.is_empty():
		GameState.log_error("start_dungeon_run(%d) returned empty" % tier)
		return

	var run: Variant = result.get("run", {})
	if not run is Dictionary:
		run = {}
	_run_id = str((run as Dictionary).get("id", ""))
	_choice_step = 0
	GameState.set_active_run(run as Dictionary)

	status_label.text = "Tier %d — In Progress" % tier
	_build_choices()
	_build_multiplier_buttons()
	_build_complete_buttons()
	_show_run()


# ── choices ──────────────────────────────────────────────────

func _build_choices() -> void:
	for c in choices_container.get_children():
		c.queue_free()

	for step in range(3):
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Step %d:" % (step + 1)
		label.custom_minimum_size.x = 60
		row.add_child(label)

		var btn_a := Button.new()
		btn_a.text = "Path A (attack)"
		btn_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_a.pressed.connect(_on_choice.bind(step, "path_a"))
		row.add_child(btn_a)

		var btn_b := Button.new()
		btn_b.text = "Path B (defense)"
		btn_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_b.pressed.connect(_on_choice.bind(step, "path_b"))
		row.add_child(btn_b)

		if step > 0:
			_set_row_disabled(row, true)

		choices_container.add_child(row)


func _set_row_disabled(row: HBoxContainer, disabled: bool) -> void:
	for child in row.get_children():
		if child is Button:
			child.disabled = disabled


func _on_choice(step: int, choice_key: String) -> void:
	if step != _choice_step:
		return

	var backend := GameState.get_backend()
	if backend == null:
		GameState.log_error("No backend available")
		return

	var skills: Array = CHOICE_SKILLS.get(choice_key, ["attack"])
	GameState.log_rpc("submit_run_choice(%s)" % choice_key)
	var run: Dictionary = await backend.submit_run_choice(_run_id, choice_key, skills)
	if not run is Dictionary or run.is_empty():
		GameState.log_error("submit_run_choice returned empty")
		return

	GameState.set_active_run(run)

	var row: HBoxContainer = choices_container.get_child(step) as HBoxContainer
	_set_row_disabled(row, true)
	for child in row.get_children():
		if child is Label:
			child.text = "Step %d: %s" % [step + 1, choice_key]

	_choice_step += 1

	if _choice_step < choices_container.get_child_count():
		var next_row: HBoxContainer = choices_container.get_child(_choice_step) as HBoxContainer
		_set_row_disabled(next_row, false)


# ── multiplier ───────────────────────────────────────────────

func _build_multiplier_buttons() -> void:
	for c in mult_container.get_children():
		c.queue_free()

	for m in [1.0, 2.0, 3.0]:
		var btn := Button.new()
		btn.text = "%dx" % int(m)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_multiplier.bind(m))
		mult_container.add_child(btn)


func _on_multiplier(mult: float) -> void:
	var backend := GameState.get_backend()
	if backend == null:
		GameState.log_error("No backend available")
		return

	GameState.log_rpc("submit_multiplier(%.1f)" % mult)
	var run: Dictionary = await backend.submit_multiplier(_run_id, mult, "skill_check")
	if not run is Dictionary or run.is_empty():
		GameState.log_error("submit_multiplier returned empty")
		return

	GameState.set_active_run(run)
	status_label.text = "Tier — Multiplier set to %dx" % int(mult)

	for child in mult_container.get_children():
		if child is Button:
			child.disabled = true


# ── complete ─────────────────────────────────────────────────

func _build_complete_buttons() -> void:
	for c in complete_container.get_children():
		c.queue_free()

	var success_btn := Button.new()
	success_btn.text = "Complete: Success"
	success_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	success_btn.pressed.connect(_on_complete.bind("success"))
	complete_container.add_child(success_btn)

	var fail_btn := Button.new()
	fail_btn.text = "Complete: Fail"
	fail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fail_btn.pressed.connect(_on_complete.bind("fail"))
	complete_container.add_child(fail_btn)


func _on_complete(outcome: String) -> void:
	var backend := GameState.get_backend()
	if backend == null:
		GameState.log_error("No backend available")
		return

	for child in complete_container.get_children():
		if child is Button:
			child.disabled = true

	GameState.log_rpc("complete_dungeon_run(%s)" % outcome)
	var result: Dictionary = await backend.complete_dungeon_run(_run_id, outcome)
	if not result is Dictionary or result.is_empty():
		GameState.log_error("complete_dungeon_run returned empty")
		return

	var rewards: Variant = result.get("rewards", [])
	var snapshot: Variant = result.get("snapshot", {})

	GameState.set_rewards(rewards if rewards is Array else [])
	GameState.set_snapshot(snapshot if snapshot is Dictionary else {})
	_run_id = ""

	_populate_rewards(rewards if rewards is Array else [], outcome)
	_show_rewards()


# ── rewards display ──────────────────────────────────────────

func _populate_rewards(rewards: Array, outcome: String) -> void:
	for c in rewards_list.get_children():
		c.queue_free()

	var header := Label.new()
	header.text = "Run %s!" % ("succeeded" if outcome == "success" else "failed")
	rewards_list.add_child(header)

	if rewards.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "  (no rewards)"
		rewards_list.add_child(none_lbl)
	else:
		for r in rewards:
			if not r is Dictionary:
				continue
			var lbl := Label.new()
			var tag: String = ""
			if r.has("type"):
				tag = " [%s]" % str(r.type)
			lbl.text = "  %s x%d%s" % [str(r.get("item_id", "?")), int(r.get("quantity", 0)), tag]
			rewards_list.add_child(lbl)

	var combat: Array = GameState.get_combat_skills()
	var skills_lbl := Label.new()
	var skill_text := ""
	for sk in combat:
		if not sk is Dictionary:
			continue
		if skill_text != "":
			skill_text += ", "
		skill_text += "%s L%d (%d xp)" % [str(sk.get("skill_id", "?")), int(sk.get("level", 1)), int(sk.get("xp", 0))]
	skills_lbl.text = "Combat: %s" % (skill_text if skill_text != "" else "—")
	rewards_list.add_child(skills_lbl)

	var ps: Dictionary = GameState.get_player_state()
	var tier_lbl := Label.new()
	tier_lbl.text = "Highest tier: %d" % int(ps.get("highest_dungeon_tier", 0))
	rewards_list.add_child(tier_lbl)


func _on_new_run() -> void:
	_refresh_tier_selector()
	_show_setup()
