extends Area2D

signal collected(kind, world_pos)
signal removed(powerup)
signal recycled(powerup)

enum Kind { SHIELD, DOUBLE_SCORE, MAGNET }

## Fixed visual size in world pixels.
## The texture resolution does NOT affect the displayed size.
@export var visual_size := Vector2(50.0, 50.0)

@export var shield_texture: Texture2D = preload("res://assets/shield.png")
@export var double_score_texture: Texture2D = preload("res://assets/double.png")
@export var magnet_texture: Texture2D = preload("res://assets/magnet.png")

var kind := Kind.SHIELD
var lifetime := 12.0
var _time := 0.0
var _collected := false
var _origin := Vector2.ZERO
var _main: Node = null
var _tween: Tween
var _recycled := false
var _collider: CollisionShape2D

@onready var visual: Sprite2D = $Sprite2D


func _ready() -> void:
	# Powerups live under Main, which keeps running while paused. Without this
	# a paused powerup kept counting down and could expire behind the menu.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_main = get_tree().current_scene
	_collider = get_node_or_null("CollisionShape2D")

	collision_layer = 0
	collision_mask = 1

	body_entered.connect(_on_body_entered)

	# Lifetime is counted in _process,
	# so a pooled powerup can be re-armed.
	monitoring = false
	set_process(false)

	_apply_visual()


## Sets the sprite to a fixed visual size regardless of
## the source texture's resolution.
func _set_visual_scale() -> void:
	if not is_instance_valid(visual):
		return

	if visual.texture == null:
		return

	var texture_size := Vector2(
		visual.texture.get_width(),
		visual.texture.get_height()
	)

	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	# Preserve aspect ratio while fitting inside visual_size.
	var scale_factor = min(
		visual_size.x / texture_size.x,
		visual_size.y / texture_size.y
	)

	visual.scale = Vector2.ONE * scale_factor


## Arm a pooled powerup for a fresh spawn.
## Set position before calling this.
func activate(new_kind: int, new_lifetime := 12.0) -> void:
	setup(new_kind, new_lifetime)

	_time = 0.0
	_collected = false
	_recycled = false
	_origin = position

	_kill_tween()

	modulate = Color.WHITE

	# Reset Area2D scale.
	scale = Vector2.ONE

	# Reset visual size and rotation.
	if is_instance_valid(visual):
		_set_visual_scale()
		visual.rotation = 0.0
		visual.self_modulate = Color.WHITE

	rotation = 0.0

	visible = true
	monitoring = true

	if is_instance_valid(_collider):
		_collider.set_deferred("disabled", false)

	set_process(true)


## Hand the powerup back to the pool when a run ends
## before it is collected.
func release() -> void:
	if _recycled:
		return

	_kill_tween()

	removed.emit(self)
	_recycle()


func setup(new_kind: int, new_lifetime := 12.0) -> void:
	kind = clampi(new_kind, 0, 2)
	lifetime = new_lifetime

	_apply_visual()


func _process(delta: float) -> void:
	_time += delta

	if _time >= lifetime:
		_expire()
		return

	position = _origin + Vector2(
		0.0,
		sin(_time * 3.0) * 5.0
	)

	visual.rotation = sin(_time * 2.0) * 0.08
	# Blink shortly before disappearing, like coins do.
	var blinking := lifetime - _time < 2.0 and int(_time * 10.0) % 2 == 0
	visual.self_modulate.a = 0.35 if blinking else 1.0
	queue_redraw()


func _on_body_entered(body: Node) -> void:
	if _collected or _recycled or not body.is_in_group("player"):
		return

	_collected = true

	set_deferred("monitoring", false)

	removed.emit(self)
	collected.emit(kind, global_position)

	_kill_tween()

	# Only scale the visual.
	# The Area2D itself stays at scale 1.
	_tween = create_tween().set_parallel(true)

	_tween.tween_property(
		visual,
		"scale",
		visual.scale * 1.8,
		0.18
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_tween.tween_property(
		self,
		"modulate:a",
		0.0,
		0.2
	)

	_tween.chain().tween_callback(_recycle)


func _expire() -> void:
	if _collected or _recycled:
		return

	# Keep Main's active list free of expired references.
	removed.emit(self)

	_recycle()


func _recycle() -> void:
	if _recycled:
		return

	_recycled = true
	_collected = true

	visible = false

	set_process(false)
	set_deferred("monitoring", false)

	if is_instance_valid(_collider):
		_collider.set_deferred("disabled", true)

	recycled.emit(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = null


const HALO_COLORS := [Color(0.45, 0.9, 0.6, 0.22), Color(1.0, 0.8, 0.3, 0.22), Color(0.45, 0.78, 1.0, 0.22)]


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_circle(Vector2.ZERO, visual_size.x * (0.6 + 0.08 * pulse), HALO_COLORS[kind])
	draw_arc(Vector2.ZERO, visual_size.x * 0.62, 0.0, TAU, 28, Color(1, 1, 1, 0.25 + 0.2 * pulse), 2.0)


func _apply_visual() -> void:
	if not is_instance_valid(visual):
		return

	match kind:
		Kind.DOUBLE_SCORE:
			visual.texture = double_score_texture

		Kind.MAGNET:
			visual.texture = magnet_texture

		_:
			visual.texture = shield_texture

	# Always calculate the size from the newly assigned texture.
	_set_visual_scale()
