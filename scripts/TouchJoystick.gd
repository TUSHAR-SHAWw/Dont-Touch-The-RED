extends Control

## On-screen joystick for touch devices.

signal vector_changed(value: Vector2)

const MOUSE_ID := 99

var _pointer_id := -1
var _vector := Vector2.ZERO


func _ready() -> void:
	set_process_input(false)
	visibility_changed.connect(
		func() -> void:
			if not is_visible_in_tree() and _pointer_id != -1:
				_end()
	)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _pointer_id != -1:
		return

	if event is InputEventScreenTouch and event.pressed:
		_begin(event.index, event.position)
		accept_event()

	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_begin(MOUSE_ID, event.position)
		accept_event()


func _input(event: InputEvent) -> void:
	if _pointer_id == -1:
		return

	if event is InputEventScreenDrag and event.index == _pointer_id:
		_update_vector(make_canvas_position_local(event.position))
		get_viewport().set_input_as_handled()

	elif (
		event is InputEventScreenTouch
		and not event.pressed
		and event.index == _pointer_id
	):
		_end()

	elif event is InputEventMouseMotion and _pointer_id == MOUSE_ID:
		_update_vector(make_canvas_position_local(event.position))

	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
		and _pointer_id == MOUSE_ID
	):
		_end()


func _begin(id: int, local_position: Vector2) -> void:
	_pointer_id = id
	set_process_input(true)
	_update_vector(local_position)


func _end() -> void:
	_pointer_id = -1
	_vector = Vector2.ZERO
	set_process_input(false)
	vector_changed.emit(_vector)
	queue_redraw()


func _update_vector(local_position: Vector2) -> void:
	var max_len := maxf(1.0, minf(size.x, size.y) * 0.38)
	var offset := local_position - size * 0.5
	_vector = offset.limit_length(max_len) / max_len
	vector_changed.emit(_vector)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var base := minf(size.x, size.y)
	var outer := base * 0.43
	var travel := base * 0.23
	var knob := base * 0.17

	draw_circle(center, outer, Color(0.05, 0.05, 0.09, 0.45))
	draw_arc(center, outer, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.35), 3.0)
	draw_circle(center + _vector * travel, knob, Color(0.88, 0.14, 0.14, 0.85))
