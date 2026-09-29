extends Area2D

signal collected(value)
signal removed(coin)
signal recycled(coin)

enum Kind { COMMON, RARE, EPIC }

## All coin textures are 1:1 square (185px). The sprite scale is derived from
## the desired visual diameter so the rendered coin stays consistent.
const TEXTURE_SIZE := 185.0

@export var common_texture: Texture2D = preload("res://assets/coin_common.svg")
@export var rare_texture: Texture2D = preload("res://assets/coin_rare.svg")
@export var epic_texture: Texture2D = preload("res://assets/coin_epic.svg")

## Visual diameter in world pixels. Matches the collision radius.
@export var visual_radius := 16.0

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
	# Sprite scale = visual diameter / texture size (1:1 assets).
	visual.scale = Vector2.ONE * (visual_radius * 2.0 / TEXTURE_SIZE)
	# Smooth filtering keeps 1:1 pixel-art from looking blocky.
	visual.texture_filter = 1  # CanvasItem.LINEAR
	_main = get_tree().current_scene
	_magnet_supported = _main != null and _main.has_method("is_magnet_active")
	_collider = get_node_or_null("CollisionShape2D")
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	# Lifetime is counted in _process, so a pooled coin can be re-armed.
	monitoring = false
	set_process(false)
	_apply_visual()

## Arm a pooled coin for a fresh spawn. Set `position` before calling this.
func activate(new_kind: int, common_lifetime := 9.0, rare_lifetime := 12.0, epic_lifetime := 15.0) -> void:
	setup(new_kind, common_lifetime, rare_lifetime, epic_lifetime)
	_time = 0.0
	_collected = false
	_recycled = false
	_origin = position
	_kill_tween()
	modulate = Color.WHITE
	# Reset the Area2D scale (used for the fade-out tween) and the
	# visual sprite scale (set from the 1:1 texture size in _ready).
	scale = Vector2.ONE
	if is_instance_valid(visual):
		visual.scale = Vector2.ONE * (visual_radius * 2.0 / TEXTURE_SIZE)
		visual.rotation = 0.0
	rotation = 0.0
	visible = true
	monitoring = true
	if is_instance_valid(_collider):
		_collider.set_deferred("disabled", false)
	set_process(true)

## Hand the coin back to the pool when a run ends before it is collected.
func release() -> void:
	if _recycled:
		return
	_kill_tween()
	removed.emit(self)
	_recycle()

func setup(new_kind: int, common_lifetime := 9.0, rare_lifetime := 12.0, epic_lifetime := 15.0) -> void:
	kind = clampi(new_kind, 0, 2)
	match kind:
		Kind.RARE:
			value = 3
			lifetime = rare_lifetime
		Kind.EPIC:
			value = 8
			lifetime = epic_lifetime
		_:
			value = 1
			lifetime = common_lifetime
	_apply_visual()

func _process(delta: float) -> void:
	_time += delta
	if _time >= lifetime:
		_expire()
		return
	if _magnet_pull_active():
		global_position = global_position.move_toward(_player.global_position, 240.0 * delta)
	else:
		position.y = _origin.y + sin(_time * 3.0) * 4.0
	visual.rotation = sin(_time * 2.5) * 0.12

func _magnet_pull_active() -> bool:
	if not _magnet_supported or _main == null:
		return false
	if not _main.is_magnet_active():
		return false
	if not is_instance_valid(_player):
		_player = _main.get_node_or_null("Player")
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
	collected.emit(value)
	_kill_tween()
	# Scale the visual sprite (not the Area2D parent) so the effect
	# composes cleanly with the per-texture scale set in _ready().
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(visual, "scale", visual.scale * 1.65, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
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

func _apply_visual() -> void:
	if is_instance_valid(visual):
		match kind:
			Kind.RARE:
				visual.texture = rare_texture
			Kind.EPIC:
				visual.texture = epic_texture
			_:
				visual.texture = common_texture
		# Re-derive the scale from the newly assigned texture's actual size.
		var tex_size := TEXTURE_SIZE
		if visual.texture:
			tex_size = float(max(visual.texture.get_width(), visual.texture.get_height()))
		visual.scale = Vector2.ONE * (visual_radius * 2.0 / tex_size)
