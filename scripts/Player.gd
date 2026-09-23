extends CharacterBody2D

const SkinCatalog := preload("res://scripts/SkinCatalog.gd")

# ============================================================
# MOVEMENT
# ============================================================

@export_group("Movement")

@export var radius := 30.0
@export var max_speed := 420.0
@export var acceleration := 2000.0
@export var friction := 1800.0
@export var skin_scale := .4

# ============================================================
# VISUAL
# ============================================================

@export_group("Visual")

@export var trail_enabled := true
@export var trail_length := 15
@export var pulse_enabled := true
@export var pulse_amount := 0.055
@export var rotation_enabled := true 
@export var rotation_multipler := 3

@export var visual_radius := radius*skin_scale*3




# ============================================================
# ARENA
# ============================================================

## The playable arena rectangle.
## The Arena node has its origin at the center.
var arena_rect := Rect2(-400.0, -300.0, 800.0, 600.0)


# ============================================================
# SKINS
# ============================================================

const SKIN_COLORS := [
	Color("#23232b"),
	Color("#147d92"),
	Color("#6d3bb5"),
	Color("#c27b16"),
	Color("#b83232"),
	Color("#2e8b57"),
	Color("#2374ab"),
	Color("#9b3d9b"),
	Color("#d05b2d"),
	Color("#4b5563"),
	Color("#0f766e"),
	Color("#be185d"),
	Color("#4d7c0f"),
	Color("#7c3aed"),
	Color("#b45309"),
	Color("#334155"),
	Color("#0891b2"),
	Color("#dc2626"),
	Color("#65a30d"),
	Color("#f59e0b")
]

const SKIN_HIGHLIGHTS := [
	Color("#3f3f4b"),
	Color("#35c5d8"),
	Color("#b184f0"),
	Color("#f3c567"),
	Color("#ff8b8b"),
	Color("#72d99a"),
	Color("#75bdf0"),
	Color("#e28be2"),
	Color("#ff9b6d"),
	Color("#aeb8c7"),
	Color("#5eead4"),
	Color("#f472b6"),
	Color("#bef264"),
	Color("#c4b5fd"),
	Color("#fbbf74"),
	Color("#94a3b8"),
	Color("#67e8f9"),
	Color("#fca5a5"),
	Color("#bef264"),
	Color("#fde68a")
]


# ============================================================
# STATE
# ============================================================

var is_dead := false

var skin_index := 0

var touch_enabled := false
var touch_vector := Vector2.ZERO

var _trail: Array[Vector2] = []

var _base_sprite_scale := Vector2.ONE

var _pulse_time := 0.0

var _pulse_redraw_timer := 0.0

var _death_tween: Tween

var _dirty := true


# ============================================================
# NODES
# ============================================================

@onready var player_sprite: Sprite2D = $Sprite2D


# ============================================================
# READY
# ============================================================

func _ready() -> void:

	add_to_group("player")

	# --------------------------------------------------------
	# Find arena
	# --------------------------------------------------------
	var arena := get_node_or_null("../Arena")

	if arena and arena.has_method("get_bounds"):
		arena_rect = arena.get_bounds()
	# --------------------------------------------------------
	# Configure collision radius
	# --------------------------------------------------------
	var collision := get_node_or_null("CollisionShape2D")
	if collision and collision.shape is CircleShape2D:
		collision.shape.radius = radius
	# --------------------------------------------------------
	# Base sprite size
	# --------------------------------------------------------
	_base_sprite_scale = Vector2.ONE * (radius * 2.0 / 64.0) * skin_scale

	player_sprite.scale = _base_sprite_scale
	# --------------------------------------------------------
	# Apply skin
	# --------------------------------------------------------
	set_skin(skin_index)
	# --------------------------------------------------------
	# Initial drawing
	# --------------------------------------------------------
	queue_redraw()
# ============================================================
# PROCESS
# ============================================================

func _process(delta: float) -> void:

	if is_dead:
		return

	_pulse_time += delta
	_pulse_redraw_timer += delta

	if _dirty or (_pulse_redraw_timer >= 0.1 and _trail.size() > 1):
		_pulse_redraw_timer = 0.0
		_dirty = false
		queue_redraw()

# ============================================================
# PHYSICS
# ============================================================
func _physics_process(delta: float) -> void:

	if is_dead:
		return
	# --------------------------------------------------------
	# Read movement
	# --------------------------------------------------------

	var direction := _read_input()
	# --------------------------------------------------------
	# Smooth velocity
	# --------------------------------------------------------
	velocity = _update_velocity(
		velocity,
		direction,
		delta
	)
	# --------------------------------------------------------
	# Move
	# --------------------------------------------------------

	move_and_slide()
	# --------------------------------------------------------
	# Keep player inside arena
	# --------------------------------------------------------

	clamp_to_arena()
	# --------------------------------------------------------
	# Movement speed
	# --------------------------------------------------------
	var speed := velocity.length()

	var speed_ratio := clampf(
		speed / max_speed,
		0.0,
		1.0
	)
	# --------------------------------------------------------
	# Squash / stretch
	# --------------------------------------------------------

	var target_scale := _base_sprite_scale

	if speed > 5.0:
		var stretch := speed_ratio * 0.10
		var squash := speed_ratio * 0.06
		target_scale *= Vector2(
			1.0 + stretch,
			1.0 - squash
		)
	player_sprite.scale = player_sprite.scale.lerp(
		target_scale,
		minf(1.0, delta * 12.0)
	)
	# --------------------------------------------------------
	# Rotation
	# --------------------------------------------------------

	if rotation_enabled and speed > 10.0:

		player_sprite.rotation += (
			velocity.x * delta *  0.0015 * rotation_multipler
		)
	# --------------------------------------------------------
	# Trail
	# --------------------------------------------------------
	if trail_enabled and speed > 20.0:

		_trail.push_front(position)

		if _trail.size() > trail_length:
			_trail.pop_back()
		_dirty = true

	else:

		if _trail.size() > 0:
			_trail.pop_back()
			_dirty = true
# ============================================================
# INPUT
# ============================================================
func _read_input() -> Vector2:

	var direction := Vector2.ZERO
	# --------------------------------------------------------
	# Touch joystick
	# --------------------------------------------------------
	if touch_enabled and touch_vector != Vector2.ZERO:

		return touch_vector.limit_length(1.0)
	# --------------------------------------------------------
	# Keyboard
	# --------------------------------------------------------
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		return direction.normalized()
	# --------------------------------------------------------
	# Mouse steering
	# --------------------------------------------------------
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var target := get_global_mouse_position()
		var to_target := target - global_position
		if to_target.length() > 4.0:
			return to_target.normalized()

	return Vector2.ZERO

# ============================================================
# VELOCITY
# ============================================================
func _update_velocity(
	current: Vector2,
	direction: Vector2,
	delta: float
) -> Vector2:

	if direction != Vector2.ZERO:

		return current.move_toward(
			direction * max_speed,
			acceleration * delta
		)
	return current.move_toward(
		Vector2.ZERO,
		friction * delta
	)
# ============================================================
# TOUCH CONTROLS
# ============================================================

func set_touch_vector(value: Vector2) -> void:

	touch_vector = value.limit_length(1.0)
func set_touch_enabled(enabled: bool) -> void:

	touch_enabled = enabled

	if not enabled:
		touch_vector = Vector2.ZERO
# ============================================================
# SKIN
# ============================================================

func set_skin(index: int) -> void:

	skin_index = clampi(
		index,
		0,
		SkinCatalog.count() - 1
	)
	if not is_instance_valid(player_sprite):
		return

	if is_dead:
		player_sprite.modulate = Color("#7a1d1d")
	else:

		player_sprite.modulate = Color.WHITE
		player_sprite.texture = SkinCatalog.get_texture(skin_index)
	_dirty = true
	queue_redraw()
# ============================================================
# DEATH
# ============================================================
func die() -> void:
	if is_dead:
		return
	var main := get_tree().current_scene

	# --------------------------------------------------------
	# Shield
	# --------------------------------------------------------
	if main and main.has_method("_try_consume_shield"):

		if main._try_consume_shield():

			_shield_protected_effect()

			return
	# --------------------------------------------------------
	# Dead state
	# --------------------------------------------------------
	is_dead = true

	velocity = Vector2.ZERO
	# --------------------------------------------------------
	# Stop previous tween
	# --------------------------------------------------------
	if _death_tween and _death_tween.is_valid():

		_death_tween.kill()
	# --------------------------------------------------------
	# Death animation
	# --------------------------------------------------------
	_death_tween = create_tween()
	_death_tween.set_parallel(true)
	_death_tween.tween_property(
		player_sprite,
		"modulate",
		Color("#7a1d1d"),
		0.15
	)
	_death_tween.tween_property(
		player_sprite,
		"scale",
		_base_sprite_scale * 1.35,
		0.18
	).set_trans(
		Tween.TRANS_BACK
	).set_ease(
		Tween.EASE_OUT
	)
	_death_tween.tween_property(
		player_sprite,
		"rotation",
		player_sprite.rotation + TAU * 0.5,
		0.35
	).set_trans(
		Tween.TRANS_QUAD
	).set_ease(
		Tween.EASE_OUT
	)
	_dirty = true
	queue_redraw()

	# --------------------------------------------------------
	# Notify main game
	# --------------------------------------------------------
	if main and main.has_method("_on_player_died"):

		main._on_player_died()
# ============================================================
# SHIELD EFFECT
# ============================================================

func _shield_protected_effect() -> void:

	var original_scale := player_sprite.scale

	var tween := create_tween()

	tween.set_parallel(true)

	tween.tween_property(
		player_sprite,
		"scale",
		original_scale * 1.35,
		0.10
	).set_trans(
		Tween.TRANS_BACK
	)
	tween.tween_property(
		player_sprite,
		"modulate",
		Color("#fff3a3"),
		0.08
	)
	tween.chain().tween_property(
		player_sprite,
		"scale",
		original_scale,
		0.20
	)
	tween.tween_property(
		player_sprite,
		"modulate",
		Color.WHITE,
		0.20
	)
	_dirty = true
	queue_redraw()

# ============================================================
# RESET
# ============================================================

func reset() -> void:
	is_dead = false
	velocity = Vector2.ZERO
	position = Vector2.ZERO
	_trail.clear()
	player_sprite.rotation = 0.0
	player_sprite.scale = _base_sprite_scale
	set_skin(skin_index)
	_dirty = true
	queue_redraw()
# ============================================================
# ARENA CLAMP
# ============================================================
func clamp_to_arena() -> void:

	var min_x := arena_rect.position.x + radius
	var max_x := (
		arena_rect.position.x
		+ arena_rect.size.x
		- radius
	)
	var min_y := arena_rect.position.y + radius
	var max_y := (
		arena_rect.position.y
		+ arena_rect.size.y
		- radius
	)
	position.x = clampf(
		position.x,
		min_x,
		max_x
	)
	position.y = clampf(
		position.y,
		min_y,
		max_y
	)
# ============================================================
# CUSTOM DRAWING
# ============================================================
func _draw() -> void:
	# --------------------------------------------------------
	# Current skin colors
	# --------------------------------------------------------
	var skin_data := SkinCatalog.get_skin(skin_index)
	var body_color: Color = skin_data.body
	var highlight_color: Color = skin_data.highlight

	# --------------------------------------------------------
	# Motion trail
	# --------------------------------------------------------
	if trail_enabled and _trail.size() > 1 and not is_dead:
		for i in range(_trail.size() - 1):
			var point := _trail[i]
			var ratio := float(i) / float(maxi(1, _trail.size() - 1))
			var alpha := (1.0 - ratio) * 0.22

			var trail_radius := lerpf(
				visual_radius * 0.75,
				visual_radius * 0.20,
				ratio
			)

			draw_circle(
				to_local(point),
				trail_radius,
				Color(
					body_color.r,
					body_color.g,
					body_color.b,
					alpha
				)
			)

		# --------------------------------------------------------
		# Pulse ring
		# --------------------------------------------------------
		if pulse_enabled and not is_dead:

			var pulse := (
				sin(_pulse_time * 3.0)
				* 0.5
				+ 0.5
			)
			var pulse_radius := (
				radius
				+ 3.0
				+ pulse * 3.0
			)
			var pulse_alpha := (
				0.12
				- pulse * 0.07
			)

			draw_arc(
				Vector2.ZERO,
				pulse_radius,
				0.0,
				TAU,
				32,
				Color(
					highlight_color.r,
					highlight_color.g,
					highlight_color.b,
					pulse_alpha
				),
				1.5
			)

	# --------------------------------------------------------
	# Dead visual
	# --------------------------------------------------------
	if is_dead:
		draw_arc(
			Vector2.ZERO,
			radius * 1.35,
			0.0,
			TAU,
			32,
			Color(
				1.0,
				0.15,
				0.15,
				0.55
			),
			2.0
		)
