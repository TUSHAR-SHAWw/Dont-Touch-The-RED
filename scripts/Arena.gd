extends Node2D

## The play field. White floor = safe. Black border = the arena walls.
## Kept intentionally simple for the MVP.

@export var arena_size := Vector2(800, 600)
@export var border_width := 6.0

## Returns the playable area in world space (relative to this node's origin,
## which is the arena centre).
func get_bounds() -> Rect2:
	return Rect2(-arena_size / 2.0, arena_size)

func _draw() -> void:
	var half := arena_size / 2.0
	var floor_rect := Rect2(-half, arena_size)
	draw_rect(floor_rect, Color("#e9edf4"))
	# A quiet grid makes movement and danger spacing easier to read.
	var grid_color := Color(0.25, 0.31, 0.40, 0.09)
	for x in range(int(-half.x), int(half.x) + 1, 40):
		draw_line(Vector2(x, -half.y), Vector2(x, half.y), grid_color, 1.0)
	for y in range(int(-half.y), int(half.y) + 1, 40):
		draw_line(Vector2(-half.x, y), Vector2(half.x, y), grid_color, 1.0)
	# Center marker and corner accents give the safe zone a game-board identity.
	draw_circle(Vector2.ZERO, 44.0, Color(0.35, 0.48, 0.62, 0.05))
	draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, Color(0.25, 0.38, 0.53, 0.18), 2.0)
	var accent := Color("#f59e0b")
	for corner in [Vector2(-half.x + 18.0, -half.y + 18.0), Vector2(half.x - 18.0, -half.y + 18.0), Vector2(-half.x + 18.0, half.y - 18.0), Vector2(half.x - 18.0, half.y - 18.0)]:
		draw_circle(corner, 4.0, accent)
	# Border (walls).
	draw_rect(Rect2(-half - Vector2(border_width, border_width), arena_size + Vector2(border_width, border_width) * 2.0), Color("#17202c"), false, border_width)
	draw_rect(Rect2(-half - Vector2(10.0, 10.0), arena_size + Vector2(20.0, 20.0)), Color(0.96, 0.66, 0.12, 0.18), false, 2.0)
