extends Control

# One screen-owned effect: leaving the victory screen stops emission and frees it.
var rockets: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var launch_in := 0.0
var launched := 0
var exploded := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	rng.randomize()

func _launch() -> void:
	var hue := rng.randf()
	rockets.append({
		"start": Vector2(size.x * rng.randf_range(0.08, 0.92), size.y + 12.0),
		"target": Vector2(size.x * rng.randf_range(0.12, 0.88), size.y * rng.randf_range(0.12, 0.52)),
		"age": 0.0, "duration": rng.randf_range(1.15, 1.85),
		"color": Color.from_hsv(hue, 0.6, 1.0), "hue": hue,
	})
	launched += 1

func _burst(rocket: Dictionary) -> void:
	var radius := minf(size.x, size.y) * rng.randf_range(0.18, 0.29)
	var phase := rng.randf() * TAU
	# Three overlapping rings blossom into a bouquet, with contrasting hues.
	for ring in range(3):
		var count := 36 + ring * 8
		var hue := fposmod(rocket.hue + ring * 0.19, 1.0)
		for index in range(count):
			var angle := phase + TAU * index / count + rng.randf_range(-0.035, 0.035)
			var velocity := Vector2.from_angle(angle) * radius * (0.48 + ring * 0.25) * rng.randf_range(0.85, 1.12)
			sparks.append({
				"position": rocket.target, "velocity": velocity, "age": 0.0,
				"life": rng.randf_range(1.8, 2.9), "radius": rng.randf_range(1.3, 2.5),
				"color": Color.from_hsv(fposmod(hue + rng.randf_range(-0.045, 0.045), 1.0), 0.65, 1.0),
			})
	exploded += 1

func _rocket_position(rocket: Dictionary, age: float) -> Vector2:
	var progress := clampf(age / rocket.duration, 0.0, 1.0)
	return rocket.start.lerp(rocket.target, 1.0 - pow(1.0 - progress, 2.0))

func _process(delta: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	launch_in -= delta
	if launch_in <= 0.0:
		_launch()
		launch_in = rng.randf_range(0.45, 0.8)
	for index in range(rockets.size() - 1, -1, -1):
		var rocket := rockets[index]
		rocket.age += delta
		if rocket.age >= rocket.duration:
			_burst(rocket)
			rockets.remove_at(index)
	for index in range(sparks.size() - 1, -1, -1):
		var spark := sparks[index]
		spark.age += delta
		if spark.age >= spark.life:
			sparks.remove_at(index)
			continue
		spark.velocity *= exp(-0.65 * delta)
		spark.velocity.y += size.y * 0.085 * delta
		spark.position += spark.velocity * delta
	queue_redraw()

func _draw() -> void:
	for rocket in rockets:
		var tip := _rocket_position(rocket, rocket.age)
		for segment in range(8):
			var age: float = rocket.age - segment * 0.025
			var tail := _rocket_position(rocket, maxf(0.0, age - 0.025))
			draw_line(tail, _rocket_position(rocket, maxf(0.0, age)), Color(rocket.color, (1.0 - segment / 8.0) * 0.8), 2.0, true)
		draw_circle(tip, 5.0, Color(rocket.color, 0.14))
		draw_circle(tip, 2.0, Color.WHITE)
	for spark in sparks:
		var alpha := pow(maxf(0.0, 1.0 - spark.age / spark.life), 0.7)
		var point: Vector2 = spark.position
		draw_circle(point, spark.radius * 3.0, Color(spark.color, alpha * 0.07))
		draw_line(point - spark.velocity * 0.035, point, Color(spark.color, alpha * 0.7), spark.radius, true)
		draw_circle(point, spark.radius, Color(spark.color, alpha))
