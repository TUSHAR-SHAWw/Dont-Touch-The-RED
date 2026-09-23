extends Camera2D

## Keeps the whole arena in view on any screen size / aspect ratio.
## Recalculates zoom whenever the viewport is resized.

@export var arena_size := Vector2(800, 600)
@export var side_margin := 60.0
@export var bottom_margin := 40.0
@export var ui_top_reserve := 92.0  # HUD bar height in pixels at base 720

var _shake_time := 0.0
var _shake_strength := 0.0
var _base_position := Vector2.ZERO
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

func _process(delta: float) -> void:
	if _shake_time <= 0.0:
		position = _base_position
		return
	_shake_time -= delta
	var fade := clampf(_shake_time / 0.24, 0.0, 1.0)
	position = _base_position + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * fade

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
	zoom = Vector2(z, z)
