extends Area2D

@export var radius := 18.0
@export var speed := 180.0
@export var warning_time := 1.0
@export var active_time := 3.0

var velocity := Vector2.ZERO
var active := false
var _warning := true
var _timer := 0.0
var _collider: CollisionShape2D
var _redraw_timer := 0.0

var arena_rect := Rect2(-400, -300, 800, 600)

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
	body_entered.connect(_on_body_entered)
	queue_redraw()

func setup(start_position: Vector2, direction: Vector2, ball_speed: float, warn: float, active_duration: float) -> void:
	position = start_position

	velocity = direction.normalized() * ball_speed
	speed = ball_speed

	warning_time = warn
	active_time = active_duration

	_warning = true
	active = false
	_timer = 0.0

	queue_redraw()

func _process(delta: float) -> void:
	_timer += delta

	# Warning phase
	if _warning:

		if _timer >= warning_time:
			_warning = false
			active = true
			_timer = 0.0
			# The active look is static, so a single redraw is enough.
			queue_redraw()
			return

		_redraw_timer += delta
		if _redraw_timer >= 0.05:
			_redraw_timer = 0.0
			queue_redraw()
		return

	# Active movement
	if active:

		position += velocity * delta

		_bounce_inside_arena()

		if _timer >= active_time:
			queue_free()

func _bounce_inside_arena() -> void:

	var min_x := arena_rect.position.x + radius
	var max_x := arena_rect.position.x + arena_rect.size.x - radius

	var min_y := arena_rect.position.y + radius
	var max_y := arena_rect.position.y + arena_rect.size.y - radius

	if position.x <= min_x:
		position.x = min_x
		velocity.x = abs(velocity.x)

	elif position.x >= max_x:
		position.x = max_x
		velocity.x = -abs(velocity.x)

	if position.y <= min_y:
		position.y = min_y
		velocity.y = abs(velocity.y)

	elif position.y >= max_y:
		position.y = max_y
		velocity.y = -abs(velocity.y)

func _on_body_entered(body: Node) -> void:
	if active and body.is_in_group("player") and body.has_method("die"):
		body.die()

func _draw() -> void:

	var pulse := sin(Time.get_ticks_msec() * 0.008) * 0.5 + 0.5

	# Outer warning glow
	if _warning:

		draw_circle(
			Vector2.ZERO,
			radius + 8.0 + pulse * 4.0,
			Color(1.0, 0.15, 0.05, 0.12)
		)

		draw_circle(
			Vector2.ZERO,
			radius + 3.0,
			Color(1.0, 0.25, 0.05, 0.25)
		)
	else:
		# Active glow
		draw_circle(
			Vector2.ZERO,
			radius + 9.0,
			Color(1.0, 0.05, 0.02, 0.12)
		)
		draw_circle(
			Vector2.ZERO,
			radius + 4.0,
			Color(1.0, 0.10, 0.02, 0.22)
		)

	# Main ball
	draw_circle(
		Vector2.ZERO,
		radius,
		Color("#c91f1f")
	)

	# Inner circle
	draw_circle(
		Vector2.ZERO,
		radius * 0.72,
		Color("#8f1010")
	)

	# Spikes
	for i in range(8):

		var angle := TAU * float(i) / 8.0

		var direction := Vector2(
			cos(angle),
			sin(angle)
		)

		var base := direction * radius * 0.65
		var tip := direction * (radius + 9.0)

		var side := Vector2(
			-direction.y,
			direction.x
		) * 4.0

		var points := PackedVector2Array([
			base + side,
			tip,
			base - side
		])

		draw_colored_polygon(
			points,
			Color("#ef4444")
		)

	# Highlight
	draw_circle(
		Vector2(-radius * 0.3, -radius * 0.3),
		radius * 0.18,
		Color(1, 0.75, 0.75, 0.8)
	)

	# Warning ring
	if _warning:

		draw_arc(
			Vector2.ZERO,
			radius + 5.0,
			0.0,
			TAU,
			40,
			Color(1.0, 0.2, 0.1, 0.7),
			2.0
		)
