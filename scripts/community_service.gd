class_name CommunityService
extends Node

const ENDPOINT := "https://different-ostrich-580.convex.site/community"
const IDENTITY_PATH := "user://community_identity.cfg"
var token := ""
var owned: Array = []
var custom_levels_notice_seen := false
var publish_available_at_ms := 0.0

func _ready() -> void:
	var config := ConfigFile.new()
	config.load(IDENTITY_PATH)
	token = str(config.get_value("identity", "token", ""))
	owned = config.get_value("identity", "owned", [])
	custom_levels_notice_seen = bool(config.get_value("preferences", "custom_levels_notice_seen", false))
	publish_available_at_ms = float(config.get_value("publishing", "available_at_ms", 0))
	if OS.has_feature("web"):
		var publish_time: Variant = JavaScriptBridge.eval("(() => { try { return Number(localStorage.getItem('hearthline_publish_available_at') || 0); } catch (_) { return 0; } })()")
		if publish_time is float or publish_time is int:
			publish_available_at_ms = maxf(publish_available_at_ms, float(publish_time))
		var notice_seen: Variant = JavaScriptBridge.eval("(() => { try { return localStorage.getItem('hearthline_custom_levels_notice_seen') === '1'; } catch (_) { return false; } })()")
		# Web builds can return a JavaScript boolean as an integer Variant.
		custom_levels_notice_seen = custom_levels_notice_seen or bool(notice_seen)
		var cookie: Variant = JavaScriptBridge.eval("(() => { try { return document.cookie.split('; ').find(s => s.startsWith('hearthline_owner='))?.split('=')[1] || ''; } catch (_) { return ''; } })()")
		if cookie is String and cookie.length() == 64 and cookie.is_valid_hex_number(false):
			token = cookie
		var ids: Variant = JavaScriptBridge.eval("(() => { try { return decodeURIComponent(document.cookie.split('; ').find(s => s.startsWith('hearthline_levels='))?.split('=')[1] || '%5B%5D'); } catch (_) { return '[]'; } })()")
		if ids is String:
			var parsed: Variant = JSON.parse_string(ids)
			if parsed is Array:
				owned = parsed
	if token.length() != 64 or not token.is_valid_hex_number(false):
		token = Crypto.new().generate_random_bytes(32).hex_encode()
	_save_identity()

func _save_identity() -> void:
	var config := ConfigFile.new()
	config.set_value("identity", "token", token)
	config.set_value("identity", "owned", owned)
	config.set_value("preferences", "custom_levels_notice_seen", custom_levels_notice_seen)
	config.set_value("publishing", "available_at_ms", publish_available_at_ms)
	config.save(IDENTITY_PATH)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('hearthline_publish_available_at', '" + str(publish_available_at_ms) + "'); } catch (_) {}")
		if custom_levels_notice_seen:
			JavaScriptBridge.eval("try { localStorage.setItem('hearthline_custom_levels_notice_seen', '1'); } catch (_) {}")
		JavaScriptBridge.eval("try { document.cookie = 'hearthline_owner=" + token + "; Max-Age=31536000; Path=/; SameSite=Lax; Secure'; } catch (_) {}")
		# Ownership itself is the token. IDs only control owner buttons locally.
		var ids := JSON.stringify(owned.slice(maxi(0, owned.size() - 80)))
		JavaScriptBridge.eval("try { document.cookie = 'hearthline_levels=' + encodeURIComponent(" + JSON.stringify(ids) + ") + '; Max-Age=31536000; Path=/; SameSite=Lax; Secure'; } catch (_) {}")

func remember_custom_levels_notice() -> void:
	custom_levels_notice_seen = true
	_save_identity()

func publish_remaining_ms() -> int:
	return maxi(0, ceili(publish_available_at_ms - Time.get_unix_time_from_system() * 1000))

func remember_publish_cooldown(remaining_ms: int) -> void:
	publish_available_at_ms = maxf(publish_available_at_ms, Time.get_unix_time_from_system() * 1000 + maxi(0, remaining_ms))
	_save_identity()

func request(action: String, args: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.body_size_limit = 2097152
	add_child(http)
	var payload := args.duplicate(true)
	payload.action = action
	payload.token = token
	var error := http.request(ENDPOINT, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		http.queue_free()
		return {"error": "Connection failed"}
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Connection failed"}
	var parsed: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if parsed is Dictionary and parsed.has("retryAfterMs"):
		remember_publish_cooldown(int(parsed.retryAfterMs))
	if response[1] < 200 or response[1] >= 300 or not parsed is Dictionary:
		if parsed is Dictionary and parsed.has("error"):
			return parsed
		return {"error": str(parsed.get("error", "Community server unavailable")) if parsed is Dictionary else "Community server unavailable"}
	if parsed.get("error"):
		return parsed
	if action == "list" and parsed.get("owned") is Array:
		owned = parsed.owned
		_save_identity()
	if action == "publish" and parsed.has("id") and not owned.has(parsed.id):
		owned.append(parsed.id)
		_save_identity()
	if action == "delete":
		owned.erase(args.get("id"))
		_save_identity()
	return parsed
