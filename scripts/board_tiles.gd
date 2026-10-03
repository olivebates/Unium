extends Node2D

# Keep cached tile draw commands outside Control's theme invalidation path.
# Position/scale/opacity transitions then reuse these commands unchanged.
var paint: Callable

func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
