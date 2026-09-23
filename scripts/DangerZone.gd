extends Area2D

## A single dangerous red area. Lives through warning -> active -> done.
## While WARNING the zone is only a translucent pulsing preview (not lethal).
## Once ACTIVE it becomes solid red and kills the player on contact.

signal warning_started
signal activated
signal finished

enum Phase { WARNING, ACTIVE, DONE }
enum Kind { RECTANGLE, SPIKES, MOVING_WALL, ZIGZAG, PINWHEEL }

@export var warning_time := 1.2
@export var active_time := 2.0

var size_now := Vector2(200, 200)
var target_size := Vector2.ZERO
var grow_speed := 0.0
var _activation_flash := 0.0
var kind := Kind.RECTANGLE
var motion_axis := Vector2.ZERO
var motion_origin := Vector2.ZERO
var motion_range := 0.0
var motion_time := 0.0

var phase := Phase.WARNING

var _dirty := true

var _redraw_timer := 0.0

var _last_drawn_size := Vector2.ZERO

var _last_drawn_phase := Phase.WARNING

var _last_draw_flash := 0.0


const WARNING_COLOR := Color("#8a1616")
const ACTIVE_COLOR := Color("#e02323")
const ACTIVE_BORDER := Color("#6d0d0d")

var _shape: RectangleShape2D
var _collider: CollisionShape2D

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
	_shape = RectangleShape2D.new()
	_collider = CollisionShape2D.new()
	_collider.shape = _shape
	_collider.disabled = true
	add_child(_collider)

	# Detect the player (PhysicsBody2D on collision layer 1).
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false

	body_entered.connect(_on_body_entered)
	warning_started.emit()
	_start_warning()

func _start_warning() -> void:
	phase = Phase.WARNING
	_dirty = true
	_last_drawn_phase = Phase.WARNING
	get_tree().create_timer(warning_time, false).timeout.connect(_activate)
	queue_redraw()

func _activate() -> void:
	phase = Phase.ACTIVE
	_activation_flash = 0.22
	modulate = Color(1.0, 1.0, 1.0, 0.78)
	var activation_tween := create_tween()
	activation_tween.tween_property(self, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_update_collider()
	activated.emit()
	_dirty = true
	_last_drawn_phase = Phase.ACTIVE
	queue_redraw()
	get_tree().create_timer(active_time, false).timeout.connect(_finish)

func _finish() -> void:
	phase = Phase.DONE
	_collider.set_deferred("disabled", true)
	monitoring = false
	_dirty = true
	_last_drawn_phase = Phase.DONE
	finished.emit()
	var finish_tween := create_tween()
	finish_tween.tween_property(self, "modulate:a", 0.0, 0.14)
	finish_tween.tween_callback(queue_free)

func is_active() -> bool:
	return phase == Phase.ACTIVE

func get_danger_rect() -> Rect2:
	return Rect2(position - size_now / 2.0, size_now)

func _physics_process(delta: float) -> void:
	motion_time += delta
	if kind == Kind.MOVING_WALL and phase != Phase.DONE:
		# _draw() works in local space, so moving the node needs no redraw.
		position = motion_origin + motion_axis * sin(motion_time * 2.0) * motion_range
	if phase == Phase.WARNING:
		# The warning preview pulses, so keep a throttled redraw alive.
		_redraw_timer += delta
		if _redraw_timer >= 0.05:
			_redraw_timer = 0.0
			_dirty = true
	_activation_flash = maxf(0.0, _activation_flash - delta)
	if _activation_flash > 0.0 and phase == Phase.ACTIVE:
		_dirty = true
	if target_size != Vector2.ZERO and size_now != target_size:
		size_now = size_now.move_toward(target_size, grow_speed * delta)
		if phase != Phase.WARNING:
			_update_collider()
		_dirty = true

	if _dirty:
		queue_redraw()

func _update_collider() -> void:
	_shape.size = size_now
	_collider.set_deferred("disabled", false)

func _on_body_entered(body: Node) -> void:
	if phase == Phase.ACTIVE and body.is_in_group("player") and body.has_method("die"):
		body.die()

func _draw() -> void:
	var rect := Rect2(-size_now / 2.0, size_now)
	if phase == Phase.WARNING:
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := 0.5 + 0.5 * sin(t * TAU * 2.0)
		var fill := WARNING_COLOR
		fill.a = 0.20 + 0.30 * pulse
		draw_rect(rect, fill)
		var border := WARNING_COLOR
		border.a = 0.4 + 0.6 * pulse
		_draw_warning_marks(rect, border)
		draw_rect(rect, border, false, 3.0 + 2.0 * pulse)
	else:
		draw_rect(rect, Color("#d91f3a"))
		draw_rect(rect, ACTIVE_BORDER, false, 4.0)
		_draw_active_stripes(rect)
		if kind == Kind.SPIKES:
			_draw_spikes(rect, ACTIVE_BORDER)
		elif kind == Kind.MOVING_WALL:
			draw_line(Vector2(-size_now.x / 2.0, 0.0), Vector2(size_now.x / 2.0, 0.0), Color.WHITE, 2.0)
		elif kind == Kind.ZIGZAG:
			_draw_zigzag(rect)
		elif kind == Kind.PINWHEEL:
			_draw_pinwheel(rect)
		if _activation_flash > 0.0:
			var burst := 1.0 + (0.22 - _activation_flash) * 2.5
			var burst_rect := Rect2(-size_now * burst / 2.0, size_now * burst)
			var burst_color := Color(1.0, 0.35, 0.35, _activation_flash / 0.22)
			draw_rect(burst_rect, burst_color, false, 8.0)

	_last_drawn_size = size_now
	_last_drawn_phase = phase
	_last_draw_flash = _activation_flash
	_dirty = false

func _draw_spikes(rect: Rect2, color: Color) -> void:
	var count := maxi(3, int(rect.size.x / 28.0))
	var step := rect.size.x / count
	for i in range(count):
		var x := rect.position.x + i * step
		var points := PackedVector2Array([
			Vector2(x, rect.position.y),
			Vector2(x + step / 2.0, rect.position.y - 10.0),
			Vector2(x + step, rect.position.y),
		])
		draw_colored_polygon(points, color)

func _draw_zigzag(rect: Rect2) -> void:
	var points := PackedVector2Array()
	for i in range(7):
		var x := rect.position.x + rect.size.x * float(i) / 6.0
		var y := rect.position.y + (rect.size.y if i % 2 == 0 else 0.0)
		points.append(Vector2(x, y))
	draw_polyline(points, Color("#ffcf55"), 5.0)

func _draw_pinwheel(rect: Rect2) -> void:
	var center := rect.get_center()
	draw_line(center + Vector2(-rect.size.x / 2.0, -rect.size.y / 2.0), center + Vector2(rect.size.x / 2.0, rect.size.y / 2.0), Color("#ffcf55"), 5.0)
	draw_line(center + Vector2(rect.size.x / 2.0, -rect.size.y / 2.0), center + Vector2(-rect.size.x / 2.0, rect.size.y / 2.0), Color("#ffcf55"), 5.0)

func _draw_warning_marks(rect: Rect2, color: Color) -> void:
	var mark_color := Color(1.0, 0.72, 0.25, color.a)
	var center := rect.get_center()
	draw_circle(center, 15.0, Color(0.35, 0.03, 0.05, 0.35))
	draw_line(center + Vector2(0.0, -8.0), center + Vector2(0.0, 3.0), mark_color, 4.0)
	draw_circle(center + Vector2(0.0, 9.0), 2.5, mark_color)

func _draw_active_stripes(rect: Rect2) -> void:
	var stripe_color := Color(1.0, 0.55, 0.18, 0.28)
	var spacing := 24.0
	var start := rect.position.x - rect.size.y
	for x in range(int(start), int(rect.end.x), int(spacing)):
		draw_line(Vector2(x, rect.end.y), Vector2(x + rect.size.y, rect.position.y), stripe_color, 5.0)
