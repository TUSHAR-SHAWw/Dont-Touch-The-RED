extends Node2D

const DangerZone := preload("res://scripts/DangerZone.gd")
const SpikeBall := preload("res://scripts/SpikeBall.gd")
## Spawns danger zones on an interval using a set of random patterns.
## Every pattern always leaves at least one safe spot, so the game stays fair.

signal danger_spawned(zone)
signal danger_died

## Difficulty knobs (level tuning happens here, exposed for later scaling).
@export var spawn_interval := 2.2
@export var warning_time := 1.2
@export var active_time := 2.0

var running := false
var player: Node2D
var elapsed := 0.0
var mode := 0
var _run_generation := 0
@onready var tuning := get_node("../GameTuning")

var _fair_cache_result := false
var _fair_cache_elapsed := -1.0

# Arena half-size (matches the Arena node, +-400/+-300 around the origin).
var _arena_half := Vector2(400, 300)

func _pattern_spike_ball() -> bool:

	var half := _arena_half

	var margin := 40.0

	var spawn_position := Vector2(
		randf_range(-half.x + margin, half.x - margin),
		randf_range(-half.y + margin, half.y - margin)
	)

	# Don't spawn directly on the player
	if is_instance_valid(player):

		if spawn_position.distance_to(player.global_position) < 130.0:
			return false

	var direction := Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()

	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	var ball := SpikeBall.new()

	ball.setup(
		spawn_position,
		direction,
		180.0,
		warning_time,
		3.0
	)

	ball.arena_rect = Rect2(
		-_arena_half,
		_arena_half * 2.0
	)

	add_child(ball)

	danger_spawned.emit(ball)

	return true

func start(p: Node2D, selected_mode := 0) -> void:
	_run_generation += 1
	player = p
	mode = selected_mode
	elapsed = 0.0
	running = true
	spawn_interval = tuning.danger_spawn_interval
	warning_time = tuning.danger_warning_time
	active_time = tuning.danger_active_time
	if mode == 1:
		spawn_interval *= tuning.rush_spawn_multiplier
		warning_time *= tuning.rush_warning_multiplier
		active_time *= tuning.rush_active_multiplier
	elif mode == 2:
		spawn_interval *= tuning.zen_spawn_multiplier
		warning_time *= tuning.zen_warning_multiplier
		active_time *= tuning.zen_active_multiplier
	_schedule(_run_generation)

func stop() -> void:
	_run_generation += 1
	running = false
	elapsed = 0.0
	for child in get_children():
		if child is DangerZone:
			child.queue_free()

func _process(delta: float) -> void:
	if running:
		elapsed += delta


func _schedule(generation: int) -> void:
	if not running or generation != _run_generation:
		return
	var interval := maxf(tuning.danger_min_spawn_interval, spawn_interval - elapsed * tuning.danger_spawn_acceleration)
	if mode == 1:
		interval = maxf(tuning.danger_min_spawn_interval * 0.7, interval)
	elif mode == 2:
		interval = maxf(tuning.danger_min_spawn_interval, interval)
	await get_tree().create_timer(interval, false).timeout
	if not running or generation != _run_generation:
		return
	_spawn_random_pattern()
	_schedule(generation)


func _spawn_random_pattern() -> void:
	if elapsed >= tuning.idle_pressure_start and is_instance_valid(player) and player.velocity.length() < 10.0:
		_pattern_player_pressure()
		return
	var patterns: Array[Callable] = [
	_pattern_side_rect,
	_pattern_strip,
	_pattern_expand,
	_pattern_spike_ball,
	_pattern_zigzag,
	_pattern_pinwheel
]
	if elapsed >= tuning.idle_pressure_start:
		patterns.append(_pattern_player_pressure)
	if mode != 2:
		patterns.append(_pattern_spikes)
	if mode == 1 or (mode == 0 and elapsed >= 18.0) or (mode == 2 and elapsed >= 45.0):
		patterns.append(_pattern_moving_wall)
	var cross_time := 6.0 if mode == 1 else (30.0 if mode == 2 else 12.0)
	var double_time := 12.0 if mode == 1 else (60.0 if mode == 2 else 24.0)
	var corner_time := 24.0 if mode == 1 else (90.0 if mode == 2 else 40.0)
	if elapsed >= cross_time:
		patterns.append(_pattern_cross)
	if elapsed >= double_time:
		patterns.append(_pattern_double_sides)
	if elapsed >= corner_time:
		patterns.append(_pattern_corner_pair)
	var shuffled := patterns.duplicate()
	shuffled.shuffle()
	for pattern in shuffled:
		if pattern.call():
			return

func _is_pattern_fair(rects: Array[Rect2]) -> bool:
	if rects.is_empty():
		return false
	if elapsed - _fair_cache_elapsed < 0.1:
		return _fair_cache_result
	var hazards := rects.duplicate()
	for child in get_children():
		if child is DangerZone and child.is_active():
			hazards.append(child.get_danger_rect())

	var player_position := player.global_position if is_instance_valid(player) else Vector2.ZERO
	for rect in rects:
		if rect.grow(16.0).has_point(player_position):
			_fair_cache_result = false
			_fair_cache_elapsed = elapsed
			return false

	var safe_points := 0
	for y in range(-3, 4):
		for x in range(-4, 5):
			var point := Vector2(x * _arena_half.x / 4.0, y * _arena_half.y / 3.0)
			var safe := true
			for hazard in hazards:
				if hazard.grow(16.0).has_point(point):
					safe = false
					break
			if safe:
				safe_points += 1
	_fair_cache_result = safe_points >= 3
	_fair_cache_elapsed = elapsed
	return _fair_cache_result

func _spawn_rects(rects: Array[Rect2]) -> bool:
	if not _is_pattern_fair(rects):
		return false
	for rect in rects:
		_spawn_zone(rect)
	return true

func _spawn_zone(rect: Rect2, target := Vector2.ZERO, grow := 0.0) -> void:
	_spawn_zone_as(rect, target, grow, DangerZone.Kind.RECTANGLE)

func _spawn_zone_as(rect: Rect2, target: Vector2, grow: float, kind: int, axis := Vector2.ZERO, motion_range := 0.0) -> void:
	var zone := DangerZone.new()
	var warn := warning_time
	if mode == 2:
		warn += 0.3
	zone.setup(rect.size, target, warn, active_time, grow, kind, axis, motion_range)
	zone.position = rect.get_center()
	zone.motion_origin = zone.position
	add_child(zone)
	danger_spawned.emit(zone)

# ---------------------------------------------------------------------------
# Patterns: each returns a Rect2 in world space (arena centred on the origin).
# ---------------------------------------------------------------------------

func _pattern_side_rect() -> bool:
	return _spawn_rects([_random_side_rect()])

func _pattern_player_pressure() -> bool:
	if not is_instance_valid(player):
		return false
	var pressure_size := Vector2(tuning.idle_pressure_size, tuning.idle_pressure_size)
	var rect := Rect2(player.global_position - pressure_size / 2.0, pressure_size)
	_spawn_zone(rect)
	return true

func _random_side_rect() -> Rect2:
	var side := randi_range(0, 3)
	var half := _arena_half
	match side:
		0:  # left
			var w := half.x * randf_range(0.45, 0.6)
			return Rect2(Vector2(-half.x, -half.y), Vector2(w, half.y * 2.0))
		1:  # right
			var w := half.x * randf_range(0.45, 0.6)
			return Rect2(Vector2(half.x - w, -half.y), Vector2(w, half.y * 2.0))
		2:  # top
			var h := half.y * randf_range(0.45, 0.6)
			return Rect2(Vector2(-half.x, -half.y), Vector2(half.x * 2.0, h))
		_:  # bottom
			var h := half.y * randf_range(0.45, 0.6)
			return Rect2(Vector2(-half.x, half.y - h), Vector2(half.x * 2.0, h))

func _pattern_strip() -> bool:
	return _spawn_rects([_random_strip()])

func _random_strip() -> Rect2:
	var vertical := randf() < 0.5
	var half := _arena_half
	if vertical:
		var thickness := randf_range(half.x * 0.25, half.x * 0.4)
		var x := randf_range(-half.x, half.x - thickness)
		return Rect2(Vector2(x, -half.y), Vector2(thickness, half.y * 2.0))
	else:
		var thickness := randf_range(half.y * 0.25, half.y * 0.4)
		var y := randf_range(-half.y, half.y - thickness)
		return Rect2(Vector2(-half.x, y), Vector2(half.x * 2.0, thickness))

func _pattern_expand() -> bool:
	var half := _arena_half
	var start := Vector2(half.x * 0.08, half.y * 0.08)
	var target := Vector2(half.x * 0.9, half.y * 0.9)
	var center := Vector2(randf_range(-half.x * 0.15, half.x * 0.15), randf_range(-half.y * 0.15, half.y * 0.15))
	var rect := Rect2(center - start / 2.0, start)
	var grow_speed := target.distance_to(start) / active_time
	if not _is_pattern_fair([Rect2(center - target / 2.0, target)]):
		return false
	_spawn_zone(rect, target, grow_speed)
	return true

func _pattern_spikes() -> bool:
	var rect := _random_side_rect()
	if not _is_pattern_fair([rect]):
		return false
	_spawn_zone_as(rect, Vector2.ZERO, 0.0, DangerZone.Kind.SPIKES)
	return true

func _pattern_moving_wall() -> bool:
	var half := _arena_half
	var vertical := randf() < 0.5
	var axis := Vector2.RIGHT if vertical else Vector2.DOWN
	var size := Vector2(half.x * 0.14, half.y * 2.0) if vertical else Vector2(half.x * 2.0, half.y * 0.14)
	var start := Vector2(randf_range(-half.x * 0.45, half.x * 0.45), 0.0) if vertical else Vector2(0.0, randf_range(-half.y * 0.45, half.y * 0.45))
	var rect := Rect2(start - size / 2.0, size)
	var sweep := rect.grow_individual(170.0 if vertical else 0.0, 0.0 if vertical else 130.0, 170.0 if vertical else 0.0, 0.0 if vertical else 130.0)
	if not _is_pattern_fair([sweep]):
		return false
	_spawn_zone_as(rect, Vector2.ZERO, 0.0, DangerZone.Kind.MOVING_WALL, axis, 170.0 if vertical else 130.0)
	return true

func _pattern_cross() -> bool:
	var half := _arena_half
	var vertical_width := half.x * 0.22
	var horizontal_height := half.y * 0.22
	var offset := randf_range(-half.x * 0.18, half.x * 0.18)
	var vertical := Rect2(Vector2(offset - vertical_width / 2.0, -half.y), Vector2(vertical_width, half.y * 2.0))
	var horizontal := Rect2(Vector2(-half.x, -horizontal_height / 2.0), Vector2(half.x * 2.0, horizontal_height))
	return _spawn_rects([vertical, horizontal])

func _pattern_double_sides() -> bool:
	var half := _arena_half
	var width := half.x * 0.25
	var gap_offset := randf_range(-half.y * 0.16, half.y * 0.16)
	var top := Rect2(Vector2(-half.x, -half.y), Vector2(half.x * 2.0, half.y * 0.28))
	var bottom := Rect2(Vector2(-half.x, half.y - half.y * 0.28), Vector2(half.x * 2.0, half.y * 0.28))
	top.position.y += gap_offset
	bottom.position.y += gap_offset
	return _spawn_rects([top, bottom])

func _pattern_corner_pair() -> bool:
	var half := _arena_half
	var corner_size := Vector2(half.x * 0.42, half.y * 0.38)
	var left := Rect2(Vector2(-half.x, -half.y), corner_size)
	var right := Rect2(Vector2(half.x - corner_size.x, half.y - corner_size.y), corner_size)
	return _spawn_rects([left, right])

func _pattern_zigzag() -> bool:
	var half := _arena_half
	var bar_size := Vector2(half.x * 0.34, half.y * 0.18)
	var bars: Array[Rect2] = []
	for i in range(3):
		var x := -half.x + (half.x * 0.56 if i % 2 == 0 else half.x * 0.10)
		var y := -half.y * 0.72 + i * half.y * 0.72
		bars.append(Rect2(Vector2(x, y), bar_size))
	var player_position := player.global_position if is_instance_valid(player) else Vector2.ZERO
	for rect in bars:
		if rect.grow(16.0).has_point(player_position):
			return false
	for rect in bars:
		_spawn_zone_as(rect, Vector2.ZERO, 0.0, DangerZone.Kind.ZIGZAG)
	return true

func _pattern_pinwheel() -> bool:
	var half := _arena_half
	var arm_width := half.x * 0.16
	var arm_length := half.x * 0.62
	var rects: Array[Rect2] = [
		Rect2(Vector2(-arm_length / 2.0, -arm_width / 2.0), Vector2(arm_length, arm_width)),
		Rect2(Vector2(-arm_width / 2.0, -arm_length / 2.0), Vector2(arm_width, arm_length))
	]
	return _spawn_rects_as(rects, DangerZone.Kind.PINWHEEL)

func _spawn_rects_as(rects: Array[Rect2], kind: int) -> bool:
	if not _is_pattern_fair(rects):
		return false
	for rect in rects:
		_spawn_zone_as(rect, Vector2.ZERO, 0.0, kind)
	return true
