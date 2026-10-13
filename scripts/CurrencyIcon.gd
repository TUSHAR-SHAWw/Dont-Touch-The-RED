extends Control

## Coin / gem icon drawn in code, so no new texture assets are needed.

enum Kind { COIN, GEM }

@export var kind: Kind = Kind.COIN:
	set(value):
		kind = value
		queue_redraw()
@export var animated := true

const GEM_LIGHT := Color("#c4f9ff")
const GEM_MID := Color("#3ddcff")
const GEM_DARK := Color("#14a8d8")
const GEM_DEEP := Color("#0b73a8")
const GEM_LINE := Color("#06384f")

var _t := 0.0
var _burst := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(28, 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = randf() * 6.0


## Quick bright flash, used when the currency is gained.
func sparkle() -> void:
	_burst = 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not animated and _burst <= 0.0:
		return
	_t += delta
	_burst = maxf(0.0, _burst - delta * 2.2)
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		return
	var x_scale := 1.0
	if animated:
		x_scale = 0.2 + 0.8 * absf(cos(_t * 2.0)) if kind == Kind.COIN else 1.0 - absf(sin(_t * 1.4)) * 0.16
	draw_set_transform(Vector2(size.x * 0.5, (size.y - s) * 0.5), 0.0, Vector2(x_scale, 1.0))
	if kind == Kind.GEM:
		_draw_gem(s)
	else:
		_draw_coin(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _pt(x: float, y: float, s: float) -> Vector2:
	return Vector2((x - 0.5) * s, y * s)


func _poly(points: Array, s: float, color: Color) -> void:
	var packed := PackedVector2Array()
	for p in points:
		packed.append(_pt(p[0], p[1], s))
	draw_colored_polygon(packed, color)


func _draw_gem(s: float) -> void:
	_poly([[0.25, 0.12], [0.75, 0.12], [0.62, 0.38], [0.38, 0.38]], s, GEM_LIGHT)
	_poly([[0.25, 0.12], [0.0, 0.38], [0.38, 0.38]], s, GEM_MID)
	_poly([[0.75, 0.12], [1.0, 0.38], [0.62, 0.38]], s, GEM_DARK)
	_poly([[0.0, 0.38], [0.38, 0.38], [0.5, 0.96]], s, GEM_MID)
	_poly([[0.38, 0.38], [0.62, 0.38], [0.5, 0.96]], s, GEM_DARK)
	_poly([[0.62, 0.38], [1.0, 0.38], [0.5, 0.96]], s, GEM_DEEP)
	var outline := PackedVector2Array([
		_pt(0.25, 0.12, s), _pt(0.75, 0.12, s), _pt(1.0, 0.38, s),
		_pt(0.5, 0.96, s), _pt(0.0, 0.38, s), _pt(0.25, 0.12, s)])
	draw_polyline(outline, GEM_LINE, maxf(1.0, s * 0.05))
	var glint := 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * 3.0)) + _burst
	var c := _pt(0.3, 0.24, s)
	var r := s * (0.09 + 0.1 * _burst)
	var col := Color(1, 1, 1, clampf(glint, 0.0, 1.0))
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, maxf(1.0, s * 0.045))
	draw_line(c - Vector2(0, r), c + Vector2(0, r), col, maxf(1.0, s * 0.045))


func _draw_coin(s: float) -> void:
	var center := Vector2(0.0, s * 0.5)
	var r := s * 0.46
	draw_circle(center, r, Color("#a8700a"))
	draw_circle(center, r * 0.9, Color("#f6c744"))
	draw_arc(center, r * 0.62, 0.0, TAU, 28, Color("#c58b12"), maxf(1.0, s * 0.07))
	draw_arc(center, r * 0.8, PI * 1.1, PI * 1.6, 10, Color(1, 1, 1, 0.55 + _burst * 0.4), maxf(1.0, s * 0.06))
