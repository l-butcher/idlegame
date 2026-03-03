## Supabase RPC backend — drop-in replacement for MockBackend.
## Calls POST /rest/v1/rpc/<function_name> against a live Supabase instance.
class_name SupabaseBackend
extends Backend

var supabase_url: String
var anon_key: String
var access_token: String = ""

# Held reference so the HTTPRequest node isn't freed mid-flight.
var _http_parent: Node = null


func _init(url: String, key: String, parent: Node) -> void:
	supabase_url = url.rstrip("/")
	anon_key = key
	_http_parent = parent


# ── auth helpers ─────────────────────────────────────────────

# TODO: add sign_in_with_password(email, password) -> sets access_token
# TODO: add sign_up(email, password) -> sets access_token
# TODO: add refresh_token() for session keep-alive
# TODO: add sign_out() to clear access_token

func set_access_token(token: String) -> void:
	access_token = token


func _build_headers() -> PackedStringArray:
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % anon_key,
		"Prefer: return=representation",
	])
	if access_token != "":
		headers.append("Authorization: Bearer %s" % access_token)
	return headers


# ── HTTP transport ───────────────────────────────────────────

func _post_json(function_name: String, body: Dictionary = {}) -> Dictionary:
	var url := "%s/rest/v1/rpc/%s" % [supabase_url, function_name]
	var json_body := JSON.stringify(body)

	var http := HTTPRequest.new()
	_http_parent.add_child(http)

	var err := http.request(url, _build_headers(), HTTPClient.METHOD_POST, json_body)
	if err != OK:
		push_error("HTTPRequest.request failed for %s: %d" % [function_name, err])
		http.queue_free()
		return {}

	var response: Array = await http.request_completed
	http.queue_free()

	var result_code: int = response[0]
	var http_code: int = response[1]
	var _resp_headers: PackedStringArray = response[2]
	var resp_body: PackedByteArray = response[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		push_error("RPC %s network error: result_code=%d" % [function_name, result_code])
		return {}

	var text := resp_body.get_string_from_utf8()

	if http_code < 200 or http_code >= 300:
		push_error("RPC %s HTTP %d: %s" % [function_name, http_code, text])
		return {}

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		push_error("RPC %s JSON parse error: %s" % [function_name, json.get_error_message()])
		return {}

	var data: Variant = json.data
	if data is Dictionary:
		return data as Dictionary
	if data is Array:
		return {"_array": data}

	push_error("RPC %s unexpected response type: %s" % [function_name, typeof(data)])
	return {}


# ── RPC implementations ─────────────────────────────────────

func bootstrap_player() -> Dictionary:
	return await _post_json("rpc_bootstrap_player")


func get_player_snapshot() -> Dictionary:
	return await _post_json("rpc_get_player_snapshot")


func claim_all(base_type: Variant) -> Dictionary:
	var body := {}
	body["p_base_type"] = base_type
	return await _post_json("rpc_claim_all", body)


func start_dungeon_run(tier: int) -> Dictionary:
	return await _post_json("rpc_start_dungeon_run", {"p_tier": tier})


func submit_run_choice(run_id: String, choice_key: String, skills_used: Array) -> Dictionary:
	return await _post_json("rpc_submit_run_choice", {
		"p_run_id": run_id,
		"p_choice_key": choice_key,
		"p_skills_used": skills_used,
	})


func submit_multiplier(run_id: String, multiplier: float, source: String) -> Dictionary:
	return await _post_json("rpc_submit_multiplier", {
		"p_run_id": run_id,
		"p_multiplier": multiplier,
		"p_source": source,
	})


func complete_dungeon_run(run_id: String, outcome: String) -> Dictionary:
	return await _post_json("rpc_complete_dungeon_run", {
		"p_run_id": run_id,
		"p_outcome": outcome,
	})
