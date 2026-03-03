extends VBoxContainer

var backend: Backend

@onready var tier_label: Label = $TierLabel
@onready var bases_list: VBoxContainer = $Scroll/BasesList
@onready var claim_all_btn: Button = $ClaimAllBtn


func _ready() -> void:
	claim_all_btn.pressed.connect(_on_claim_all)
	GameState.snapshot_updated.connect(_on_snapshot_updated)
	_refresh(GameState.player_snapshot)


func _on_snapshot_updated(snapshot: Dictionary) -> void:
	_refresh(snapshot)


func _refresh(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return

	var ps: Dictionary = snapshot.get("player_state", {})
	tier_label.text = "Max Dungeon Tier: %d" % int(ps.get("highest_dungeon_tier", 0))

	for child in bases_list.get_children():
		child.queue_free()

	var bases: Array = snapshot.get("bases", [])
	var inventories: Array = snapshot.get("inventories", [])
	var unlocks: Array = snapshot.get("unlocks", [])

	for base in bases:
		var base_id: String = base.get("id", "")
		var base_type: String = base.get("base_type_id", "")

		var is_unlocked := false
		for u in unlocks:
			if u.get("unlock_type") == "base" and u.get("unlock_key") == base_type:
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
			if row.get("base_id") == base_id:
				base_inv.append(row)

		if base_inv.is_empty() and is_unlocked:
			var empty_lbl := Label.new()
			empty_lbl.text = "  (no items yet)"
			vbox.add_child(empty_lbl)
		else:
			for row in base_inv:
				var item_lbl := Label.new()
				item_lbl.text = "  %s: %d" % [row.get("item_id", "?"), int(row.get("quantity", 0))]
				vbox.add_child(item_lbl)

		if is_unlocked:
			var claim_btn := Button.new()
			claim_btn.text = "Claim %s" % base_type.capitalize()
			claim_btn.pressed.connect(_on_claim_base.bind(base_type))
			vbox.add_child(claim_btn)

		bases_list.add_child(card)


func _on_claim_base(base_type: String) -> void:
	claim_all_btn.disabled = true
	var result: Dictionary = backend.claim_all(base_type)
	var snapshot: Dictionary = result.get("snapshot", {})
	GameState.set_snapshot(snapshot)
	claim_all_btn.disabled = false


func _on_claim_all() -> void:
	claim_all_btn.disabled = true
	var result: Dictionary = backend.claim_all(null)
	var snapshot: Dictionary = result.get("snapshot", {})
	GameState.set_snapshot(snapshot)
	claim_all_btn.disabled = false
