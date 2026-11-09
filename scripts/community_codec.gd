class_name CommunityCodec
extends RefCounted

# HL1: two bits per tile, UTF-8 metadata, zlib, AES-256-CBC, base64url.
# The shared format key provides portable encrypted saves, not ownership proof.
# Ownership is authenticated separately by a random browser capability.
const KEY_TEXT := "Hearthline/community/portable-save/v1"
const MAX_RAW := 1048576
const MAX_EVENTS := 20000

static func _varint(bytes: PackedByteArray, value: int) -> void:
	while value >= 128:
		bytes.append((value & 127) | 128)
		value >>= 7
	bytes.append(value)

static func _read_varint(bytes: PackedByteArray, cursor: Array) -> int:
	var value := 0
	for shift in range(0, 35, 7):
		if cursor[0] >= bytes.size():
			cursor[0] = bytes.size() + 1
			return -1
		var byte := int(bytes[cursor[0]])
		cursor[0] += 1
		value |= (byte & 127) << shift
		if byte < 128:
			return value
	return -1

static func _string(bytes: PackedByteArray, value: String) -> void:
	var utf8 := value.to_utf8_buffer()
	_varint(bytes, utf8.size())
	bytes.append_array(utf8)

static func _read_string(bytes: PackedByteArray, cursor: Array, limit: int) -> String:
	var length := _read_varint(bytes, cursor)
	if length < 0 or length > limit or cursor[0] + length > bytes.size():
		cursor[0] = bytes.size() + 1
		return ""
	var value := bytes.slice(cursor[0], cursor[0] + length).get_string_from_utf8()
	cursor[0] += length
	return value

static func valid_layout(value: Dictionary) -> bool:
	for key in ["width", "height"]:
		if not (value.get(key) is int or value.get(key) is float):
			return false
		if int(value[key]) != value[key] or int(value[key]) < 1 or int(value[key]) > 32:
			return false
	if not value.get("tiles") is Array or value.tiles.size() != int(value.width) * int(value.height):
		return false
	for tile in value.tiles:
		if not (tile is int or tile is float) or int(tile) != tile or int(tile) < 0 or int(tile) > 2:
			return false
	return true

static func encode_level(level: Dictionary) -> String:
	if not valid_layout(level):
		return ""
	var bytes := PackedByteArray([1, int(level.width), int(level.height)])
	var color := Color(str(level.get("color", "a9dfcc")))
	bytes.append_array(PackedByteArray([color.r8, color.g8, color.b8]))
	_string(bytes, str(level.get("name", "")).left(80))
	_string(bytes, str(level.get("author", "")).left(48))
	for start in range(0, level.tiles.size(), 4):
		var packed := 0
		for offset in range(mini(4, level.tiles.size() - start)):
			packed |= int(level.tiles[start + offset]) << (offset * 2)
		bytes.append(packed)
	return _seal(bytes, "HL1.")

static func decode_level(value: String) -> Dictionary:
	var bytes := _open(value, "HL1.")
	if bytes.size() < 9 or bytes[0] != 1:
		return {}
	var width := int(bytes[1])
	var height := int(bytes[2])
	if width < 1 or width > 32 or height < 1 or height > 32:
		return {}
	var cursor := [6]
	var level := {"width": width, "height": height, "color": Color8(bytes[3], bytes[4], bytes[5]).to_html(false)}
	level.name = _read_string(bytes, cursor, 320)
	level.author = _read_string(bytes, cursor, 192)
	if cursor[0] + ceili(width * height / 4.0) != bytes.size():
		return {}
	var tiles: Array = []
	for cell in range(width * height):
		var tile := (bytes[cursor[0] + int(cell / 4)] >> ((cell % 4) * 2)) & 3
		if tile == 3:
			return {}
		tiles.append(tile)
	level.tiles = tiles
	return level

# Replay events are [delta_ms, cell]; -1 means undo, -2 means reset.
static func encode_replay(events: Array) -> String:
	if events.size() > MAX_EVENTS:
		return ""
	var bytes := PackedByteArray([1])
	_varint(bytes, events.size())
	for event in events:
		_varint(bytes, clampi(int(event[0]), 0, 5000))
		_varint(bytes, int(event[1]) + 2)
	return _seal(bytes, "HR1.")

static func decode_replay(value: String, area: int) -> Array:
	var bytes := _open(value, "HR1.")
	if bytes.size() < 2 or bytes[0] != 1:
		return []
	var cursor := [1]
	var count := _read_varint(bytes, cursor)
	if count < 1 or count > MAX_EVENTS:
		return []
	var events: Array = []
	for index in range(count):
		var delay := _read_varint(bytes, cursor)
		var cell := _read_varint(bytes, cursor) - 2
		if delay < 0 or delay > 5000 or cell < -2 or cell >= area:
			return []
		events.append([delay, cell])
	return events if cursor[0] == bytes.size() else []

static func _seal(raw: PackedByteArray, prefix: String) -> String:
	var compressed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var payload := PackedByteArray()
	payload.resize(4)
	payload.encode_u32(0, raw.size())
	payload.append_array(compressed)
	var padding := 16 - payload.size() % 16
	for index in range(padding):
		payload.append(padding)
	var iv := Crypto.new().generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, KEY_TEXT.sha256_buffer(), iv)
	var encrypted := aes.update(payload)
	aes.finish()
	iv.append_array(encrypted)
	return prefix + Marshalls.raw_to_base64(iv).replace("+", "-").replace("/", "_").replace("=", "")

static func _open(value: String, prefix: String) -> PackedByteArray:
	value = value.strip_edges()
	if not value.begins_with(prefix) or value.length() > 100000:
		return PackedByteArray()
	var encoded := value.substr(prefix.length()).replace("-", "+").replace("_", "/")
	while encoded.length() % 4:
		encoded += "="
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.size() < 32 or bytes.size() % 16 != 0:
		return PackedByteArray()
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, KEY_TEXT.sha256_buffer(), bytes.slice(0, 16))
	var payload := aes.update(bytes.slice(16))
	aes.finish()
	var padding := int(payload[-1])
	if padding < 1 or padding > 16:
		return PackedByteArray()
	for index in range(payload.size() - padding, payload.size()):
		if payload[index] != padding:
			return PackedByteArray()
	payload.resize(payload.size() - padding)
	if payload.size() < 5:
		return PackedByteArray()
	var length := payload.decode_u32(0)
	if length < 1 or length > MAX_RAW:
		return PackedByteArray()
	var raw := payload.slice(4).decompress(length, FileAccess.COMPRESSION_DEFLATE)
	return raw if raw.size() == length else PackedByteArray()
