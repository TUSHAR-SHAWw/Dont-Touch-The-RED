extends Node2D

## Spawns danger zones on an interval using a set of random patterns.
## Every pattern always leaves at least one safe spot, so the game stays fair.

const DangerZone := preload("res://scripts/DangerZone.gd")
const SpikeBall := preload("res://scripts/SpikeBall.gd")

## Extra clearance around a hazard when checking the player / safe points.
const SAFE_MARGIN := 16.0
## A pattern needs at least this many safe sample points to be allowed.
const SAFE_POINTS_REQUIRED := 3
const LASER_THICKNESS := 28.0

## Patterns unlock one at a time as the run goes on: [method name, seconds].
## Times are for Normal mode; Rush and Zen scale them like the stage times.
const PATTERN_UNLOCKS := [
	[&"_pattern_side_rect", 0.0],
	[&"_pattern_strip", 0.0],
	[&"_pattern_expand", 10.0],
	[&"_pattern_bombs", 20.0],
	[&"_pattern_spike_ball", 30.0],
	[&"_pattern_spikes", 38.0],
	# Stage 1 (45s)
	[&"_pattern_cross", 45.0],
	[&"_pattern_zigzag", 55.0],
	[&"_pattern_moving_wall", 60.0],
	[&"_pattern_laser_snipe", 65.0],
	[&"_pattern_pinwheel", 72.0],
	# Stage 2 (90s)
	[&"_pattern_double_sides", 90.0],
	[&"_pattern_crusher", 100.0],
	[&"_pattern_laser_barrage", 112.0],
	# Stage 3 (140s)
	[&"_pattern_corner_pair", 140.0],
	[&"_pattern_sweeper", 152.0],
	[&"_pattern_checkerboard", 168.0],
]

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

# Arena half-size. Read from the Arena node in _ready (default 400/300).
var _arena_half := Vector2(400, 300)


func _ready() -> void:
	var arena := get_node_or_null("../Arena")
	if arena and arena.has_method("get_bounds"):
		_arena_half = arena.get_bounds().size / 2.0


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
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for child in get_children():
		if child is DangerZone or child is SpikeBall:
			child.queue_free()


## Freezes everything in place (used while the revive prompt is open).
## Hazards stay visible but stop moving, and no new patterns spawn.
func suspend() -> void:
	_run_generation += 1
	running = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Continues a suspended run: all hazards fade out and spawning restarts
## after `extra_delay` seconds. The difficulty clock keeps its value.
func resume(extra_delay := 1.5) -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	clear_hazards()
	_run_generation += 1
	running = true
	_schedule(_run_generation, extra_delay)


## Fades out every hazard that is currently alive.
func clear_hazards() -> void:
	for child in get_children():
		if (child is DangerZone or child is SpikeBall) and child.has_method("dismiss"):
			child.dismiss()


func _process(delta: float) -> void:
	if running:
		elapsed += delta


func _schedule(generation: int, initial_delay := 0.0) -> void:
	if initial_delay > 0.0:
		await get_tree().create_timer(initial_delay, false).timeout
		if not running or generation != _run_generation:
			return
	while running and generation == _run_generation:
		var interval := maxf(tuning.danger_min_spawn_interval, spawn_interval - elapsed * tuning.danger_spawn_acceleration)
		if mode == 1:
			interval = maxf(tuning.danger_min_spawn_interval * 0.7, interval)
		await get_tree().create_timer(interval, false).timeout
		if not running or generation != _run_generation:
			return
		_spawn_random_pattern()


func _spawn_random_pattern() -> void:
	var idle: bool = is_instance_valid(player) and player.velocity.length() < 10.0
	if elapsed >= tuning.idle_pressure_start and idle:
		_pattern_player_pressure()
		return

	var stage_times := _stage_times()
	# Rush / Zen scale the stage times; unlock times follow the same scale.
	var unlock_scale := float(stage_times[0]) / maxf(float(tuning.stage_1_threshold), 0.001)

	var patterns: Array[Callable] = []
	for entry in PATTERN_UNLOCKS:
		var method: StringName = entry[0]
		if method == &"_pattern_spikes" and mode == 2:
			continue
		if elapsed >= float(entry[1]) * unlock_scale:
			patterns.append(Callable(self, method))
	if elapsed >= tuning.idle_pressure_start:
		patterns.append(_pattern_player_pressure)
	if elapsed >= float(stage_times[3]):
		# Duplicates act as extra weight for the nastier patterns.
		patterns.append(_pattern_player_pressure)
		patterns.append(_pattern_double_sides)
		patterns.append(_pattern_corner_pair)
		patterns.append(_pattern_sweeper)

	var shuffled := patterns.duplicate()
	shuffled.shuffle()
	for pattern in shuffled:
		if pattern.call():
			return


## 0 at the start of a run, 1 once `difficulty_ramp_time` has passed (eased).
func _ramp() -> float:
	var t := clampf(elapsed / maxf(float(tuning.difficulty_ramp_time), 1.0), 0.0, 1.0)
	return smoothstep(0.0, 1.0, t)


## Warning time for a zone spawned right now: long at first, normal after the
## ramp, then slowly shrinking towards `late_warning_floor`.
func _current_warning() -> float:
	var ramp_time := maxf(float(tuning.difficulty_ramp_time), 1.0)
	var late := clampf((elapsed - ramp_time) / ramp_time, 0.0, 1.0)
	var base := warning_time * lerpf(1.0, float(tuning.late_warning_floor), late)
	return base + float(tuning.start_warning_bonus) * (1.0 - _ramp())


## Active time for a zone spawned right now: short at first, normal after the ramp.
func _current_active_time() -> float:
	return active_time * lerpf(float(tuning.start_active_scale), 1.0, _ramp())


## Stage times come from the Game node so banners and unlocks stay in sync.
func _stage_times() -> Array:
	var game := get_parent()
	if game and game.has_method("get_stage_times"):
		return game.get_stage_times(mode)
	var factors := [1.0, 1.0, 1.0, 1.0]
	if mode == 1:
		factors = [0.8, 0.85, 0.9, 0.95]
	elif mode == 2:
		factors = [1.2, 1.25, 1.3, 1.35]
	return [
		float(tuning.stage_1_threshold) * factors[0],
		float(tuning.stage_2_threshold) * factors[1],
		float(tuning.stage_3_threshold) * factors[2],
		float(tuning.stage_4_threshold) * factors[3],
	]


# ---------------------------------------------------------------------------
# Fairness
# ---------------------------------------------------------------------------

## True if none of the rects sit on the player and enough safe room is left.
func _is_pattern_fair(rects: Array[Rect2]) -> bool:
	if rects.is_empty():
		return false
	if is_instance_valid(player):
		for rect in rects:
			if rect.grow(SAFE_MARGIN).has_point(player.global_position):
				return false
	return _has_safe_room(rects)


## Samples a grid over the arena and counts points not covered by the new
## rects or any zone that is still alive (warning or active).
func _has_safe_room(rects: Array[Rect2]) -> bool:
	var hazards: Array[Rect2] = []
	hazards.append_array(rects)
	for child in get_children():
		if child is DangerZone and child.phase != DangerZone.Phase.DONE:
			hazards.append(child.get_danger_rect())

	var safe_points := 0
	for y in range(-3, 4):
		for x in range(-4, 5):
			var point := Vector2(x * _arena_half.x / 4.0, y * _arena_half.y / 3.0)
			var safe := true
			for hazard in hazards:
				if hazard.grow(SAFE_MARGIN).has_point(point):
					safe = false
					break
			if safe:
				safe_points += 1
				if safe_points >= SAFE_POINTS_REQUIRED:
					return true
	return false


# ---------------------------------------------------------------------------
# Spawning helpers
# ---------------------------------------------------------------------------

func _spawn_rects(rects: Array[Rect2]) -> bool:
	return _spawn_rects_as(rects, DangerZone.Kind.RECTANGLE)


func _spawn_rects_as(rects: Array[Rect2], kind: int, opts := {}) -> bool:
	if not _is_pattern_fair(rects):
		return false
	for rect in rects:
		_spawn_zone_as(rect, Vector2.ZERO, 0.0, kind, Vector2.ZERO, 0.0, opts)
	return true


func _spawn_zone(rect: Rect2, target := Vector2.ZERO, grow := 0.0) -> void:
	_spawn_zone_as(rect, target, grow, DangerZone.Kind.RECTANGLE)


## opts (all optional): warn_scale, active_scale, spin (rad/s), angle (rad).
func _spawn_zone_as(rect: Rect2, target: Vector2, grow: float, kind: int, axis := Vector2.ZERO, motion_range := 0.0, opts := {}) -> Area2D:
	var zone := DangerZone.new()
	var warn := _current_warning() * float(opts.get("warn_scale", 1.0))
	if mode == 2:
		warn += 0.3
	var act := _current_active_time() * float(opts.get("active_scale", 1.0))
	zone.setup(rect.size, target, warn, act, grow, kind, axis, motion_range)
	zone.spin_speed = float(opts.get("spin", 0.0))
	zone.rotation = float(opts.get("angle", 0.0))
	zone.position = rect.get_center()
	zone.motion_origin = zone.position
	add_child(zone)
	danger_spawned.emit(zone)
	return zone


func _clamp_point(point: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(point.x, -_arena_half.x + margin, _arena_half.x - margin),
		clampf(point.y, -_arena_half.y + margin, _arena_half.y - margin))


func _arena_rect() -> Rect2:
	return Rect2(-_arena_half, _arena_half * 2.0)


func _laser_rect(horizontal: bool, offset: float) -> Rect2:
	if horizontal:
		return Rect2(Vector2(-_arena_half.x, offset - LASER_THICKNESS / 2.0), Vector2(_arena_half.x * 2.0, LASER_THICKNESS))
	return Rect2(Vector2(offset - LASER_THICKNESS / 2.0, -_arena_half.y), Vector2(LASER_THICKNESS, _arena_half.y * 2.0))


func _random_sign() -> float:
	return 1.0 if randf() < 0.5 else -1.0


# ---------------------------------------------------------------------------
# Original patterns
# ---------------------------------------------------------------------------

func _pattern_spike_ball() -> bool:
	var half := _arena_half
	var margin := 40.0
	var spawn_position := Vector2(
		randf_range(-half.x + margin, half.x - margin),
		randf_range(-half.y + margin, half.y - margin))

	# Don't spawn directly on the player.
	if is_instance_valid(player) and spawn_position.distance_to(player.global_position) < 130.0:
		return false

	var direction := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	var ball := SpikeBall.new()
	ball.setup(spawn_position, direction, 180.0, _current_warning(), 3.0)
	ball.arena_rect = _arena_rect()
	add_child(ball)
	danger_spawned.emit(ball)
	return true


func _pattern_side_rect() -> bool:
	return _spawn_rects([_random_side_rect()])


func _pattern_player_pressure() -> bool:
	if not is_instance_valid(player):
		return false
	var pressure_size := Vector2(tuning.idle_pressure_size, tuning.idle_pressure_size)
	_spawn_zone(Rect2(player.global_position - pressure_size / 2.0, pressure_size))
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
	var thickness := randf_range(half.y * 0.25, half.y * 0.4)
	var y := randf_range(-half.y, half.y - thickness)
	return Rect2(Vector2(-half.x, y), Vector2(half.x * 2.0, thickness))


func _pattern_expand() -> bool:
	var half := _arena_half
	var start := Vector2(half.x * 0.08, half.y * 0.08)
	var target := Vector2(half.x * 0.9, half.y * 0.9)
	var center := Vector2(randf_range(-half.x * 0.15, half.x * 0.15), randf_range(-half.y * 0.15, half.y * 0.15))
	var rect := Rect2(center - start / 2.0, start)
	var grow_speed := target.distance_to(start) / _current_active_time()
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
	var swing := 170.0 if vertical else 130.0
	var sweep := rect.grow_individual(swing if vertical else 0.0, 0.0 if vertical else swing, swing if vertical else 0.0, 0.0 if vertical else swing)
	if not _is_pattern_fair([sweep]):
		return false
	_spawn_zone_as(rect, Vector2.ZERO, 0.0, DangerZone.Kind.MOVING_WALL, axis, swing)
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
	var gap_offset := randf_range(-half.y * 0.16, half.y * 0.16)
	var bar_height := half.y * 0.28
	var top := Rect2(Vector2(-half.x, -half.y + gap_offset), Vector2(half.x * 2.0, bar_height))
	var bottom := Rect2(Vector2(-half.x, half.y - bar_height + gap_offset), Vector2(half.x * 2.0, bar_height))
	# Shifting can push a bar past the arena edge, so trim both to the arena.
	var arena := _arena_rect()
	return _spawn_rects([top.intersection(arena), bottom.intersection(arena)])


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
	# Goes through the full fairness check now (it only checked the player before).
	return _spawn_rects_as(bars, DangerZone.Kind.ZIGZAG)


## The two arms now slowly spin around the arena centre.
func _pattern_pinwheel() -> bool:
	var half := _arena_half
	var arm_width := half.x * 0.16
	var arm_length := half.x * 0.62
	var rects: Array[Rect2] = [
		Rect2(Vector2(-arm_length / 2.0, -arm_width / 2.0), Vector2(arm_length, arm_width)),
		Rect2(Vector2(-arm_width / 2.0, -arm_length / 2.0), Vector2(arm_width, arm_length))
	]
	# The arms sweep a circle, so check room against its bounding square.
	var reach := arm_length / 2.0
	if not _has_safe_room([Rect2(Vector2(-reach, -reach), Vector2(reach, reach) * 2.0)]):
		return false
	if not _is_pattern_fair(rects):
		return false
	# One zone draws and collides as the whole plus (the second arm is built inside it).
	var spin := randf_range(0.8, 1.2) * _random_sign()
	_spawn_zone_as(rects[0], Vector2.ZERO, 0.0, DangerZone.Kind.PINWHEEL, Vector2.ZERO, 0.0, {"spin": spin})
	return true


# ---------------------------------------------------------------------------
# New patterns
# ---------------------------------------------------------------------------

## Round blasts. One leads the player's movement, the rest are scattered.
func _pattern_bombs() -> bool:
	var half := _arena_half
	var count := randi_range(3, 5)
	var spots: Array[Vector2] = []
	var radii: Array[float] = []
	var has_player := is_instance_valid(player)
	var player_pos := player.global_position if has_player else Vector2.ZERO

	if has_player:
		spots.append(_clamp_point(player_pos + player.velocity * _current_warning() * 0.6, 70.0))
		radii.append(70.0)

	var attempts := 0
	while spots.size() < count and attempts < 20:
		attempts += 1
		var r := randf_range(55.0, 75.0)
		var p := Vector2(randf_range(-half.x + r, half.x - r), randf_range(-half.y + r, half.y - r))
		if has_player and p.distance_to(player_pos) < r + 90.0:
			continue
		var overlaps := false
		for i in range(spots.size()):
			if p.distance_to(spots[i]) < r + radii[i] + 20.0:
				overlaps = true
				break
		if overlaps:
			continue
		spots.append(p)
		radii.append(r)

	var boxes: Array[Rect2] = []
	for i in range(spots.size()):
		boxes.append(Rect2(spots[i] - Vector2(radii[i], radii[i]), Vector2(radii[i], radii[i]) * 2.0))
	if not _has_safe_room(boxes):
		return false
	for box in boxes:
		_spawn_zone_as(box, Vector2.ZERO, 0.0, DangerZone.Kind.CIRCLE, Vector2.ZERO, 0.0, {"warn_scale": 0.9})
	return true


## Thin lasers lined up on the player's row and/or column.
func _pattern_laser_snipe() -> bool:
	if not is_instance_valid(player):
		return false
	var aim := _clamp_point(player.global_position + player.velocity * _current_warning() * 0.4, 20.0)
	var choice := randi_range(0, 2)  # 0 = row, 1 = column, 2 = both
	var rects: Array[Rect2] = []
	if choice != 1:
		rects.append(_laser_rect(true, aim.y))
	if choice != 0:
		rects.append(_laser_rect(false, aim.x))
	if not _has_safe_room(rects):
		return false
	for rect in rects:
		_spawn_zone_as(rect, Vector2.ZERO, 0.0, DangerZone.Kind.LASER, Vector2.ZERO, 0.0, {"active_scale": 0.4})
	return true


## A set of parallel lasers with gaps between them.
func _pattern_laser_barrage() -> bool:
	var horizontal := randf() < 0.5
	var span := _arena_half.y if horizontal else _arena_half.x
	var offsets: Array[float] = []
	var wanted := randi_range(3, 4)
	var tries := 0
	while offsets.size() < wanted and tries < 30:
		tries += 1
		var o := randf_range(-span + 30.0, span - 30.0)
		var spaced := true
		for other in offsets:
			if absf(o - other) < 120.0:
				spaced = false
				break
		if spaced:
			offsets.append(o)
	var rects: Array[Rect2] = []
	for o in offsets:
		rects.append(_laser_rect(horizontal, o))
	return _spawn_rects_as(rects, DangerZone.Kind.LASER, {"active_scale": 0.5, "warn_scale": 1.1})


## Two walls slide in from opposite sides and stop with a gap between them.
## The gap is placed near the player so it is always reachable.
func _pattern_crusher() -> bool:
	var horizontal := randf() < 0.5  # true: walls come from left and right
	var gap := 150.0 if horizontal else 130.0
	var thick := 90.0 if horizontal else 70.0
	var span := _arena_half.x if horizontal else _arena_half.y
	var cross := _arena_half.y if horizontal else _arena_half.x

	var focus := 0.0
	if is_instance_valid(player):
		focus = player.global_position.x if horizontal else player.global_position.y
	var limit := span - gap / 2.0 - thick - 40.0
	var gap_center := clampf(focus + randf_range(-120.0, 120.0), -limit, limit)

	var wall_size := Vector2(thick, cross * 2.0) if horizontal else Vector2(cross * 2.0, thick)
	var start_a := -span + thick / 2.0
	var start_b := span - thick / 2.0
	var end_a := gap_center - gap / 2.0 - thick / 2.0
	var end_b := gap_center + gap / 2.0 + thick / 2.0

	var rect_a := Rect2((Vector2(start_a, 0.0) if horizontal else Vector2(0.0, start_a)) - wall_size / 2.0, wall_size)
	var rect_b := Rect2((Vector2(start_b, 0.0) if horizontal else Vector2(0.0, start_b)) - wall_size / 2.0, wall_size)
	var axis_a := Vector2.RIGHT if horizontal else Vector2.DOWN
	var axis_b := -axis_a
	var dist_a := end_a - start_a
	var dist_b := start_b - end_b

	var swept: Array[Rect2] = [
		rect_a.merge(Rect2(rect_a.position + axis_a * dist_a, wall_size)),
		rect_b.merge(Rect2(rect_b.position + axis_b * dist_b, wall_size)),
	]
	if not _has_safe_room(swept):
		return false
	_spawn_zone_as(rect_a, Vector2.ZERO, 0.0, DangerZone.Kind.SLIDER, axis_a, dist_a)
	_spawn_zone_as(rect_b, Vector2.ZERO, 0.0, DangerZone.Kind.SLIDER, axis_b, dist_b)
	return true


## One long bar spinning around a point near the arena centre.
func _pattern_sweeper() -> bool:
	var half := _arena_half
	var length := half.y * 1.5
	var thick := 22.0
	var pivot := Vector2(randf_range(-half.x * 0.25, half.x * 0.25), randf_range(-half.y * 0.2, half.y * 0.2))
	if is_instance_valid(player) and pivot.distance_to(player.global_position) < 70.0:
		return false
	var reach := length / 2.0
	if not _has_safe_room([Rect2(pivot - Vector2(reach, reach), Vector2(reach, reach) * 2.0)]):
		return false
	var rect := Rect2(pivot - Vector2(length, thick) / 2.0, Vector2(length, thick))
	var spin := randf_range(1.0, 1.5) * _random_sign()
	_spawn_zone_as(rect, Vector2.ZERO, 0.0, DangerZone.Kind.SWEEPER, Vector2.ZERO, 0.0, {"spin": spin, "angle": randf() * PI})
	return true


## Half of a 4x3 grid of tiles goes lethal, in a checkerboard.
func _pattern_checkerboard() -> bool:
	var half := _arena_half
	var cols := 4
	var rows := 3
	var tile := Vector2(half.x * 2.0 / cols, half.y * 2.0 / rows)
	var parity := randi_range(0, 1)
	var rects: Array[Rect2] = []
	for cy in range(rows):
		for cx in range(cols):
			if (cx + cy) % 2 == parity:
				rects.append(Rect2(Vector2(-half.x + cx * tile.x, -half.y + cy * tile.y), tile).grow(-4.0))
	if not _has_safe_room(rects):
		return false
	# No "player not inside" check on purpose: a longer warning lets them step off.
	for rect in rects:
		_spawn_zone_as(rect, Vector2.ZERO, 0.0, DangerZone.Kind.RECTANGLE, Vector2.ZERO, 0.0, {"warn_scale": 1.15})
	return true
