extends Node2D

## Spawns danger zones on an interval using a set of random patterns.
## Every pattern attempts to leave enough safe room for the player.
## Stage 4 continues indefinitely because the game is endless.

const DangerZone := preload("res://scripts/DangerZone.gd")
const SpikeBall := preload("res://scripts/SpikeBall.gd")

# ---------------------------------------------------------------------------
# Fairness / arena
# ---------------------------------------------------------------------------

const SAFE_MARGIN: float = 16.0
const SAFE_POINTS_REQUIRED: int = 3
const LASER_THICKNESS: float = 28.0

# Arena half-size.
# Arena is approximately -400..400 horizontally
# and -300..300 vertically.
var arena_half: Vector2 = Vector2(400.0, 300.0)


# ---------------------------------------------------------------------------
# Idle pressure
# ---------------------------------------------------------------------------

## Idle pressure is an anti-camping mechanic, not a guaranteed attack.
const IDLE_PRESSURE_COOLDOWN: float = 5.0
const IDLE_PRESSURE_CHANCE: float = 0.30
const MAX_CONSECUTIVE_IDLE_PRESSURES: int = 1


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal danger_spawned(zone)
signal danger_died


# ---------------------------------------------------------------------------
# Difficulty
# ---------------------------------------------------------------------------

@export var spawn_interval: float = 2.2
@export var warning_time: float = 1.2
@export var active_time: float = 2.0


# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var running: bool = false
var player: Node2D
var elapsed: float = 0.0
var mode: int = 0
var _run_generation: int = 0

# Idle pressure state.
var _last_idle_pressure_time: float = -999.0
var _idle_pressure_count: int = 0


# GameTuning node.
@onready var tuning: Node = get_node("../GameTuning")


# ===========================================================================
# START / STOP
# ===========================================================================

func start(p: Node2D, selected_mode: int = 0) -> void:
	_run_generation += 1

	player = p
	mode = selected_mode
	elapsed = 0.0
	running = true

	# Reset idle-pressure state.
	_last_idle_pressure_time = -999.0
	_idle_pressure_count = 0

	# Read master tuning.
	spawn_interval = float(tuning.danger_spawn_interval)
	warning_time = float(tuning.danger_warning_time)
	active_time = float(tuning.danger_active_time)

	# Rush mode.
	if mode == 1:
		spawn_interval *= float(tuning.rush_spawn_multiplier)
		warning_time *= float(tuning.rush_warning_multiplier)
		active_time *= float(tuning.rush_active_multiplier)

	# Zen mode.
	elif mode == 2:
		spawn_interval *= float(tuning.zen_spawn_multiplier)
		warning_time *= float(tuning.zen_warning_multiplier)
		active_time *= float(tuning.zen_active_multiplier)

	_schedule(_run_generation)


func stop() -> void:
	_run_generation += 1
	running = false
	elapsed = 0.0

	_last_idle_pressure_time = -999.0
	_idle_pressure_count = 0

	for child in get_children():
		if child is DangerZone or child is SpikeBall:
			child.queue_free()


func _process(delta: float) -> void:
	if running:
		elapsed += delta


# ===========================================================================
# SPAWN SCHEDULER
# ===========================================================================

func _schedule(generation: int) -> void:
	while running and generation == _run_generation:
		var interval: float = maxf(
			float(tuning.danger_min_spawn_interval),
			spawn_interval
			- elapsed * float(tuning.danger_spawn_acceleration)
		)

		# Rush can go slightly faster.
		if mode == 1:
			interval = maxf(
				float(tuning.danger_min_spawn_interval) * 0.7,
				interval
			)

		await get_tree().create_timer(interval, false).timeout

		if not running or generation != _run_generation:
			return

		_spawn_random_pattern()


# ===========================================================================
# PATTERN SELECTION
# ===========================================================================

func _spawn_random_pattern() -> void:

	# -----------------------------------------------------------------------
	# Detect whether player is standing still.
	# -----------------------------------------------------------------------

	var idle: bool = (
		is_instance_valid(player)
		and player.velocity.length() < 10.0
	)

	# -----------------------------------------------------------------------
	# Idle pressure
	# -----------------------------------------------------------------------

	var can_pressure: bool = (
		elapsed >= float(tuning.idle_pressure_start)
		and idle
		and elapsed - _last_idle_pressure_time >= IDLE_PRESSURE_COOLDOWN
		and _idle_pressure_count < MAX_CONSECUTIVE_IDLE_PRESSURES
	)

	if can_pressure and randf() < IDLE_PRESSURE_CHANCE:
		if _pattern_player_pressure():
			_last_idle_pressure_time = elapsed
			_idle_pressure_count += 1
			return

	# -----------------------------------------------------------------------
	# Normal pattern pool
	# -----------------------------------------------------------------------

	var patterns: Array[Callable] = [
		_pattern_side_rect,
		_pattern_strip,
		_pattern_expand,
		_pattern_spike_ball,
		_pattern_zigzag,
		_pattern_pinwheel,
		_pattern_bombs,
	]

	# Spikes are disabled in Zen.
	if mode != 2:
		patterns.append(_pattern_spikes)

	# -----------------------------------------------------------------------
	# Stage timing
	# -----------------------------------------------------------------------

	var stage_times: Array = _stage_times()

	var stage_1_time: float = float(stage_times[0])
	var stage_2_time: float = float(stage_times[1])
	var stage_3_time: float = float(stage_times[2])
	var stage_4_time: float = float(stage_times[3])

	# -----------------------------------------------------------------------
	# Stage 1
	# -----------------------------------------------------------------------

	if elapsed >= stage_1_time:
		patterns.append(_pattern_cross)
		patterns.append(_pattern_moving_wall)
		patterns.append(_pattern_laser_snipe)

	# -----------------------------------------------------------------------
	# Stage 2
	# -----------------------------------------------------------------------

	if elapsed >= stage_2_time:
		patterns.append(_pattern_double_sides)
		patterns.append(_pattern_crusher)
		patterns.append(_pattern_laser_barrage)

	# -----------------------------------------------------------------------
	# Stage 3
	# -----------------------------------------------------------------------

	if elapsed >= stage_3_time:
		patterns.append(_pattern_corner_pair)
		patterns.append(_pattern_sweeper)
		patterns.append(_pattern_checkerboard)

	# -----------------------------------------------------------------------
	# Stage 4+
	#
	# The game is endless.
	# These are intentionally added again to increase their probability.
	# Stage 4 therefore continues forever.
	# -----------------------------------------------------------------------

	if elapsed >= stage_4_time:
		patterns.append(_pattern_double_sides)
		patterns.append(_pattern_corner_pair)
		patterns.append(_pattern_sweeper)

	# -----------------------------------------------------------------------
	# Shuffle and try patterns.
	# -----------------------------------------------------------------------

	var shuffled: Array[Callable] = patterns.duplicate()
	shuffled.shuffle()

	for pattern: Callable in shuffled:
		if pattern.call():
			# Successful normal pattern resets the idle-pressure chain.
			_idle_pressure_count = 0
			return


# ===========================================================================
# STAGE TIMING
# ===========================================================================

## Gets stage thresholds.
## The Game node can override these so stage banners/unlocks remain synced.
func _stage_times() -> Array:
	var game: Node = get_parent()

	if is_instance_valid(game) and game.has_method("get_stage_times"):
		return game.get_stage_times(mode)

	var factors: Array[float] = [
		1.0,
		1.0,
		1.0,
		1.0
	]

	if mode == 1:
		factors = [
			0.8,
			0.85,
			0.9,
			0.95
		]

	elif mode == 2:
		factors = [
			1.2,
			1.25,
			1.3,
			1.35
		]

	return [
		float(tuning.stage_1_threshold) * factors[0],
		float(tuning.stage_2_threshold) * factors[1],
		float(tuning.stage_3_threshold) * factors[2],
		float(tuning.stage_4_threshold) * factors[3]
	]


# ===========================================================================
# FAIRNESS
# ===========================================================================

## Returns true if the pattern does not overlap the player and enough
## safe sample points remain.
func _is_pattern_fair(rects: Array[Rect2]) -> bool:
	if rects.is_empty():
		return false

	if is_instance_valid(player):
		for rect in rects:
			if rect.grow(SAFE_MARGIN).has_point(player.global_position):
				return false

	return _has_safe_room(rects)


## Samples a grid across the arena and checks how many points remain safe.
func _has_safe_room(rects: Array[Rect2]) -> bool:
	var hazards: Array[Rect2] = []

	hazards.append_array(rects)

	for child in get_children():
		if child is DangerZone and child.phase != DangerZone.Phase.DONE:
			hazards.append(child.get_danger_rect())

	var safe_points: int = 0

	for y in range(-3, 4):
		for x in range(-4, 5):

			var point: Vector2 = Vector2(
				x * arena_half.x / 4.0,
				y * arena_half.y / 3.0
			)

			var safe: bool = true

			for hazard in hazards:
				if hazard.grow(SAFE_MARGIN).has_point(point):
					safe = false
					break

			if safe:
				safe_points += 1

				if safe_points >= SAFE_POINTS_REQUIRED:
					return true

	return false


# ===========================================================================
# SPAWNING HELPERS
# ===========================================================================

func _spawn_rects(rects: Array[Rect2]) -> bool:
	return _spawn_rects_as(
		rects,
		DangerZone.Kind.RECTANGLE
	)


func _spawn_rects_as(
	rects: Array[Rect2],
	kind: int,
	opts: Dictionary = {}
) -> bool:

	if not _is_pattern_fair(rects):
		return false

	for rect in rects:
		_spawn_zone_as(
			rect,
			Vector2.ZERO,
			0.0,
			kind,
			Vector2.ZERO,
			0.0,
			opts
		)

	return true


func _spawn_zone(
	rect: Rect2,
	target: Vector2 = Vector2.ZERO,
	grow: float = 0.0
) -> void:

	_spawn_zone_as(
		rect,
		target,
		grow,
		DangerZone.Kind.RECTANGLE
	)


## opts:
## warn_scale
## active_scale
## spin
## angle
func _spawn_zone_as(
	rect: Rect2,
	target: Vector2,
	grow: float,
	kind: int,
	axis: Vector2 = Vector2.ZERO,
	motion_range: float = 0.0,
	opts: Dictionary = {}
) -> Area2D:

	var zone := DangerZone.new()

	var warn: float = warning_time * float(
		opts.get("warn_scale", 1.0)
	)

	# Zen gets additional warning time.
	if mode == 2:
		warn += 0.3

	var act: float = active_time * float(
		opts.get("active_scale", 1.0)
	)

	zone.setup(
		rect.size,
		target,
		warn,
		act,
		grow,
		kind,
		axis,
		motion_range
	)

	zone.spin_speed = float(
		opts.get("spin", 0.0)
	)

	zone.rotation = float(
		opts.get("angle", 0.0)
	)

	zone.position = rect.get_center()
	zone.motion_origin = zone.position

	add_child(zone)

	danger_spawned.emit(zone)

	return zone


# ===========================================================================
# ARENA HELPERS
# ===========================================================================

func _clamp_point(point: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(
			point.x,
			-arena_half.x + margin,
			arena_half.x - margin
		),
		clampf(
			point.y,
			-arena_half.y + margin,
			arena_half.y - margin
		)
	)


func _arena_rect() -> Rect2:
	return Rect2(
		-arena_half,
		arena_half * 2.0
	)


func _laser_rect(
	horizontal: bool,
	offset: float
) -> Rect2:

	if horizontal:
		return Rect2(
			Vector2(
				-arena_half.x,
				offset - LASER_THICKNESS / 2.0
			),
			Vector2(
				arena_half.x * 2.0,
				LASER_THICKNESS
			)
		)

	return Rect2(
		Vector2(
			offset - LASER_THICKNESS / 2.0,
			-arena_half.y
		),
		Vector2(
			LASER_THICKNESS,
			arena_half.y * 2.0
		)
	)


func _random_sign() -> float:
	return 1.0 if randf() < 0.5 else -1.0


# ===========================================================================
# ORIGINAL PATTERNS
# ===========================================================================

func _pattern_spike_ball() -> bool:
	var half: Vector2 = arena_half
	var margin: float = 40.0

	var spawn_position: Vector2 = Vector2(
		randf_range(
			-half.x + margin,
			half.x - margin
		),
		randf_range(
			-half.y + margin,
			half.y - margin
		)
	)

	# Don't spawn directly on the player.
	if (
		is_instance_valid(player)
		and spawn_position.distance_to(player.global_position) < 130.0
	):
		return false

	var direction: Vector2 = Vector2(
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

	ball.arena_rect = _arena_rect()

	add_child(ball)
	danger_spawned.emit(ball)

	return true


func _pattern_side_rect() -> bool:
	return _spawn_rects([
		_random_side_rect()
	])


# ===========================================================================
# IDLE PRESSURE
# ===========================================================================

func _pattern_player_pressure() -> bool:
	if not is_instance_valid(player):
		return false

	var pressure_size: Vector2 = Vector2(
		float(tuning.idle_pressure_size),
		float(tuning.idle_pressure_size)
	)

	# Slightly offset from the player instead of spawning directly on them.
	var offset: Vector2 = Vector2(
		randf_range(-90.0, 90.0),
		randf_range(-90.0, 90.0)
	)

	var center: Vector2 = _clamp_point(
		player.global_position + offset,
		pressure_size.x / 2.0 + SAFE_MARGIN
	)

	var rect: Rect2 = Rect2(
		center - pressure_size / 2.0,
		pressure_size
	)

	# Normal fairness system applies.
	return _spawn_rects([
		rect
	])


# ===========================================================================
# SIDE RECT
# ===========================================================================

func _random_side_rect() -> Rect2:
	var side: int = randi_range(0, 3)
	var half: Vector2 = arena_half

	match side:
		0:
			# Left
			var w: float = half.x * randf_range(0.45, 0.6)

			return Rect2(
				Vector2(-half.x, -half.y),
				Vector2(w, half.y * 2.0)
			)

		1:
			# Right
			var w: float = half.x * randf_range(0.45, 0.6)

			return Rect2(
				Vector2(half.x - w, -half.y),
				Vector2(w, half.y * 2.0)
			)

		2:
			# Top
			var h: float = half.y * randf_range(0.45, 0.6)

			return Rect2(
				Vector2(-half.x, -half.y),
				Vector2(half.x * 2.0, h)
			)

		_:
			# Bottom
			var h: float = half.y * randf_range(0.45, 0.6)

			return Rect2(
				Vector2(-half.x, half.y - h),
				Vector2(half.x * 2.0, h)
			)


# ===========================================================================
# STRIP
# ===========================================================================

func _pattern_strip() -> bool:
	return _spawn_rects([
		_random_strip()
	])


func _random_strip() -> Rect2:
	var vertical: bool = randf() < 0.5
	var half: Vector2 = arena_half

	if vertical:
		var thickness: float = randf_range(
			half.x * 0.25,
			half.x * 0.4
		)

		var x: float = randf_range(
			-half.x,
			half.x - thickness
		)

		return Rect2(
			Vector2(x, -half.y),
			Vector2(
				thickness,
				half.y * 2.0
			)
		)

	var thickness: float = randf_range(
		half.y * 0.25,
		half.y * 0.4
	)

	var y: float = randf_range(
		-half.y,
		half.y - thickness
	)

	return Rect2(
		Vector2(-half.x, y),
		Vector2(
			half.x * 2.0,
			thickness
		)
	)


# ===========================================================================
# EXPAND
# ===========================================================================

func _pattern_expand() -> bool:
	var half: Vector2 = arena_half

	var start: Vector2 = Vector2(
		half.x * 0.08,
		half.y * 0.08
	)

	var target: Vector2 = Vector2(
		half.x * 0.9,
		half.y * 0.9
	)

	var center: Vector2 = Vector2(
		randf_range(
			-half.x * 0.15,
			half.x * 0.15
		),
		randf_range(
			-half.y * 0.15,
			half.y * 0.15
		)
	)

	var rect: Rect2 = Rect2(
		center - start / 2.0,
		start
	)

	var grow_speed: float = (
		target.distance_to(start)
		/ maxf(active_time, 0.1)
	)

	if not _is_pattern_fair([
		Rect2(
			center - target / 2.0,
			target
		)
	]):
		return false

	_spawn_zone(
		rect,
		target,
		grow_speed
	)

	return true


# ===========================================================================
# SPIKES
# ===========================================================================

func _pattern_spikes() -> bool:
	var rect: Rect2 = _random_side_rect()

	if not _is_pattern_fair([
		rect
	]):
		return false

	_spawn_zone_as(
		rect,
		Vector2.ZERO,
		0.0,
		DangerZone.Kind.SPIKES
	)

	return true


# ===========================================================================
# MOVING WALL
# ===========================================================================

func _pattern_moving_wall() -> bool:
	var half: Vector2 = arena_half
	var vertical: bool = randf() < 0.5

	var axis: Vector2 = (
		Vector2.RIGHT
		if vertical
		else Vector2.DOWN
	)

	var size: Vector2 = (
		Vector2(
			half.x * 0.14,
			half.y * 2.0
		)
		if vertical
		else
		Vector2(
			half.x * 2.0,
			half.y * 0.14
		)
	)

	var start: Vector2 = (
		Vector2(
			randf_range(
				-half.x * 0.45,
				half.x * 0.45
			),
			0.0
		)
		if vertical
		else
		Vector2(
			0.0,
			randf_range(
				-half.y * 0.45,
				half.y * 0.45
			)
		)
	)

	var rect: Rect2 = Rect2(
		start - size / 2.0,
		size
	)

	var swing: float = (
		170.0
		if vertical
		else 130.0
	)

	var sweep: Rect2 = rect.grow_individual(
		swing if vertical else 0.0,
		0.0 if vertical else swing,
		swing if vertical else 0.0,
		0.0 if vertical else swing
	)

	if not _is_pattern_fair([
		sweep
	]):
		return false

	_spawn_zone_as(
		rect,
		Vector2.ZERO,
		0.0,
		DangerZone.Kind.MOVING_WALL,
		axis,
		swing
	)

	return true


# ===========================================================================
# CROSS
# ===========================================================================

func _pattern_cross() -> bool:
	var half: Vector2 = arena_half

	var vertical_width: float = half.x * 0.22
	var horizontal_height: float = half.y * 0.22

	var offset: float = randf_range(
		-half.x * 0.18,
		half.x * 0.18
	)

	var vertical: Rect2 = Rect2(
		Vector2(
			offset - vertical_width / 2.0,
			-half.y
		),
		Vector2(
			vertical_width,
			half.y * 2.0
		)
	)

	var horizontal: Rect2 = Rect2(
		Vector2(
			-half.x,
			-horizontal_height / 2.0
		),
		Vector2(
			half.x * 2.0,
			horizontal_height
		)
	)

	return _spawn_rects([
		vertical,
		horizontal
	])


# ===========================================================================
# DOUBLE SIDES
# ===========================================================================

func _pattern_double_sides() -> bool:
	var half: Vector2 = arena_half

	var gap_offset: float = randf_range(
		-half.y * 0.16,
		half.y * 0.16
	)

	var bar_height: float = half.y * 0.28

	var top: Rect2 = Rect2(
		Vector2(
			-half.x,
			-half.y + gap_offset
		),
		Vector2(
			half.x * 2.0,
			bar_height
		)
	)

	var bottom: Rect2 = Rect2(
		Vector2(
			-half.x,
			half.y - bar_height + gap_offset
		),
		Vector2(
			half.x * 2.0,
			bar_height
		)
	)

	var arena: Rect2 = _arena_rect()

	return _spawn_rects([
		top.intersection(arena),
		bottom.intersection(arena)
	])


# ===========================================================================
# CORNER PAIR
# ===========================================================================

func _pattern_corner_pair() -> bool:
	var half: Vector2 = arena_half

	var corner_size: Vector2 = Vector2(
		half.x * 0.42,
		half.y * 0.38
	)

	var left: Rect2 = Rect2(
		Vector2(-half.x, -half.y),
		corner_size
	)

	var right: Rect2 = Rect2(
		Vector2(
			half.x - corner_size.x,
			half.y - corner_size.y
		),
		corner_size
	)

	return _spawn_rects([
		left,
		right
	])


# ===========================================================================
# ZIGZAG
# ===========================================================================

func _pattern_zigzag() -> bool:
	var half: Vector2 = arena_half

	var bar_size: Vector2 = Vector2(
		half.x * 0.34,
		half.y * 0.18
	)

	var bars: Array[Rect2] = []

	for i in range(3):
		var x: float = (
			-half.x + half.x * 0.56
			if i % 2 == 0
			else
			-half.x + half.x * 0.10
		)

		var y: float = (
			-half.y * 0.72
			+ i * half.y * 0.72
		)

		bars.append(
			Rect2(
				Vector2(x, y),
				bar_size
			)
		)

	return _spawn_rects_as(
		bars,
		DangerZone.Kind.ZIGZAG
	)


# ===========================================================================
# PINWHEEL
# ===========================================================================

func _pattern_pinwheel() -> bool:
	var half: Vector2 = arena_half

	var arm_width: float = half.x * 0.16
	var arm_length: float = half.x * 0.62

	var rects: Array[Rect2] = [
		Rect2(
			Vector2(
				-arm_length / 2.0,
				-arm_width / 2.0
			),
			Vector2(
				arm_length,
				arm_width
			)
		),

		Rect2(
			Vector2(
				-arm_width / 2.0,
				-arm_length / 2.0
			),
			Vector2(
				arm_width,
				arm_length
			)
		)
	]

	var reach: float = arm_length / 2.0

	if not _has_safe_room([
		Rect2(
			Vector2(-reach, -reach),
			Vector2(reach, reach) * 2.0
		)
	]):
		return false

	if not _is_pattern_fair(rects):
		return false

	var spin: float = (
		randf_range(0.8, 1.2)
		* _random_sign()
	)

	_spawn_zone_as(
		rects[0],
		Vector2.ZERO,
		0.0,
		DangerZone.Kind.PINWHEEL,
		Vector2.ZERO,
		0.0,
		{
			"spin": spin
		}
	)

	return true


# ===========================================================================
# BOMBS
# ===========================================================================

func _pattern_bombs() -> bool:
	var half: Vector2 = arena_half
	var count: int = randi_range(3, 5)

	var spots: Array[Vector2] = []
	var radii: Array[float] = []

	var has_player: bool = is_instance_valid(player)

	var player_pos: Vector2 = (
		player.global_position
		if has_player
		else
		Vector2.ZERO
	)

	if has_player:
		spots.append(
			_clamp_point(
				player_pos
				+ player.velocity
				* warning_time
				* 0.6,
				70.0
			)
		)

		radii.append(70.0)

	var attempts: int = 0

	while spots.size() < count and attempts < 20:
		attempts += 1

		var r: float = randf_range(55.0, 75.0)

		var p: Vector2 = Vector2(
			randf_range(
				-half.x + r,
				half.x - r
			),
			randf_range(
				-half.y + r,
				half.y - r
			)
		)

		if (
			has_player
			and p.distance_to(player_pos) < r + 90.0
		):
			continue

		var overlaps: bool = false

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
		boxes.append(
			Rect2(
				spots[i] - Vector2(
					radii[i],
					radii[i]
				),
				Vector2(
					radii[i],
					radii[i]
				) * 2.0
			)
		)

	if not _has_safe_room(boxes):
		return false

	for box in boxes:
		_spawn_zone_as(
			box,
			Vector2.ZERO,
			0.0,
			DangerZone.Kind.CIRCLE,
			Vector2.ZERO,
			0.0,
			{
				"warn_scale": 0.9
			}
		)

	return true


# ===========================================================================
# LASER SNIPE
# ===========================================================================

func _pattern_laser_snipe() -> bool:
	if not is_instance_valid(player):
		return false

	var aim: Vector2 = _clamp_point(
		player.global_position
		+ player.velocity
		* warning_time
		* 0.4,
		20.0
	)

	var choice: int = randi_range(0, 2)

	var rects: Array[Rect2] = []

	if choice != 1:
		rects.append(
			_laser_rect(
				true,
				aim.y
			)
		)

	if choice != 0:
		rects.append(
			_laser_rect(
				false,
				aim.x
			)
		)

	if not _has_safe_room(rects):
		return false

	for rect in rects:
		_spawn_zone_as(
			rect,
			Vector2.ZERO,
			0.0,
			DangerZone.Kind.LASER,
			Vector2.ZERO,
			0.0,
			{
				"active_scale": 0.4
			}
		)

	return true


# ===========================================================================
# LASER BARRAGE
# ===========================================================================

func _pattern_laser_barrage() -> bool:
	var horizontal: bool = randf() < 0.5

	var span: float = (
		arena_half.y
		if horizontal
		else arena_half.x
	)

	var offsets: Array[float] = []

	var wanted: int = randi_range(3, 4)
	var tries: int = 0

	while offsets.size() < wanted and tries < 30:
		tries += 1

		var o: float = randf_range(
			-span + 30.0,
			span - 30.0
		)

		var spaced: bool = true

		for other in offsets:
			if absf(o - other) < 120.0:
				spaced = false
				break

		if spaced:
			offsets.append(o)

	var rects: Array[Rect2] = []

	for o in offsets:
		rects.append(
			_laser_rect(
				horizontal,
				o
			)
		)

	return _spawn_rects_as(
		rects,
		DangerZone.Kind.LASER,
		{
			"active_scale": 0.5,
			"warn_scale": 1.1
		}
	)


# ===========================================================================
# CRUSHER
# ===========================================================================

func _pattern_crusher() -> bool:
	var horizontal: bool = randf() < 0.5

	var gap: float = (
		150.0
		if horizontal
		else 130.0
	)

	var thick: float = (
		90.0
		if horizontal
		else 70.0
	)

	var span: float = (
		arena_half.x
		if horizontal
		else arena_half.y
	)

	var cross: float = (
		arena_half.y
		if horizontal
		else arena_half.x
	)

	var focus: float = 0.0

	if is_instance_valid(player):
		focus = (
			player.global_position.x
			if horizontal
			else player.global_position.y
		)

	var limit: float = (
		span
		- gap / 2.0
		- thick
		- 40.0
	)

	var gap_center: float = clampf(
		focus + randf_range(-120.0, 120.0),
		-limit,
		limit
	)

	var wall_size: Vector2 = (
		Vector2(
			thick,
			cross * 2.0
		)
		if horizontal
		else
		Vector2(
			cross * 2.0,
			thick
		)
	)

	var start_a: float = -span + thick / 2.0
	var start_b: float = span - thick / 2.0

	var end_a: float = (
		gap_center
		- gap / 2.0
		- thick / 2.0
	)

	var end_b: float = (
		gap_center
		+ gap / 2.0
		+ thick / 2.0
	)

	var rect_a: Rect2 = Rect2(
		(
			Vector2(start_a, 0.0)
			if horizontal
			else
			Vector2(0.0, start_a)
		)
		- wall_size / 2.0,
		wall_size
	)

	var rect_b: Rect2 = Rect2(
		(
			Vector2(start_b, 0.0)
			if horizontal
			else
			Vector2(0.0, start_b)
		)
		- wall_size / 2.0,
		wall_size
	)

	var axis_a: Vector2 = (
		Vector2.RIGHT
		if horizontal
		else Vector2.DOWN
	)

	var axis_b: Vector2 = -axis_a

	var dist_a: float = end_a - start_a
	var dist_b: float = start_b - end_b

	var swept: Array[Rect2] = [
		rect_a.merge(
			Rect2(
				rect_a.position + axis_a * dist_a,
				wall_size
			)
		),

		rect_b.merge(
			Rect2(
				rect_b.position + axis_b * dist_b,
				wall_size
			)
		)
	]

	if not _has_safe_room(swept):
		return false

	_spawn_zone_as(
		rect_a,
		Vector2.ZERO,
		0.0,
		DangerZone.Kind.SLIDER,
		axis_a,
		dist_a
	)

	_spawn_zone_as(
		rect_b,
		Vector2.ZERO,
		0.0,
		DangerZone.Kind.SLIDER,
		axis_b,
		dist_b
	)

	return true


# ===========================================================================
# SWEEPER
# ===========================================================================

func _pattern_sweeper() -> bool:
	var half: Vector2 = arena_half

	var length: float = half.y * 1.5
	var thick: float = 22.0

	var pivot: Vector2 = Vector2(
		randf_range(
			-half.x * 0.25,
			half.x * 0.25
		),
		randf_range(
			-half.y * 0.2,
			half.y * 0.2
		)
	)

	if (
		is_instance_valid(player)
		and pivot.distance_to(player.global_position) < 70.0
	):
		return false

	var reach: float = length / 2.0

	if not _has_safe_room([
		Rect2(
			pivot - Vector2(reach, reach),
			Vector2(reach, reach) * 2.0
		)
	]):
		return false

	var rect: Rect2 = Rect2(
		pivot - Vector2(length, thick) / 2.0,
		Vector2(length, thick)
	)

	var spin: float = (
		randf_range(1.0, 1.5)
		* _random_sign()
	)

	_spawn_zone_as(
		rect,
		Vector2.ZERO,
		0.0,
		DangerZone.Kind.SWEEPER,
		Vector2.ZERO,
		0.0,
		{
			"spin": spin,
			"angle": randf() * PI
		}
	)

	return true


# ===========================================================================
# CHECKERBOARD
# ===========================================================================

func _pattern_checkerboard() -> bool:
	var half: Vector2 = arena_half

	var cols: int = 4
	var rows: int = 3

	var tile: Vector2 = Vector2(
		half.x * 2.0 / cols,
		half.y * 2.0 / rows
	)

	var parity: int = randi_range(0, 1)

	var rects: Array[Rect2] = []

	for cy in range(rows):
		for cx in range(cols):
			if (cx + cy) % 2 == parity:
				rects.append(
					Rect2(
						Vector2(
							-half.x + cx * tile.x,
							-half.y + cy * tile.y
						),
						tile
					).grow(-4.0)
				)

	if not _has_safe_room(rects):
		return false

	# Longer warning gives the player more time to react.
	for rect in rects:
		_spawn_zone_as(
			rect,
			Vector2.ZERO,
			0.0,
			DangerZone.Kind.RECTANGLE,
			Vector2.ZERO,
			0.0,
			{
				"warn_scale": 1.15
			}
		)

	return true
