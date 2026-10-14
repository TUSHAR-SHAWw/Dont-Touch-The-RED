extends CharacterBody2D

## The player ball: movement, skin, visual effects and death.
## Game connects to `died` and sets `shield_handler`, so this script does not
## depend on where Game sits in the scene tree.

## Emitted once when the player actually dies (not when a shield absorbs a hit).
signal died

## Emitted when the player slams into an arena wall at speed (for dust / shake).
signal wall_hit(world_position: Vector2, strength: float)

const SkinCatalog := preload("res://scripts/SkinCatalog.gd")
const FXScript := preload("res://scripts/FX.gd")

## All skin textures are 1:1 square. The sprite scale is derived from
## the actual texture size so the rendered player stays a consistent
## size regardless of the source texture resolution.
const SKIN_TEXTURE_SIZE := 185.0

const DEAD_COLOR := Color("#7a1d1d")
const SHIELD_FLASH_COLOR := Color("#fff3a3")
const SHIELD_RING_COLOR := Color("#ffd166")
## Don't replay the shield pop more often than this (a zone can hit every frame).
const SHIELD_FX_COOLDOWN_MSEC := 300
## Mouse steering reaches full speed at this distance from the cursor.
const MOUSE_FULL_SPEED_DISTANCE := 40.0
## Walls only report an impact above this speed, and not more often than this.
const WALL_HIT_MIN_SPEED := 160.0
const WALL_HIT_COOLDOWN_MSEC := 140
const REVIVE_RING_COLOR := Color("#3ddcff")

## Default bindings, only added if the project doesn't define these actions.
const MOVE_ACTIONS := {
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"move_up": [KEY_W, KEY_UP],
	&"move_down": [KEY_S, KEY_DOWN],
}
const MOVE_JOY_AXES := {
	&"move_left": [JOY_AXIS_LEFT_X, -1.0],
	&"move_right": [JOY_AXIS_LEFT_X, 1.0],
	&"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

@export_group("Movement")
@export var radius := 32.0
@export var max_speed := 420.0
@export var acceleration := 2000.0
@export var friction := 1800.0
@export var skin_scale := 1.0
## Fraction of `radius` used for the collision shape. Below 1.0 the hitbox is
## smaller than the sprite, which feels fairer in a dodging game.
@export_range(0.5, 1.0, 0.05) var hit_radius_scale := 0.85

@export_group("Visual")
@export var trail_enabled := true
@export var trail_length := 15
@export var pulse_enabled := true
@export var pulse_amount := 0.055
@export var rotation_enabled := true
@export var rotation_multiplier := 3.0

## Set by Game. Called when the player is hit; returns true if a shield (or
## grace period) absorbed the hit.
var shield_handler := Callable()

## Visual radius for trail/pulse effects (kept in sync with `radius` in _ready).
var visual_radius := 32.0

## The playable arena rectangle. The Arena node has its origin at the centre.
var arena_rect := Rect2(-400.0, -300.0, 800.0, 600.0)

var is_dead := false
var skin_index := 0
var touch_enabled := false
var touch_vector := Vector2.ZERO
var effects_reduced := false

var _trail: Array[Vector2] = []
var _base_scale := 1.0
var _sprite_origin := Vector2.ZERO
var _pulse_time := 0.0
var _dirty := true

# Sprite effect state. The sprite's transform is rebuilt every frame from these.
var _spin := 0.0
var _death_spin := 0.0
var _pop := 1.0
var _stretch := 0.0
var _stretch_angle := 0.0

# Skin colors, cached in set_skin() so _draw() doesn't look them up every frame.
var _body_color := Color.WHITE
var _highlight_color := Color.WHITE

var _shield_visible := false
var _invulnerable := false
var _last_shield_fx_msec := -10000
var _mouse_steering := false
var _last_wall_hit_msec := -10000
var _revive_ring := 1.0

var _fx_tween: Tween
var _flash_tween: Tween

@onready var player_sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("player")
	_ensure_input_actions()
	visual_radius = radius

	# Find arena.
	var arena := get_node_or_null("../Arena")
	if arena and arena.has_method("get_bounds"):
		arena_rect = arena.get_bounds()

	# Collision shape (hitbox is a bit smaller than the sprite).
	var collision := get_node_or_null("CollisionShape2D")
	if collision and collision.shape is CircleShape2D:
		collision.shape.radius = radius * hit_radius_scale

	_sprite_origin = player_sprite.position
	# Smooth filtering so the skins scale down cleanly.
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	set_skin(skin_index)
	queue_redraw()


## Adds default move_* actions (keyboard + left stick) when the project has none,
## so controls can be rebound in Project Settings without touching this script.
func _ensure_input_actions() -> void:
	for action in MOVE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		if not InputMap.action_get_events(action).is_empty():
			continue
		for key in MOVE_ACTIONS[action]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = key
			InputMap.action_add_event(action, key_event)
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = MOVE_JOY_AXES[action][0]
		axis_event.axis_value = MOVE_JOY_AXES[action][1]
		InputMap.action_add_event(action, axis_event)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Only clicks that reach here were not consumed by the UI, so pressing a
## button never makes the player chase the cursor.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_mouse_steering = true


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_mouse_steering = false


func _read_input() -> Vector2:
	# Touch joystick.
	if touch_enabled and touch_vector != Vector2.ZERO:
		return touch_vector.limit_length(1.0)

	# Keyboard / gamepad.
	var move := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if move != Vector2.ZERO:
		return move

	# Mouse steering (desktop only; touch has its own joystick).
	if not touch_enabled and _mouse_steering and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var to_target := get_global_mouse_position() - global_position
		if to_target.length() > 4.0:
			return (to_target / MOUSE_FULL_SPEED_DISTANCE).limit_length(1.0)

	return Vector2.ZERO


func _update_velocity(current: Vector2, direction: Vector2, delta: float) -> Vector2:
	if direction != Vector2.ZERO:
		return current.move_toward(direction * max_speed, acceleration * delta)
	return current.move_toward(Vector2.ZERO, friction * delta)


func set_touch_vector(value: Vector2) -> void:
	touch_vector = value.limit_length(1.0)


func set_touch_enabled(enabled: bool) -> void:
	touch_enabled = enabled
	if not enabled:
		touch_vector = Vector2.ZERO


# ---------------------------------------------------------------------------
# Process / physics
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	velocity = _update_velocity(velocity, _read_input(), delta)
	move_and_slide()
	clamp_to_arena()

	var speed := velocity.length()
	if rotation_enabled and speed > 10.0:
		_spin += velocity.x * delta * 0.0015 * rotation_multiplier

	# Trail (global positions, so it works wherever the player sits in the tree).
	if trail_enabled and not effects_reduced and speed > 20.0:
		_trail.push_front(global_position)
		if _trail.size() > trail_length:
			_trail.pop_back()
	elif not _trail.is_empty():
		_trail.pop_back()


func _process(delta: float) -> void:
	_pulse_time += delta
	_update_sprite(delta)

	var animated := _shield_visible or _revive_ring < 1.0
	if not is_dead and not effects_reduced:
		animated = animated or pulse_enabled or not _trail.is_empty()
	if _dirty or animated:
		_dirty = false
		queue_redraw()


## Rebuilds the sprite transform: spin, pop (shield / death) and a squash and
## stretch that follows the direction of travel, regardless of the sprite's spin.
func _update_sprite(delta: float) -> void:
	var speed := velocity.length()
	var target := 0.0
	if speed > 5.0:
		target = clampf(speed / max_speed, 0.0, 1.0)
		_stretch_angle = velocity.angle()
	_stretch = lerpf(_stretch, target, minf(1.0, delta * 12.0))

	var body := Transform2D(_spin + _death_spin, Vector2.ZERO).scaled(Vector2.ONE * _base_scale * _pop)
	if _stretch > 0.001:
		var along := 1.0 + 0.10 * _stretch
		var across := 1.0 - 0.06 * _stretch
		var stretch_xf := Transform2D(_stretch_angle, Vector2.ZERO) \
			* Transform2D().scaled(Vector2(along, across)) \
			* Transform2D(-_stretch_angle, Vector2.ZERO)
		body = stretch_xf * body
	body.origin = _sprite_origin
	player_sprite.transform = body

	# Blink while the shield's grace period protects the player.
	var blink := _invulnerable and not is_dead and int(_pulse_time * 14.0) % 2 == 0
	player_sprite.self_modulate.a = 0.45 if blink else 1.0


# ---------------------------------------------------------------------------
# Skin
# ---------------------------------------------------------------------------

func set_skin(index: int) -> void:
	skin_index = clampi(index, 0, SkinCatalog.count() - 1)
	var skin_data := SkinCatalog.get_skin(skin_index)
	_body_color = skin_data.body
	_highlight_color = skin_data.highlight
	if not is_instance_valid(player_sprite):
		return
	player_sprite.texture = SkinCatalog.get_texture(skin_index)
	_refresh_base_scale()
	if not is_dead:
		player_sprite.modulate = Color.WHITE
	_dirty = true


## Sprite scale = visual diameter / actual texture size.
func _refresh_base_scale() -> void:
	var tex_size := SKIN_TEXTURE_SIZE
	if player_sprite.texture:
		tex_size = float(maxi(player_sprite.texture.get_width(), player_sprite.texture.get_height()))
	_base_scale = (radius * 2.0 / tex_size) * skin_scale


# ---------------------------------------------------------------------------
# Effects switches (driven by Game)
# ---------------------------------------------------------------------------

func set_reduced_effects(reduced: bool) -> void:
	effects_reduced = reduced
	if reduced:
		_trail.clear()
	_dirty = true


func set_shield_visible(value: bool) -> void:
	if value != _shield_visible:
		_shield_visible = value
		_dirty = true


func set_invulnerable(value: bool) -> void:
	_invulnerable = value


# ---------------------------------------------------------------------------
# Death / shield
# ---------------------------------------------------------------------------

func die() -> void:
	if is_dead:
		return

	# A shield or grace period absorbs the hit.
	if shield_handler.is_valid() and shield_handler.call():
		_shield_protected_effect()
		return

	is_dead = true
	velocity = Vector2.ZERO
	_trail.clear()
	_kill_tweens()
	player_sprite.self_modulate.a = 1.0

	_fx_tween = create_tween()
	_fx_tween.set_parallel(true)
	_fx_tween.tween_property(player_sprite, "modulate", DEAD_COLOR, 0.15)
	_fx_tween.tween_property(self, "_pop", 1.35, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_property(self, "_death_spin", PI, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dirty = true
	died.emit()


func _shield_protected_effect() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_shield_fx_msec < SHIELD_FX_COOLDOWN_MSEC:
		return
	_last_shield_fx_msec = now

	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_property(self, "_pop", 1.35, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_property(self, "_pop", 1.0, 0.20)

	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	player_sprite.modulate = SHIELD_FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(player_sprite, "modulate", Color.WHITE, 0.30)
	_dirty = true


func _kill_tweens() -> void:
	if _fx_tween and _fx_tween.is_valid():
		_fx_tween.kill()
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()


# ---------------------------------------------------------------------------
# Reset / arena
# ---------------------------------------------------------------------------

func reset() -> void:
	# Cancel a leftover death animation so it can't overwrite the new run.
	_kill_tweens()
	is_dead = false
	velocity = Vector2.ZERO
	position = Vector2.ZERO
	_trail.clear()
	_spin = 0.0
	_death_spin = 0.0
	_pop = 0.3
	_stretch = 0.0
	_shield_visible = false
	_invulnerable = false
	_mouse_steering = false
	_revive_ring = 1.0
	player_sprite.modulate = Color.WHITE
	player_sprite.self_modulate.a = 1.0
	set_skin(skin_index)
	# Pop in at the start of a run.
	_fx_tween = create_tween()
	_fx_tween.tween_property(self, "_pop", 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_dirty = true


## Brings the player back after dying (gem revive). Position is kept.
func revive() -> void:
	_kill_tweens()
	is_dead = false
	velocity = Vector2.ZERO
	_trail.clear()
	_death_spin = 0.0
	_pop = 0.4
	_revive_ring = 0.0
	player_sprite.modulate = Color.WHITE
	player_sprite.self_modulate.a = 1.0
	_fx_tween = create_tween().set_parallel(true)
	_fx_tween.tween_property(self, "_pop", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fx_tween.tween_property(self, "_revive_ring", 1.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dirty = true


func clamp_to_arena() -> void:
	var min_pos := arena_rect.position + Vector2(radius, radius)
	var max_pos := arena_rect.end - Vector2(radius, radius)
	var clamped := position.clamp(min_pos, max_pos)
	# Stop pushing into a wall instead of building up speed against it.
	var impact := 0.0
	if clamped.x != position.x:
		impact = maxf(impact, absf(velocity.x))
		velocity.x = 0.0
	if clamped.y != position.y:
		impact = maxf(impact, absf(velocity.y))
		velocity.y = 0.0
	position = clamped
	if impact >= WALL_HIT_MIN_SPEED:
		var now := Time.get_ticks_msec()
		if now - _last_wall_hit_msec >= WALL_HIT_COOLDOWN_MSEC:
			_last_wall_hit_msec = now
			wall_hit.emit(global_position, clampf(impact / max_speed, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not is_dead and not effects_reduced:
		_draw_trail(_body_color)
		if pulse_enabled:
			_draw_pulse(_highlight_color)

	if _shield_visible and not is_dead:
		_draw_shield()

	if is_dead:
		draw_arc(Vector2.ZERO, radius * 1.35, 0.0, TAU, 32, Color(1.0, 0.15, 0.15, 0.55), 2.0)

	if _revive_ring < 1.0:
		var ring_radius := lerpf(radius, radius * 5.0, _revive_ring)
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48, Color(REVIVE_RING_COLOR, 1.0 - _revive_ring), 5.0 * (1.0 - _revive_ring) + 1.0)


func _draw_trail(body_color: Color) -> void:
	if not trail_enabled or _trail.size() < 2:
		return
	var last := float(maxi(1, _trail.size() - 1))
	var dot := FXScript.get_dot()
	for i in range(_trail.size() - 1):
		var ratio := float(i) / last
		var r := lerpf(visual_radius * 0.75, visual_radius * 0.20, ratio)
		var c := to_local(_trail[i])
		# Textured quad instead of draw_circle (about 50x cheaper per call).
		draw_texture_rect(dot, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, Color(body_color, (1.0 - ratio) * 0.22))


## Gentle breathing ring. Drawn whenever the player is alive, even when standing still.
func _draw_pulse(highlight_color: Color) -> void:
	var pulse := sin(_pulse_time * 3.0) * 0.5 + 0.5
	var pulse_radius := radius + 3.0 + pulse * 3.0
	draw_arc(Vector2.ZERO, pulse_radius, 0.0, TAU, 32, Color(highlight_color, 0.18 - pulse * 0.10), 1.5)


func _draw_shield() -> void:
	var pulse := sin(_pulse_time * 5.0) * 0.5 + 0.5
	var ring_radius := radius + 8.0 + pulse * 2.0
	draw_circle(Vector2.ZERO, ring_radius, Color(SHIELD_RING_COLOR, 0.10 + 0.06 * pulse))
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 40, Color(SHIELD_RING_COLOR, 0.65 + 0.3 * pulse), 2.5)
