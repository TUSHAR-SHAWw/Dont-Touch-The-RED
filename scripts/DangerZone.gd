extends Area2D

## A single dangerous area. Lives through warning -> active -> done.
## While WARNING it is only a translucent, pulsing preview (not lethal).
## Once ACTIVE it becomes solid red and kills the player on contact.
##
## Kinds:
##   RECTANGLE   plain box
##   SPIKES      box with spikes drawn on the edge facing the arena centre
##   MOVING_WALL box that swings back and forth along an axis
##   ZIGZAG      box with a zigzag marking
##   PINWHEEL    box that can spin (set spin_speed)
##   LASER       thin beam with a bright core (short active time)
##   CIRCLE      round blast zone (circular collider)
##   SLIDER      box that slides once from its start to start + axis * range
##   SWEEPER     long thin bar that spins around its centre

signal warning_started
signal activated
signal finished

enum Phase { WARNING, ACTIVE, DONE }
enum Kind { RECTANGLE, SPIKES, MOVING_WALL, ZIGZAG, PINWHEEL, LASER, CIRCLE, SLIDER, SWEEPER }

const WARNING_COLOR := Color("#8a1616")
const ACTIVE_COLOR := Color("#e02323")
const ACTIVE_FILL := Color("#d91f3a")
const ACTIVE_BORDER := Color("#6d0d0d")
const HAZARD_YELLOW := Color("#ffcf55")
const FLASH_TIME := 0.22
const FADE_TIME := 0.14
## SLIDER finishes its move after this fraction of the active time, then holds.
const SLIDE_FRACTION := 0.6

@export var warning_time := 1.2
@export var active_time := 2.0

var size_now := Vector2(200, 200)
var target_size := Vector2.ZERO
var grow_speed := 0.0
var kind := Kind.RECTANGLE
var motion_axis := Vector2.ZERO
var motion_origin := Vector2.ZERO
var motion_range := 0.0
## Radians per second, applied only while ACTIVE.
var spin_speed := 0.0

var phase := Phase.WARNING

var _phase_time := 0.0
var _flash := 0.0
var _base_rotation := 0.0
var _dirty := true
var _shape: Shape2D
var _collider: CollisionShape2D
# PINWHEEL is a plus: the main collider is the horizontal arm, this is the vertical one.
var _shape_b: RectangleShape2D
var _collider_b: CollisionShape2D
var _already_hit: Array[Node] = []


## Configure the zone before adding it to the tree.
func setup(new_size: Vector2, target: Vector2, warn: float, act: float, grow: float, new_kind := Kind.RECTANGLE, new_motion_axis := Vector2.ZERO, new_motion_range := 0.0) -> void:
	size_now = new_size
	target_size = target
	warning_time = warn
	active_time = act
	grow_speed = grow
	kind = new_kind
	motion_axis = new_motion_axis
	motion_range = new_motion_range


func _ready() -> void:
	_base_rotation = rotation
	if motion_origin == Vector2.ZERO:
		motion_origin = position

	if kind == Kind.CIRCLE:
		_shape = CircleShape2D.new()
	else:
		_shape = RectangleShape2D.new()
	_update_shape()
	_collider = CollisionShape2D.new()
	_collider.shape = _shape
	_collider.disabled = true
	add_child(_collider)
	if kind == Kind.PINWHEEL:
		_shape_b = RectangleShape2D.new()
		_collider_b = CollisionShape2D.new()
		_collider_b.shape = _shape_b
		_collider_b.disabled = true
		add_child(_collider_b)
		_update_shape()

	# Detect the player (PhysicsBody2D on collision layer 1).
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false

	# Deferred so listeners that connect right after add_child still receive it.
	call_deferred("emit_signal", "warning_started")
	queue_redraw()


func is_active() -> bool:
	return phase == Phase.ACTIVE


## True from spawn until the zone has finished (warning and active).
func is_alive() -> bool:
	return phase != Phase.DONE


## Conservative world-space bounds used by the spawner's fairness check.
## Covers everything the zone can touch, not only where it is right now.
func get_danger_rect() -> Rect2:
	var half_extent := size_now / 2.0
	if spin_speed != 0.0 or kind == Kind.SWEEPER:
		var reach := maxf(size_now.x, size_now.y) / 2.0
		return Rect2(position - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	var home := Rect2(motion_origin - half_extent, size_now)
	var offset := motion_axis * motion_range
	match kind:
		Kind.MOVING_WALL:
			return home.merge(_shifted(home, offset)).merge(_shifted(home, -offset))
		Kind.SLIDER:
			return home.merge(_shifted(home, offset))
	return Rect2(position - half_extent, size_now)


func _shifted(rect: Rect2, offset: Vector2) -> Rect2:
	return Rect2(rect.position + offset, rect.size)


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	_phase_time += delta

	if phase == Phase.WARNING:
		_dirty = true  # pulse + countdown fill
		if _phase_time >= warning_time:
			_activate()
	else:
		_step_active(delta)

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		_dirty = true
	if _dirty:
		queue_redraw()


func _activate() -> void:
	phase = Phase.ACTIVE
	_phase_time = 0.0  # from here on _phase_time is time since activation
	_flash = FLASH_TIME
	modulate.a = 0.78
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_update_shape()
	_collider.set_deferred("disabled", false)
	if _collider_b:
		_collider_b.set_deferred("disabled", false)
	_dirty = true
	activated.emit()


func _step_active(delta: float) -> void:
	if _phase_time >= active_time:
		_finish()
		return
	_apply_motion()
	# Growth only starts once lethal, so it ends exactly when the zone does.
	if target_size != Vector2.ZERO and size_now != target_size:
		size_now = size_now.move_toward(target_size, grow_speed * delta)
		_update_shape()
		_dirty = true
	_kill_overlapping_bodies()


func _apply_motion() -> void:
	match kind:
		Kind.MOVING_WALL:
			position = motion_origin + motion_axis * sin(_phase_time * 2.0) * motion_range
		Kind.SLIDER:
			var k := clampf(_phase_time / (active_time * SLIDE_FRACTION), 0.0, 1.0)
			position = motion_origin + motion_axis * motion_range * smoothstep(0.0, 1.0, k)
	if spin_speed != 0.0:
		rotation = _base_rotation + spin_speed * _phase_time


func _finish() -> void:
	phase = Phase.DONE
	_collider.set_deferred("disabled", true)
	if _collider_b:
		_collider_b.set_deferred("disabled", true)
	set_deferred("monitoring", false)
	finished.emit()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)
	queue_redraw()


func _update_shape() -> void:
	if _shape is CircleShape2D:
		(_shape as CircleShape2D).radius = size_now.x / 2.0
	elif _shape is RectangleShape2D:
		(_shape as RectangleShape2D).size = size_now
	if _shape_b:
		_shape_b.size = Vector2(size_now.y, size_now.x)


## Polling (instead of body_entered) also catches a player who is already
## standing inside when the zone turns lethal, or who is swept by a moving one.
func _kill_overlapping_bodies() -> void:
	for body in get_overlapping_bodies():
		if body in _already_hit:
			continue
		if body.is_in_group("player") and body.has_method("die"):
			_already_hit.append(body)
			body.die()


# ---------------------------------------------------------------------------
# Drawing (local space; the node's own rotation/position are applied for us)
# ---------------------------------------------------------------------------

func _draw() -> void:
	var rect := Rect2(-size_now / 2.0, size_now)
	if phase == Phase.WARNING:
		_draw_warning(rect)
	else:
		_draw_active(rect)
	_dirty = false


func _warning_progress() -> float:
	return clampf(_phase_time / maxf(warning_time, 0.001), 0.0, 1.0)


func _draw_warning(rect: Rect2) -> void:
	var p := _warning_progress()
	# The pulse speeds up as the zone is about to go live.
	var pulse := 0.5 + 0.5 * sin(_phase_time * TAU * lerpf(1.5, 5.0, p))
	var fill := Color(WARNING_COLOR, lerpf(0.12, 0.34, p) + 0.12 * pulse)
	var border := Color(ACTIVE_COLOR, 0.4 + 0.6 * pulse)
	var line_w := 3.0 + 2.0 * pulse

	# Expanding zones show where they will end up.
	if target_size != Vector2.ZERO:
		draw_rect(Rect2(-target_size / 2.0, target_size), Color(ACTIVE_COLOR, 0.3), false, 2.0)

	match kind:
		Kind.CIRCLE:
			var r := size_now.x / 2.0
			draw_circle(Vector2.ZERO, r, fill)
			draw_circle(Vector2.ZERO, r * p, Color(ACTIVE_COLOR, 0.3))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, border, line_w)
		Kind.LASER:
			_draw_laser_warning(rect, p, pulse)
		Kind.PINWHEEL:
			var plus := _plus_points()
			draw_colored_polygon(plus, fill)
			draw_colored_polygon(_scaled(plus, p), Color(ACTIVE_COLOR, 0.22))
			_draw_closed(plus, border, line_w)
		_:
			draw_rect(rect, fill)
			# Fills from the centre outwards: a visible countdown.
			draw_rect(Rect2(-size_now * p / 2.0, size_now * p), Color(ACTIVE_COLOR, 0.22))
			draw_rect(rect, border, false, line_w)

	if kind == Kind.MOVING_WALL or kind == Kind.SLIDER:
		_draw_motion_preview(rect, border)
	if spin_speed != 0.0:
		_draw_spin_hint(maxf(size_now.x, size_now.y) * 0.32, border)
	if kind != Kind.LASER:
		_draw_warning_mark(pulse)


func _draw_active(rect: Rect2) -> void:
	match kind:
		Kind.CIRCLE:
			_draw_circle_active()
		Kind.LASER:
			_draw_laser_active(rect)
		Kind.PINWHEEL:
			_draw_pinwheel_active()
		_:
			draw_rect(rect, ACTIVE_FILL)
			_draw_active_stripes(rect)
			match kind:
				Kind.SPIKES:
					_draw_spikes(rect, ACTIVE_BORDER)
				Kind.MOVING_WALL, Kind.SLIDER:
					_draw_axis_line(rect, Color.WHITE)
				Kind.ZIGZAG:
					_draw_zigzag(rect)
				Kind.SWEEPER:
					_draw_sweeper_marks()
			# Inset so the border never sticks out past the hitbox.
			draw_rect(rect.grow(-2.0), ACTIVE_BORDER, false, 4.0)
	_draw_flash(rect)


func _draw_flash(rect: Rect2) -> void:
	if _flash <= 0.0:
		return
	var k := _flash / FLASH_TIME
	var burst := 1.0 + (FLASH_TIME - _flash) * 2.5
	var color := Color(1.0, 0.35, 0.35, k)
	if kind == Kind.CIRCLE:
		draw_arc(Vector2.ZERO, size_now.x / 2.0 * burst, 0.0, TAU, 48, color, 8.0)
	elif kind == Kind.PINWHEEL:
		_draw_closed(_scaled(_plus_points(), burst), color, 8.0)
	else:
		draw_rect(Rect2(-size_now * burst / 2.0, size_now * burst), color, false, 8.0)


## Outline of the plus (union of both arms) so nothing is drawn across the middle.
func _plus_points() -> PackedVector2Array:
	var a := size_now.x / 2.0  # half arm length
	var w := size_now.y / 2.0  # half arm width
	return PackedVector2Array([
		Vector2(-w, -a), Vector2(w, -a), Vector2(w, -w), Vector2(a, -w),
		Vector2(a, w), Vector2(w, w), Vector2(w, a), Vector2(-w, a),
		Vector2(-w, w), Vector2(-a, w), Vector2(-a, -w), Vector2(-w, -w),
	])


func _scaled(points: PackedVector2Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(point * k)
	return out


func _draw_closed(points: PackedVector2Array, color: Color, width: float) -> void:
	var loop := points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, color, width)


func _draw_pinwheel_active() -> void:
	var plus := _plus_points()
	var a := size_now.x / 2.0
	draw_colored_polygon(plus, ACTIVE_FILL)
	# Centre lines along both arms, then one hub on top.
	draw_line(Vector2(-a + 8.0, 0.0), Vector2(a - 8.0, 0.0), HAZARD_YELLOW, 3.0)
	draw_line(Vector2(0.0, -a + 8.0), Vector2(0.0, a - 8.0), HAZARD_YELLOW, 3.0)
	_draw_closed(plus, ACTIVE_BORDER, 4.0)
	draw_circle(Vector2.ZERO, size_now.y * 0.55, ACTIVE_BORDER)
	draw_circle(Vector2.ZERO, size_now.y * 0.25, HAZARD_YELLOW)


func _draw_circle_active() -> void:
	var r := size_now.x / 2.0
	draw_circle(Vector2.ZERO, r, ACTIVE_FILL)
	draw_circle(Vector2.ZERO, r * 0.55, Color(1.0, 0.55, 0.18, 0.3))
	draw_arc(Vector2.ZERO, r - 2.0, 0.0, TAU, 48, ACTIVE_BORDER, 4.0)


func _draw_laser_warning(rect: Rect2, p: float, pulse: float) -> void:
	var tall := rect.size.y > rect.size.x
	var from := Vector2(0.0, rect.position.y) if tall else Vector2(rect.position.x, 0.0)
	var to := Vector2(0.0, rect.end.y) if tall else Vector2(rect.end.x, 0.0)
	draw_rect(rect, Color(WARNING_COLOR, 0.12 + 0.25 * p))
	draw_dashed_line(from, to, Color(ACTIVE_COLOR, 0.5 + 0.5 * pulse), 2.0 + 2.0 * p, 14.0)


func _draw_laser_active(rect: Rect2) -> void:
	draw_rect(rect, Color(ACTIVE_COLOR, 0.55))
	draw_rect(rect.grow(-minf(rect.size.x, rect.size.y) * 0.3), Color(1.0, 0.92, 0.92))


func _draw_motion_preview(rect: Rect2, color: Color) -> void:
	var ghost := Color(color, 0.35)
	var offset := motion_axis * motion_range
	var tips: Array[Vector2] = [offset]
	if kind == Kind.MOVING_WALL:
		tips.append(-offset)
	for tip in tips:
		draw_rect(Rect2(rect.position + tip, rect.size), ghost, false, 2.0)
		draw_line(Vector2.ZERO, tip, ghost, 2.0)


func _draw_spin_hint(radius: float, color: Color) -> void:
	var dir_sign := signf(spin_speed)
	var a := dir_sign * 1.4
	draw_arc(Vector2.ZERO, radius, 0.0, a, 20, color, 3.0)
	var tip := Vector2.from_angle(a) * radius
	var normal := Vector2.from_angle(a)
	var tangent := Vector2.from_angle(a + dir_sign * PI / 2.0)
	draw_line(tip, tip - tangent * 12.0 + normal * 7.0, color, 3.0)
	draw_line(tip, tip - tangent * 12.0 - normal * 7.0, color, 3.0)


func _draw_warning_mark(pulse: float) -> void:
	var mark_color := Color(1.0, 0.72, 0.25, 0.6 + 0.4 * pulse)
	# Cancel the node's rotation so the "!" always stays upright.
	draw_set_transform(Vector2.ZERO, -rotation)
	draw_circle(Vector2.ZERO, 15.0, Color(0.35, 0.03, 0.05, 0.35))
	draw_line(Vector2(0.0, -8.0), Vector2(0.0, 3.0), mark_color, 4.0)
	draw_circle(Vector2(0.0, 9.0), 2.5, mark_color)
	draw_set_transform(Vector2.ZERO, 0.0)


func _draw_active_stripes(rect: Rect2) -> void:
	var h := rect.size.y
	if h <= 0.0:
		return
	var stripe_color := Color(1.0, 0.55, 0.18, 0.28)
	# 45 degree stripes, clipped horizontally so none leak outside the hitbox.
	for x in range(int(rect.position.x - h), int(rect.end.x), 24):
		var t0 := clampf((rect.position.x - x) / h, 0.0, 1.0)
		var t1 := clampf((rect.end.x - x) / h, 0.0, 1.0)
		if t1 <= t0:
			continue
		draw_line(
			Vector2(x + t0 * h, rect.end.y - t0 * h),
			Vector2(x + t1 * h, rect.end.y - t1 * h),
			stripe_color, 5.0)


## Spikes sit inside the zone, pointing at the arena centre (never outside it).
func _draw_spikes(rect: Rect2, color: Color) -> void:
	var tall := rect.size.y > rect.size.x
	var dir := Vector2.ZERO
	if tall:
		dir = Vector2(-signf(position.x) if position.x != 0.0 else 1.0, 0.0)
	else:
		dir = Vector2(0.0, -signf(position.y) if position.y != 0.0 else 1.0)
	var along := Vector2.DOWN if tall else Vector2.RIGHT
	var length := rect.size.y if tall else rect.size.x
	var edge_start := Vector2.ZERO
	if tall:
		edge_start = Vector2(rect.end.x if dir.x > 0.0 else rect.position.x, rect.position.y)
	else:
		edge_start = Vector2(rect.position.x, rect.end.y if dir.y > 0.0 else rect.position.y)
	var count := maxi(3, int(length / 28.0))
	var step := length / count
	for i in range(count):
		var a := edge_start + along * step * i
		var points := PackedVector2Array([
			a - dir * 14.0,
			a + along * step / 2.0,
			a + along * step - dir * 14.0,
		])
		draw_colored_polygon(points, color)


func _draw_zigzag(rect: Rect2) -> void:
	var pad := 6.0
	var points := PackedVector2Array()
	for i in range(7):
		var x := rect.position.x + rect.size.x * float(i) / 6.0
		var y := (rect.end.y - pad) if i % 2 == 0 else (rect.position.y + pad)
		points.append(Vector2(x, y))
	draw_polyline(points, HAZARD_YELLOW, 5.0)


func _draw_axis_line(rect: Rect2, color: Color) -> void:
	if rect.size.y > rect.size.x:
		draw_line(Vector2(0.0, rect.position.y + 4.0), Vector2(0.0, rect.end.y - 4.0), color, 2.0)
	else:
		draw_line(Vector2(rect.position.x + 4.0, 0.0), Vector2(rect.end.x - 4.0, 0.0), color, 2.0)


func _draw_sweeper_marks() -> void:
	draw_circle(Vector2.ZERO, size_now.y * 0.9, ACTIVE_BORDER)
	draw_circle(Vector2.ZERO, size_now.y * 0.4, HAZARD_YELLOW)
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(side * (size_now.x / 2.0 - size_now.y * 0.5), 0.0), size_now.y * 0.3, Color.WHITE)
