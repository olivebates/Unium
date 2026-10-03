extends Button

signal drag_pressed(source: int, pointer: Vector2)

var level_number := 0
var rearranging := false

func _ready() -> void:
	gui_input.connect(_on_rearrange_input)

func _on_rearrange_input(event: InputEvent) -> void:
	if rearranging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		drag_pressed.emit(level_number, get_global_mouse_position())
		accept_event()
