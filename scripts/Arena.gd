extends Node2D

## The play field. White floor = safe. Black border = the arena walls.
## Kept intentionally simple for the MVP.

@export var arena_size := Vector2(800, 600):
	set(value):
		arena_size = Vector2(maxf(value.x, 64.0), maxf(value.y, 64.0))
		queue_redraw()

@export var border_width := 6.0:
	set(value):
		border_width = maxf(value, 1.0)
		queue_redraw()

const FLOOR_COLOR := Color("#e9edf4")
const WALL_COLOR := Color("#17202c")
const ACCENT_COLOR := Color("#f59e0b")
const GRID_COLOR := Color(0.25, 0.31, 0.40, 0.09)
const GRID_STEP := 40.0
const HALO_GAP := 4.0
const HALO_WIDTH := 2.0


## Returns the playable area in world space (relative to this node's origin,
## which is the arena centre).
func get_bounds() -> Rect2:
	return Rect2(-arena_size / 2.0, arena_size)


func _draw() -> void:
	var half := arena_size / 2.0
	var floor_rect := Rect2(-half, arena_size)

	# Floor.
	draw_rect(floor_rect, FLOOR_COLOR)

	# A quiet grid makes movement and danger spacing easier to read.
	# Lines start at the left/top edge, and the right/bottom edges always get
	# a line too, so the grid never ends in a partial cell with no border line.
	var x := -half.x
	while x < half.x:
		draw_line(Vector2(x, -half.y), Vector2(x, half.y), GRID_COLOR, 1.0)
		x += GRID_STEP
	draw_line(Vector2(half.x, -half.y), Vector2(half.x, half.y), GRID_COLOR, 1.0)

	var y := -half.y
	while y < half.y:
		draw_line(Vector2(-half.x, y), Vector2(half.x, y), GRID_COLOR, 1.0)
		y += GRID_STEP
	draw_line(Vector2(-half.x, half.y), Vector2(half.x, half.y), GRID_COLOR, 1.0)

	# Center marker and corner accents give the safe zone a game-board identity.
	draw_circle(Vector2.ZERO, 44.0, Color(0.35, 0.48, 0.62, 0.05))
	draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, Color(0.25, 0.38, 0.53, 0.18), 2.0)

	for corner in [
		Vector2(-half.x + 18.0, -half.y + 18.0),
		Vector2(half.x - 18.0, -half.y + 18.0),
		Vector2(-half.x + 18.0, half.y - 18.0),
		Vector2(half.x - 18.0, half.y - 18.0),
	]:
		draw_circle(corner, 4.0, ACCENT_COLOR)

	# Walls are filled strips completely outside the playable floor. This keeps
	# the visual wall aligned with get_bounds() instead of eating into the arena.
	_draw_frame(floor_rect, border_width, WALL_COLOR)

	# Thin amber halo with a real gap from the wall.
	_draw_frame(
		floor_rect.grow(border_width + HALO_GAP),
		HALO_WIDTH,
		Color(0.96, 0.66, 0.12, 0.18)
	)


## Draws a frame of the given thickness as four filled strips lying
## completely outside rect. The strips overlap at the corners so the
## corners are solid.
func _draw_frame(rect: Rect2, thickness: float, color: Color) -> void:
	var t := maxf(thickness, 0.1)

	# Top and bottom include the corners.
	draw_rect(
		Rect2(rect.position.x - t, rect.position.y - t, rect.size.x + 2.0 * t, t),
		color
	)
	draw_rect(
		Rect2(rect.position.x - t, rect.end.y, rect.size.x + 2.0 * t, t),
		color
	)

	# Left and right fill the gap between the horizontal strips.
	draw_rect(
		Rect2(rect.position.x - t, rect.position.y, t, rect.size.y),
		color
	)
	draw_rect(
		Rect2(rect.end.x, rect.position.y, t, rect.size.y),
		color
	)
