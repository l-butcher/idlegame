extends VBoxContainer

@onready var tier_label: Label = $TierLabel
@onready var bases_list: VBoxContainer = $Scroll/BasesList
@onready var claim_all_btn: Button = $ClaimAllBtn


func _ready() -> void:
	claim_all_btn.pressed.connect(_on_claim_all)
	GameState.snapshot_updated.connect(_on_snapshot_updated)
	_refresh()


func _on_snapshot_updated(_snapshot: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	var ps: Dictionary = GameState.get_player_state()
	tier_label.text = "Max Dungeon Tier: %d" % int(ps.get("highest_dungeon_tier", 0))

	for child in bases_list.get_children():
		child.queue_free()

	var bases: Array = GameState.get_bases()
	var inventories: Array = GameState.get_inventories()
	var unlocks: Array = GameState.get_unlocks()

	if bases.is_empty():
		var placeholder := Label.new()
		placeholder.text = "Loading bases..."
		bases_list.add_child(placeholder)
		return

	for base in bases:
		if not base is Dictionary:
			continue
		var base_id: String = str(base.get("id", ""))
		var base_type: String = str(base.get("base_type_id", "unknown"))

		var is_unlocked := false
		for u in unlocks:
			if u is Dictionary and u.get("unlock_type") == "base" and u.get("unlock_key") == base_type:
				is_unlocked = true
				break

		var card := PanelContainer.new()
		var vbox := VBoxContainer.new()
		card.add_child(vbox)

		var title := Label.new()
		title.text = "%s  %s" % [base_type.to_upper(), "(locked)" if not is_unlocked else ""]
		title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(title)

		var base_inv: Array = []
		for row in inventories:
			if row is Dictionary and str(row.get("base_id", "")) == base_id:
				base_inv.append(row)

		if base_inv.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "  (no items yet)" if is_unlocked else "  —"
			vbox.add_child(empty_lbl)
		else:
			for row in base_inv:
				var item_lbl := Label.new()
				item_lbl.text = "  %s: %d" % [str(row.get("item_id", "?")), int(row.get("quantity", 0))]
				vbox.add_child(item_lbl)

		if is_unlocked:
			var claim_btn := Button.new()
			claim_btn.text = "Claim %s" % base_type.capitalize()
			claim_btn.pressed.connect(_on_claim_base.bind(base_type))
			vbox.add_child(claim_btn)

		bases_list.add_child(card)


func _on_claim_base(base_type: String) -> void:
	var backend := GameState.get_backend()
	if backend == null:
		GameState.log_error("No backend available")
		return
	claim_all_btn.disabled = true
	GameState.log_rpc("claim_all(%s)" % base_type)
	var result: Dictionary = await backend.claim_all(base_type)
	if not result is Dictionary or result.is_empty():
		GameState.log_error("claim_all(%s) returned empty" % base_type)
	else:
		var snapshot: Variant = result.get("snapshot", {})
		GameState.set_snapshot(snapshot if snapshot is Dictionary else {})
	claim_all_btn.disabled = false


func _on_claim_all() -> void:
	var backend := GameState.get_backend()
	if backend == null:
		GameState.log_error("No backend available")
		return
	claim_all_btn.disabled = true
	GameState.log_rpc("claim_all(null)")
	var result: Dictionary = await backend.claim_all(null)
	if not result is Dictionary or result.is_empty():
		GameState.log_error("claim_all(null) returned empty")
	else:
		var snapshot: Variant = result.get("snapshot", {})
		GameState.set_snapshot(snapshot if snapshot is Dictionary else {})
	claim_all_btn.disabled = false
