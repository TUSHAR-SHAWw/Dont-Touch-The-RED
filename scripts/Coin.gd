extends Area2D

## `world_pos` lets the game spawn effects exactly where the coin was.
signal collected(value, world_pos)
signal removed(coin)
signal recycled(coin)

enum Kind { COMMON, RARE, EPIC }

## Coin value per Kind (index = Kind). AudioManager's rare/epic thresholds
## (3 and 8) are based on these numbers.
const VALUES := [1, 3, 8]
## Seconds before expiry during which the coin blinks.
const BLINK_TIME := 2.0
const BLINK_RATE := 10.0
const SPAWN_POP_TIME := 0.18
const MAGNET_SPEED := 240.0
const BOB_HEIGHT := 4.0

## Fixed visual size in world pixels.
## Texture resolution does NOT affect the displayed size.
@export var visual_size := Vector2(50.0, 50.0)

@export var common_texture: Texture2D = preload("res://assets/common.png")
@export var rare_texture: Texture2D = preload("res://assets/rare.png")
@export var epic_texture: Texture2D = preload("res://assets/epic.png")

var value := 1
var kind := Kind.COMMON
var lifetime := 10.0
var _time := 0.0
var _collected := false
var _origin := Vector2.ZERO
var _main: Node = null
var _player: Node2D = null
var _magnet_supported := false
var _tween: Tween
var _recycled := false
var _collider: CollisionShape2D

@onready var visual: Sprite2D = $Sprite2D


func _ready() -> void:
	# Coins live under Game, which keeps running while paused. Without this a
	# paused coin keeps counting down and can expire behind the pause menu.
	process_mode = Node.PROCESS_MODE_PAUSABLE

	# Smooth filtering (the textures are scaled down a lot, so use mipmaps).
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Coins are children of Game, so ask the parent rather than the root scene.
	var parent := get_parent()
	if parent and parent.has_method("is_magnet_active"):
		_main = parent
	else:
		_main = get_tree().current_scene
	_magnet_supported = _main != null and _main.has_method("is_magnet_active")

	_collider = get_node_or_null("CollisionShape2D")

	collision_layer = 0
	collision_mask = 1

	body_entered.connect(_on_body_entered)

	# Lifetime is counted in _process,
	# so a pooled coin can be re-armed.
	monitoring = false
	set_process(false)

	_apply_visual()


## Scale that fits the current texture inside visual_size (keeps aspect ratio).
func _fit_scale() -> Vector2:
	if not is_instance_valid(visual) or visual.texture == null:
		return Vector2.ONE

	var texture_size := Vector2(visual.texture.get_width(), visual.texture.get_height())
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ONE

	return Vector2.ONE * minf(visual_size.x / texture_size.x, visual_size.y / texture_size.y)


## Sets the coin sprite to a fixed visual size regardless
## of the source texture's resolution.
func _set_visual_scale() -> void:
	if is_instance_valid(visual) and visual.texture != null:
		visual.scale = _fit_scale()


## Arm a pooled coin for a fresh spawn.
## Set position before calling this.
func activate(
	new_kind: int,
	common_lifetime := 9.0,
	rare_lifetime := 12.0,
	epic_lifetime := 15.0
) -> void:

	setup(new_kind, common_lifetime, rare_lifetime, epic_lifetime)

	_time = 0.0
	_collected = false
	_recycled = false
	_origin = position

	_kill_tween()

	modulate = Color.WHITE
	# Reset Area2D scale and rotation.
	scale = Vector2.ONE
	rotation = 0.0

	if is_instance_valid(visual):
		visual.rotation = 0.0
		visual.self_modulate = Color.WHITE
		# Pop in from a small size instead of appearing instantly.
		var target := _fit_scale()
		visual.scale = target * 0.2
		_tween = create_tween()
		_tween.tween_property(visual, "scale", target, SPAWN_POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	visible = true
	monitoring = true

	if is_instance_valid(_collider):
		_collider.set_deferred("disabled", false)

	set_process(true)


## Hand the coin back to the pool when a run ends
## before it is collected.
func release() -> void:
	if _recycled:
		return

	_kill_tween()

	removed.emit(self)
	_recycle()


func setup(
	new_kind: int,
	common_lifetime := 9.0,
	rare_lifetime := 12.0,
	epic_lifetime := 15.0
) -> void:

	kind = clampi(new_kind, 0, 2)
	value = VALUES[kind]

	match kind:
		Kind.RARE:
			lifetime = rare_lifetime
		Kind.EPIC:
			lifetime = epic_lifetime
		_:
			lifetime = common_lifetime

	_apply_visual()


func _process(delta: float) -> void:
	_time += delta

	if _time >= lifetime:
		_expire()
		return

	var bob := sin(_time * 3.0) * BOB_HEIGHT
	if _magnet_pull_active():
		global_position = global_position.move_toward(_player.global_position, MAGNET_SPEED * delta)
		# Keep the bobbing baseline under the coin, so it doesn't snap back
		# to where it spawned when the magnet runs out.
		_origin = Vector2(position.x, position.y - bob)
	else:
		position.y = _origin.y + bob

	visual.rotation = sin(_time * 2.5) * 0.12

	# Blink shortly before disappearing (self_modulate, so it never fights
	# the fade-out used on collection).
	var blinking := lifetime - _time < BLINK_TIME and int(_time * BLINK_RATE) % 2 == 0
	visual.self_modulate.a = 0.35 if blinking else 1.0


func _magnet_pull_active() -> bool:
	if not _magnet_supported or _main == null:
		return false

	if not _main.is_magnet_active():
		return false

	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D

	return is_instance_valid(_player)


func _expire() -> void:
	if _collected or _recycled:
		return

	removed.emit(self)
	_recycle()


func _on_body_entered(body: Node) -> void:
	if _collected or _recycled or not body.is_in_group("player"):
		return

	_collected = true

	set_deferred("monitoring", false)

	removed.emit(self)
	collected.emit(value, global_position)

	_kill_tween()
	visual.self_modulate.a = 1.0

	# Scale only the visual for the collection effect.
	_tween = create_tween().set_parallel(true)

	_tween.tween_property(
		visual,
		"scale",
		_fit_scale() * 1.65,
		0.16
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_tween.tween_property(
		self,
		"modulate:a",
		0.0,
		0.18
	)

	_tween.chain().tween_callback(_recycle)


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


const HALO_COLORS := [Color(1.0, 0.85, 0.3, 0.16), Color(0.45, 0.8, 1.0, 0.2), Color(0.85, 0.5, 1.0, 0.24)]


## Soft glow behind the sprite so pickups read clearly on the light floor.
func _draw() -> void:
	draw_circle(Vector2.ZERO, visual_size.x * 0.62, HALO_COLORS[kind])


func _apply_visual() -> void:
	if not is_instance_valid(visual):
		return
	queue_redraw()

	match kind:
		Kind.RARE:
			visual.texture = rare_texture

		Kind.EPIC:
			visual.texture = epic_texture

		_:
			visual.texture = common_texture

	# Always calculate scale from the actual texture.
	_set_visual_scale()
