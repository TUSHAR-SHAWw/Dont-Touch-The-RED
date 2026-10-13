extends Camera2D

## Keeps the whole arena in view on any screen size / aspect ratio.
## Recalculates zoom whenever the viewport is resized.
## Also provides screen shake and a short zoom "punch" for impact moments.

@export var arena_size := Vector2(800, 600)
@export var side_margin := 60.0
@export var bottom_margin := 40.0
@export var ui_top_reserve := 92.0  # HUD bar height in pixels at base 720

var _shake_time := 0.0
var _shake_strength := 0.0
var _base_position := Vector2.ZERO
var _base_zoom := Vector2.ONE
var _punch := 0.0
var _punch_time := 0.0
var _punch_duration := 0.001
var shake_enabled := true


func _ready() -> void:
	_base_position = position
	_fit()
	get_viewport().size_changed.connect(_fit)


func shake(strength: float, duration: float) -> void:
	if not shake_enabled:
		return
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = maxf(_shake_time, duration)


## Brief zoom-in that eases back out. `amount` 0.05 = 5% closer.
func punch(amount: float, duration := 0.25) -> void:
	if not shake_enabled:
		return
	_punch = maxf(_punch, amount)
	_punch_duration = maxf(duration, 0.01)
	_punch_time = _punch_duration


func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta
		var fade := clampf(_shake_time / 0.24, 0.0, 1.0)
		position = _base_position + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * fade
		if _shake_time <= 0.0:
			_shake_strength = 0.0
	else:
		position = _base_position

	if _punch_time > 0.0:
		_punch_time -= delta
		var k := clampf(_punch_time / _punch_duration, 0.0, 1.0)
		zoom = _base_zoom * (1.0 + _punch * k * k)
		if _punch_time <= 0.0:
			_punch = 0.0
			zoom = _base_zoom


func _fit() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	# Calculate world units needed. We must fit arena + margins.
	var needed := arena_size + Vector2(side_margin * 2.0, bottom_margin)

	# Initial estimate for zoom to determine HUD world height
	var z := minf(vp.x / needed.x, vp.y / needed.y)
	if z <= 0.0:
		return

	var hud_world := ui_top_reserve / z
	needed.y = arena_size.y + hud_world + bottom_margin

	# Final zoom calculation
	z = minf(vp.x / needed.x, vp.y / needed.y)
	_base_zoom = Vector2(z, z)
	if _punch_time <= 0.0:
		zoom = _base_zoom
