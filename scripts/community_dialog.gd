class_name CommunityDialog
extends Control

signal confirmed
signal canceled
var body: VBoxContainer
var actions: HBoxContainer
var confirm_button: Button
var cancel_button: Button
var panel: PanelContainer
var veil: ColorRect
var center: CenterContainer
var right_docked := false
var title_label: Label
var busy := false
var heading := ""
var confirm_text := "Publish"
var cancel_text := "Cancel"
var panel_color := Color("141e28")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	veil = ColorRect.new()
	veil.color = Color(0.015, 0.025, 0.035, 0.72)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 360
	panel.add_theme_stylebox_override("panel", surface(panel_color))
	center.add_child(panel)
	var margins := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	margins.add_child(layout)
	if not heading.is_empty():
		title_label = Label.new()
		title_label.name = "DialogTitle"
		title_label.text = heading
		title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_label.add_theme_font_size_override("font_size", 26)
		layout.add_child(title_label)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	layout.add_child(body)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(actions)
	cancel_button = Button.new()
	cancel_button.text = cancel_text
	cancel_button.visible = not cancel_text.is_empty()
	cancel_button.pressed.connect(dismiss)
	actions.add_child(cancel_button)
	confirm_button = Button.new()
	confirm_button.text = confirm_text
	confirm_button.theme_type_variation = "PrimaryButton"
	confirm_button.pressed.connect(func():
		if not busy:
			confirmed.emit()
	)
	actions.add_child(confirm_button)
	modulate.a = 0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

static func surface(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(22)
	style.set_border_width_all(1)
	style.border_color = color.lightened(0.22)
	style.shadow_color = Color(0, 0, 0, 0.32)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	return style

func set_busy(value: bool) -> void:
	busy = value
	confirm_button.disabled = value
	cancel_button.disabled = value
	confirm_button.text = "Uploading…" if value else confirm_text

func dock_right() -> void:
	right_docked = true
	center.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	center.offset_left = -408
	center.offset_right = -24

func dismiss() -> void:
	if not busy:
		canceled.emit()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		dismiss()
