extends Area2D

## Bouncing spike ball hazard. Warning (harmless) -> active (lethal) -> gone.

@export var radius := 18.0
@export var ball_speed := 180.0
@export var warning_time := 1.0
@export var active_time := 3.0

var velocity := Vector2.ZERO
var active := false
var arena_rect := Rect2(-400, -300, 800, 600)

var _warning := true
var _timer := 0.0
var _collider: CollisionShape2D
var _redraw_timer := 0.0
var _spin := 0.0
var _dismissed := false


func _ready() -> void:
	_collider = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius + 9.0
	_collider.shape = shape
	add_child(_collider)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	queue_redraw()


func setup(start_position: Vector2, direction: Vector2, speed: float, warn: float, active_duration: float) -> void:
	position = start_position
	velocity = direction.normalized() * speed
	warning_time = warn
	active_time = active_duration
	_warning = true
	active = false
	_timer = 0.0
	queue_redraw()


func is_alive() -> bool:
	return not _dismissed


## Bounds used by the game so pickups never spawn in the ball's path.
func get_danger_rect() -> Rect2:
	var reach := radius + 70.0
	return Rect2(position - Vector2(reach, reach), Vector2(reach, reach) * 2.0)


## Ends the hazard early with a quick fade (used after a revive).
func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	active = false
	set_deferred("monitoring", false)
	if _collider:
		_collider.set_deferred("disabled", true)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	if _dismissed:
		return
	_timer += delta

	if _warning:
		if _timer >= warning_time:
			_warning = false
			active = true
			_timer = 0.0
			queue_redraw()
			return
		_redraw_timer += delta
		if _redraw_timer >= 0.05:
			_redraw_timer = 0.0
			queue_redraw()
		return

	if active:
		position += velocity * delta
		_bounce_inside_arena()
		_spin += delta * 3.0
		queue_redraw()

		# Polling (not body_entered) also catches a player who was already
		# standing inside when the ball turned lethal.
		for body in get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("die"):
				body.die()

		if _timer >= active_time:
			dismiss()


func _bounce_inside_arena() -> void:
	var min_x := arena_rect.position.x + radius
	var max_x := arena_rect.position.x + arena_rect.size.x - radius
	var min_y := arena_rect.position.y + radius
	var max_y := arena_rect.position.y + arena_rect.size.y - radius

	if position.x <= min_x:
		position.x = min_x
		velocity.x = absf(velocity.x)
	elif position.x >= max_x:
		position.x = max_x
		velocity.x = -absf(velocity.x)

	if position.y <= min_y:
		position.y = min_y
		velocity.y = absf(velocity.y)
	elif position.y >= max_y:
		position.y = max_y
		velocity.y = -absf(velocity.y)


func _draw() -> void:
	var pulse := sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5

	if _warning:
		draw_circle(Vector2.ZERO, radius + 8.0 + pulse * 4.0, Color(1.0, 0.15, 0.05, 0.12))
		draw_circle(Vector2.ZERO, radius + 3.0, Color(1.0, 0.25, 0.05, 0.25))
	else:
		draw_circle(Vector2.ZERO, radius + 9.0, Color(1.0, 0.05, 0.02, 0.12))
		draw_circle(Vector2.ZERO, radius + 4.0, Color(1.0, 0.10, 0.02, 0.22))

	draw_circle(Vector2.ZERO, radius, Color("#c91f1f"))
	draw_circle(Vector2.ZERO, radius * 0.72, Color("#8f1010"))

	# Spikes (they rotate while the ball is lethal).
	for i in range(8):
		var angle := TAU * float(i) / 8.0 + _spin
		var direction := Vector2(cos(angle), sin(angle))
		var base := direction * radius * 0.65
		var tip := direction * (radius + 9.0)
		var side := Vector2(-direction.y, direction.x) * 4.0
		draw_colored_polygon(PackedVector2Array([base + side, tip, base - side]), Color("#ef4444"))

	draw_circle(Vector2(-radius * 0.3, -radius * 0.3), radius * 0.18, Color(1, 0.75, 0.75, 0.8))

	if _warning:
		draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 40, Color(1.0, 0.2, 0.1, 0.7), 2.0)
