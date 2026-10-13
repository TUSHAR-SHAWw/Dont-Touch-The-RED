extends Control

## Circular countdown used by the revive prompt.

@export var progress := 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

const COLOR_FULL := Color("#3ddcff")
const COLOR_LOW := Color("#ff4d5e")


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 8.0
	draw_circle(center, radius, Color(0.03, 0.05, 0.12, 0.65))
	draw_arc(center, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 8.0)
	if progress > 0.0:
		var col := COLOR_LOW.lerp(COLOR_FULL, smoothstep(0.1, 0.5, progress))
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, col, 8.0, true)
