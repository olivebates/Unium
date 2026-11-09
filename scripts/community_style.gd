class_name CommunityStyle
extends RefCounted

const ACCENT_HUE := 28.0 / 360.0

static func accent(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := button.get_theme_stylebox(state, "Button").duplicate() as StyleBoxFlat
		var reference := style.bg_color
		style.bg_color = PuzzleBoard.balanced_color(ACCENT_HUE, reference.s, PuzzleBoard.luminance(reference))
		button.add_theme_stylebox_override(state, style)
