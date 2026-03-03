## In-memory mock backend for offline development and testing.
## Mirrors the behaviour of the Supabase V1 RPCs and the TS mockBackend.
class_name MockBackend
extends Backend

# ── constants ────────────────────────────────────────────────

const USER_ID := "mock-user-0001"
const STORAGE_CAP := 1000
const XP_PER_LEVEL := 1000
const OFFLINE_CAP_S := 43200.0

const PROD_SKILLS: Array[String] = [
	"mining", "farming", "ranching", "refining", "crafting", "tech",
]
const COMBAT_SKILLS: Array[String] = ["attack", "defense", "health"]

const RARE_ITEMS: Array[String] = [
	"crystal_prism", "dark_matter_shard", "quantum_dust",
	"void_essence", "nova_fragment",
]
const SHIP_PARTS: Array[String] = [
	"ship_engine_mk1", "ship_shield_mk1", "ship_nav_mk1",
	"ship_hull_plate", "ship_thruster",
]
const DUNGEON_CHOICES: Array[String] = ["path_a", "path_b", "path_c"]

const TIER_NAMES: Array[String] = [
	"Shallow Cavern", "Dusty Tunnels", "Abandoned Mine", "Crystal Grotto",
	"Fungal Depths", "Flooded Passage", "Lava Vents", "Frozen Rift",
	"Toxic Warren", "Shadow Hollow", "Iron Labyrinth", "Bone Catacombs",
	"Magma Core", "Void Fissure", "Storm Nexus", "Obsidian Maze",
	"Spectral Halls", "Plasma Tunnels", "Gravity Well", "Chrono Rift",
	"Nebula Depths", "Dark Matter Pit", "Singularity Gate", "Stellar Tomb",
	"Event Horizon",
]

# ── base configs ─────────────────────────────────────────────

class _BaseConfig:
	var type: String
	var locked: bool
	var resources: Array[String]
	var rates: Dictionary

	func _init(t: String, l: bool, r: Array[String], rt: Dictionary) -> void:
		type = t; locked = l; resources = r; rates = rt

var _base_configs: Array[_BaseConfig] = []

# ── state ────────────────────────────────────────────────────

var _player_state: Dictionary = {}
var _bases: Array[Dictionary] = []
var _inventories: Array[Dictionary] = []
var _caps: Array[Dictionary] = []
var _prod_skills: Array[Dictionary] = []
var _combat_skills: Array[Dictionary] = []
var _ship: Dictionary = {}
var _unlocks: Array[Dictionary] = []
var _active_run: Dictionary = {}
var _run_choice_skills: Array[String] = []
var _bootstrapped := false
var _id_counter := 0

# ── init ─────────────────────────────────────────────────────

func _init() -> void:
	_base_configs = [
		_BaseConfig.new("earth", false,
			["ore_iron", "ore_copper", "food_basic", "bio_samples", "credits"] as Array[String],
			{"ore_iron": 0.5, "ore_copper": 0.3, "food_basic": 0.8, "bio_samples": 0.2, "credits": 0.05}),
		_BaseConfig.new("moon", true,
			["ore_iron", "metal_iron", "credits"] as Array[String],
			{"ore_iron": 0.8, "metal_iron": 0.3, "credits": 0.1}),
		_BaseConfig.new("asteroid", true,
			["ore_copper", "metal_copper", "circuit_basic", "credits"] as Array[String],
			{"ore_copper": 1.0, "metal_copper": 0.5, "circuit_basic": 0.4, "credits": 0.15}),
	]

# ── helpers ──────────────────────────────────────────────────

func _uid() -> String:
	_id_counter += 1
	return "mock-%d-%d" % [Time.get_unix_time_from_system(), _id_counter]


func _ts() -> String:
	return Time.get_datetime_string_from_system(true)


func _pick(arr: Array) -> Variant:
	return arr[randi() % arr.size()]


func _chance(pct: float) -> bool:
	return randf() * 100.0 < pct


func _find_inv(base_id: String, item_id: String) -> Dictionary:
	for row in _inventories:
		if row.base_id == base_id and row.item_id == item_id:
			return row
	return {}


func _get_or_create_inv(base_id: String, item_id: String) -> Dictionary:
	var row := _find_inv(base_id, item_id)
	if row.is_empty():
		row = {
			"id": _uid(), "user_id": USER_ID, "base_id": base_id,
			"item_id": item_id, "quantity": 0, "updated_at": _ts(),
		}
		_inventories.append(row)
	return row


func _get_cap(base_id: String, item_id: String) -> int:
	for c in _caps:
		if c.base_id == base_id and c.item_id == item_id:
			return int(c.cap)
	return STORAGE_CAP


func _add_inventory(base_id: String, item_id: String, qty: int) -> Dictionary:
	var row := _get_or_create_inv(base_id, item_id)
	var cap := _get_cap(base_id, item_id)
	row.quantity = clampi(int(row.quantity) + qty, 0, cap)
	row.updated_at = _ts()
	return row


func _earth_base_id() -> String:
	for b in _bases:
		if b.base_type_id == "earth":
			return b.id
	return ""


func _add_ship_part(item_id: String, qty: int) -> void:
	for p in _ship.parts:
		if p.item_id == item_id:
			p.quantity = int(p.quantity) + qty
			return
	_ship.parts.append({
		"id": _uid(), "user_id": USER_ID, "item_id": item_id,
		"quantity": qty, "acquired_at": _ts(),
	})


func _grant_combat_xp(skill_id: String, xp: int) -> void:
	for sk in _combat_skills:
		if sk.skill_id == skill_id:
			sk.xp = int(sk.xp) + xp
			while int(sk.xp) >= int(sk.level) * XP_PER_LEVEL:
				sk.xp = int(sk.xp) - int(sk.level) * XP_PER_LEVEL
				sk.level = int(sk.level) + 1
			sk.updated_at = _ts()
			return


func _is_unlocked(base_type: String) -> bool:
	for u in _unlocks:
		if u.unlock_type == "base" and u.unlock_key == base_type:
			return true
	return false


func _build_snapshot() -> Dictionary:
	return {
		"player_state": _player_state.duplicate(true),
		"bases": _bases.duplicate(true),
		"inventories": _inventories.duplicate(true),
		"caps": _caps.duplicate(true),
		"production_skills": _prod_skills.duplicate(true),
		"combat_skills": _combat_skills.duplicate(true),
		"ship": {
			"info": _ship.get("info", {}).duplicate(true) if _ship.has("info") else {},
			"parts": _ship.get("parts", []).duplicate(true),
			"equipped": _ship.get("equipped", []).duplicate(true),
			"upgrades": _ship.get("upgrades", []).duplicate(true),
		},
		"unlocks": _unlocks.duplicate(true),
		"active_run": _active_run.duplicate(true),
	}

# ── RPCs ─────────────────────────────────────────────────────

func bootstrap_player() -> Dictionary:
	if _bootstrapped:
		return _build_snapshot()

	var ts := _ts()

	_player_state = {
		"user_id": USER_ID,
		"display_name": "Space Cadet",
		"highest_dungeon_tier": 0,
		"last_login_at": ts,
		"last_claim_at": ts,
		"total_dungeon_runs": 0,
		"created_at": ts,
		"updated_at": ts,
	}

	for cfg in _base_configs:
		var base := {
			"id": _uid(), "user_id": USER_ID,
			"base_type_id": cfg.type,
			"unlocked_at": ts, "last_claim_at": ts,
		}
		_bases.append(base)

		for res in cfg.resources:
			_caps.append({
				"id": _uid(), "user_id": USER_ID,
				"base_id": base.id, "item_id": res, "cap": STORAGE_CAP,
			})

		if not cfg.locked:
			_get_or_create_inv(base.id, "credits").quantity = 100
			_unlocks.append({
				"id": _uid(), "user_id": USER_ID,
				"unlock_type": "base", "unlock_key": cfg.type,
				"unlocked_at": ts,
			})

	for s in PROD_SKILLS:
		_prod_skills.append({
			"id": _uid(), "user_id": USER_ID,
			"skill_id": s, "level": 1, "xp": 0, "updated_at": ts,
		})

	for s in COMBAT_SKILLS:
		_combat_skills.append({
			"id": _uid(), "user_id": USER_ID,
			"skill_id": s, "level": 1, "xp": 0, "updated_at": ts,
		})

	_ship = {
		"info": {
			"user_id": USER_ID, "ship_name": "Starter Ship",
			"hull_level": 1, "created_at": ts, "updated_at": ts,
		},
		"parts": [] as Array[Dictionary],
		"equipped": [] as Array[Dictionary],
		"upgrades": [] as Array[Dictionary],
	}

	_bootstrapped = true
	return _build_snapshot()


func get_player_snapshot() -> Dictionary:
	assert(_bootstrapped, "Player not bootstrapped")
	return _build_snapshot()


func claim_all(base_type: Variant) -> Dictionary:
	assert(_bootstrapped, "Player not bootstrapped")
	var ts := _ts()
	var deltas: Array[Dictionary] = []

	for base in _bases:
		if base_type != null and base.base_type_id != base_type:
			continue
		if not _is_unlocked(base.base_type_id):
			continue

		var cfg: _BaseConfig = null
		for c in _base_configs:
			if c.type == base.base_type_id:
				cfg = c
				break
		if cfg == null:
			continue

		var last_str: String = base.last_claim_at
		var elapsed_s: float = clampf(
			Time.get_unix_time_from_system() - Time.get_unix_time_from_datetime_string(last_str),
			0.0, OFFLINE_CAP_S)
		if elapsed_s <= 0.0:
			continue

		for res in cfg.resources:
			var rate: float = cfg.rates.get(res, 0.0)
			var produced := int(floorf(rate * elapsed_s))
			if produced <= 0:
				continue
			var row := _add_inventory(base.id, res, produced)
			deltas.append(row.duplicate(true))

		base.last_claim_at = ts

	_player_state.last_claim_at = ts
	_player_state.updated_at = ts

	return {"deltas": deltas, "snapshot": _build_snapshot()}


func start_dungeon_run(tier: int) -> Dictionary:
	assert(_bootstrapped, "Player not bootstrapped")
	assert(_active_run.is_empty(), "A dungeon run is already in progress")
	assert(tier >= 1 and tier <= 25, "Invalid tier")
	assert(tier <= int(_player_state.highest_dungeon_tier) + 1, "Tier not unlocked")

	var ts := _ts()
	_active_run = {
		"id": _uid(), "user_id": USER_ID, "tier": tier,
		"status": "in_progress", "multiplier": 1.0,
		"started_at": ts, "completed_at": null,
	}
	_run_choice_skills.clear()

	_player_state.total_dungeon_runs = int(_player_state.total_dungeon_runs) + 1
	_player_state.updated_at = ts

	return {"run": _active_run.duplicate(true), "choices": DUNGEON_CHOICES.duplicate()}


func submit_run_choice(run_id: String, choice_key: String, skills_used: Array) -> Dictionary:
	assert(not _active_run.is_empty() and _active_run.id == run_id, "Run not found")
	assert(_active_run.status == "in_progress", "Run is not in progress")

	for s in skills_used:
		_run_choice_skills.append(str(s))

	return _active_run.duplicate(true)


func submit_multiplier(run_id: String, multiplier: float, _source: String) -> Dictionary:
	assert(not _active_run.is_empty() and _active_run.id == run_id, "Run not found")
	assert(_active_run.status == "in_progress", "Run is not in progress")

	_active_run.multiplier = clampf(multiplier, 1.0, 3.0)
	return _active_run.duplicate(true)


func complete_dungeon_run(run_id: String, outcome: String) -> Dictionary:
	assert(not _active_run.is_empty() and _active_run.id == run_id, "Run not found")
	assert(_active_run.status == "in_progress", "Run is not in progress")
	assert(outcome in ["success", "fail"], "Invalid outcome")

	var ts := _ts()
	var tier: int = _active_run.tier
	var mult: float = _active_run.multiplier
	var factor: float = 1.0 if outcome == "success" else 0.5
	var base_credits := 50 + (tier - 1) * 100
	var base_xp := 100 + (tier - 1) * 200
	var e_base := _earth_base_id()

	var rewards: Array[Dictionary] = []

	# credits
	var credit_qty := int(floorf(base_credits * mult * factor))
	if credit_qty > 0:
		_add_inventory(e_base, "credits", credit_qty)
		rewards.append({
			"id": _uid(), "run_id": run_id, "user_id": USER_ID,
			"item_id": "credits", "quantity": credit_qty, "granted_at": ts,
		})

	# ore
	var ore_qty := int(floorf(tier * 5 * mult * factor))
	if ore_qty > 0:
		_add_inventory(e_base, "ore_iron", ore_qty)
		rewards.append({
			"id": _uid(), "run_id": run_id, "user_id": USER_ID,
			"item_id": "ore_iron", "quantity": ore_qty, "granted_at": ts,
		})

	# food
	var food_qty := int(floorf(tier * 4 * mult * factor))
	if food_qty > 0:
		_add_inventory(e_base, "food_basic", food_qty)
		rewards.append({
			"id": _uid(), "run_id": run_id, "user_id": USER_ID,
			"item_id": "food_basic", "quantity": food_qty, "granted_at": ts,
		})

	# rare drop
	if tier >= 3 and _chance(tier * 3.0):
		var rare: String = _pick(RARE_ITEMS)
		_add_inventory(e_base, rare, 1)
		rewards.append({
			"id": _uid(), "run_id": run_id, "user_id": USER_ID,
			"item_id": rare, "quantity": 1, "granted_at": ts, "type": "rare",
		})

	# ship part drop
	if tier >= 5 and _chance(tier * 2.0):
		var part: String = _pick(SHIP_PARTS)
		_add_ship_part(part, 1)
		rewards.append({
			"id": _uid(), "run_id": run_id, "user_id": USER_ID,
			"item_id": part, "quantity": 1, "granted_at": ts, "type": "ship_part",
		})

	# combat XP
	var xp_pool := int(floorf(base_xp * mult * factor))
	var combat_used: Array[String] = []
	for s in _run_choice_skills:
		if s in COMBAT_SKILLS and not s in combat_used:
			combat_used.append(s)
	if combat_used.is_empty():
		combat_used = COMBAT_SKILLS.duplicate()
	var xp_each := xp_pool / combat_used.size()
	for sk in combat_used:
		_grant_combat_xp(sk, xp_each)

	# tier progression
	if outcome == "success" and tier > int(_player_state.highest_dungeon_tier):
		_player_state.highest_dungeon_tier = tier

	_active_run.status = "success" if outcome == "success" else "failure"
	_active_run.completed_at = ts
	_player_state.updated_at = ts

	var _finished := _active_run.duplicate(true)
	_active_run = {}
	_run_choice_skills.clear()

	return {"rewards": rewards, "snapshot": _build_snapshot()}
