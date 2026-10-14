extends Node2D

## Lightweight world-space particle layer (bursts, rings, sparks).
## One node draws everything. Particles are textured quads (a cached soft
## dot), which is far cheaper than draw_circle on phones.

const MAX_PARTICLES := 320
const MAX_RINGS := 12

class _Particle extends RefCounted:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var color := Color.WHITE
	var size := 3.0
	var life := 0.5
	var age := 0.0
	var gravity := 0.0
	var drag := 2.5

class _Ring extends RefCounted:
	var pos := Vector2.ZERO
	var color := Color.WHITE
	var from_radius := 10.0
	var to_radius := 80.0
	var width := 4.0
	var life := 0.4
	var age := 0.0

static var _dot_tex: Texture2D

var reduced := false

var _particles: Array[_Particle] = []
var _rings: Array[_Ring] = []
var _was_empty := true


## Shared white anti-aliased dot. Tint it with the draw colour.
static func get_dot() -> Texture2D:
	if _dot_tex == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (n - 1) * 0.5
		for y in range(n):
			for x in range(n):
				var d := Vector2(x - c, y - c).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(c + 0.5 - d, 0.0, 1.0)))
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	get_dot()


func set_reduced(value: bool) -> void:
	reduced = value
	if value:
		clear()


func clear() -> void:
	_particles.clear()
	_rings.clear()
	queue_redraw()


## Radial burst of dots.
func burst(pos: Vector2, color: Color, count: int, speed: float, life := 0.6, size := 3.5, gravity := 0.0) -> void:
	if reduced:
		count = int(count * 0.4)
	for i in range(count):
		if _particles.size() >= MAX_PARTICLES:
			_particles.pop_front()
		var p := _Particle.new()
		var angle := randf() * TAU
		var spd := speed * randf_range(0.35, 1.0)
		p.pos = pos
		p.vel = Vector2.from_angle(angle) * spd
		p.color = color.lerp(Color.WHITE, randf() * 0.35)
		p.size = size * randf_range(0.6, 1.3)
		p.life = life * randf_range(0.7, 1.2)
		p.gravity = gravity
		_particles.append(p)


## Expanding ring (shockwave).
func ring(pos: Vector2, color: Color, from_radius := 12.0, to_radius := 90.0, life := 0.4, width := 4.0) -> void:
	if reduced:
		return
	if _rings.size() >= MAX_RINGS:
		_rings.pop_front()
	var r := _Ring.new()
	r.pos = pos
	r.color = color
	r.from_radius = from_radius
	r.to_radius = to_radius
	r.life = life
	r.width = width
	_rings.append(r)


func _process(delta: float) -> void:
	var empty := _particles.is_empty() and _rings.is_empty()
	if empty:
		if not _was_empty:
			_was_empty = true
			queue_redraw()
		return
	_was_empty = false

	for i in range(_particles.size() - 1, -1, -1):
		var p := _particles[i]
		p.age += delta
		if p.age >= p.life:
			# Swap-remove is O(1); draw order of particles does not matter.
			_particles[i] = _particles[_particles.size() - 1]
			_particles.pop_back()
			continue
		p.vel *= maxf(0.0, 1.0 - p.drag * delta)
		p.vel.y += p.gravity * delta
		p.pos += p.vel * delta
	for i in range(_rings.size() - 1, -1, -1):
		var r := _rings[i]
		r.age += delta
		if r.age >= r.life:
			_rings.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for r in _rings:
		var k := r.age / r.life
		var eased := 1.0 - pow(1.0 - k, 3.0)
		var radius := lerpf(r.from_radius, r.to_radius, eased)
		var col := Color(r.color, r.color.a * (1.0 - k))
		draw_arc(r.pos, radius, 0.0, TAU, 28, col, maxf(1.0, r.width * (1.0 - k * 0.6)))
	var tex := _dot_tex
	for p in _particles:
		var k := p.age / p.life
		var rad := maxf(0.5, p.size * (1.0 - k * 0.7))
		draw_texture_rect(tex, Rect2(p.pos.x - rad, p.pos.y - rad, rad * 2.0, rad * 2.0), false,
				Color(p.color, p.color.a * (1.0 - k)))
