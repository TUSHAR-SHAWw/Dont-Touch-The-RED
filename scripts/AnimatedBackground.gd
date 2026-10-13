extends Control

## Shared animated menu background (orbs, grid, radar, particles).

const ORB_POS := [Vector2(0.18, 0.25), Vector2(0.82, 0.70), Vector2(0.55, 0.42), Vector2(0.30, 0.82)]
const ORB_COL := [Color(0.30, 0.18, 0.75), Color(0.08, 0.50, 0.75), Color(0.70, 0.10, 0.40), Color(0.10, 0.60, 0.50)]
const ORB_RAD := [330.0, 390.0, 280.0, 240.0]

var time := 0.0
var lite := false
var particles: Array[Dictionary] = []
var streaks: Array[Dictionary] = []
var kicks: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for i in range(70):
		particles.append({
			"pos": Vector2(randf(), randf()),
			"speed": randf_range(0.02, 0.07),
			"radius": randf_range(1.0, 3.2),
			"phase": randf_range(0.0, TAU),
			"alpha": randf_range(0.2, 0.7),
			"layer": 0.5 + float(randi() % 3) * 0.55,
			"red": randf() < 0.12,
		})

	for i in range(5):
		streaks.append({
			"offset": randf_range(0.0, 10.0),
			"period": randf_range(4.0, 8.0),
			"y": randf_range(0.02, 0.7),
			"length": randf_range(140.0, 280.0),
		})

	queue_redraw()


## Reduced effects: cheaper drawing, but it still moves.
func set_lite(enabled: bool) -> void:
	lite = enabled
	queue_redraw()


## Expanding ring burst, fired on every screen change.
func kick() -> void:
	if lite:
		return
	kicks.append(time)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	time += delta
	if not kicks.is_empty():
		kicks = kicks.filter(func(k: float) -> bool: return time - k < 1.0)
	queue_redraw()


func _draw() -> void:
	var area := size
	var arena_center := area * 0.5

	# Deep background
	draw_rect(Rect2(Vector2.ZERO, area), Color("#080b20"))

	# Drifting glow orbs (3 stacked circles = soft glow)
	for i in range(ORB_POS.size()):
		if lite and i > 1:
			break
		var ph := float(i) * 1.7
		var orb_pos := Vector2(
			area.x * (ORB_POS[i].x + 0.05 * sin(time * 0.25 + ph)),
			area.y * (ORB_POS[i].y + 0.05 * cos(time * 0.21 + ph))
		)
		var base: Color = ORB_COL[i]
		var rad: float = ORB_RAD[i] * (1.0 + 0.06 * sin(time * 0.6 + ph))
		for layer in range(3):
			draw_circle(orb_pos, rad * (1.0 - layer * 0.3), Color(base.r, base.g, base.b, 0.085))

	if not lite:
		# Scrolling grid
		var grid_step := 90.0
		var gx := fmod(time * 12.0, grid_step)
		var gy := fmod(time * 8.0, grid_step)
		var grid_col := Color(0.35, 0.6, 0.95, 0.045)
		for i in range(int(area.x / grid_step) + 2):
			var x := float(i) * grid_step - gx
			draw_line(Vector2(x, 0.0), Vector2(x, area.y), grid_col, 1.0)
		for i in range(int(area.y / grid_step) + 2):
			var y := float(i) * grid_step - gy
			draw_line(Vector2(0.0, y), Vector2(area.x, y), grid_col, 1.0)

	# Moving diagonal energy lines
	var line_offset := fmod(time * 45.0, 180.0)
	var span := area.y * 0.55
	var line_count := ceili((area.x + span) / 180.0) + 2
	for i in range(line_count):
		var line_x := -span + float(i) * 180.0 + line_offset - 180.0
		draw_line(
			Vector2(line_x, area.y),
			Vector2(line_x + span, 0.0),
			Color(0.25, 0.55, 0.85, 0.08),
			2.0
		)

	# Horizontal scan line
	var scan_y := fmod(time * 55.0, area.y + 100.0) - 50.0
	draw_line(Vector2(0.0, scan_y), Vector2(area.x, scan_y), Color(0.35, 0.75, 1.0, 0.07), 2.0)
	draw_line(Vector2(0.0, scan_y + 5.0), Vector2(area.x, scan_y + 5.0), Color(0.35, 0.75, 1.0, 0.025), 8.0)

	# Parallax particles rising and twinkling
	var particle_count := 25 if lite else particles.size()
	for i in range(particle_count):
		var p := particles[i]
		var base_pos: Vector2 = p["pos"]
		var layer: float = p["layer"]
		var phase: float = p["phase"]

		var px: float = base_pos.x * area.x + sin(time * 0.6 + phase) * 22.0 * layer
		var py := fposmod(base_pos.y * area.y - time * float(p["speed"]) * area.y * layer, area.y)
		var twinkle := 0.6 + 0.4 * sin(time * 2.2 + phase)
		var a: float = float(p["alpha"]) * twinkle

		var col := Color(0.55, 0.82, 1.0, a)
		if p["red"]:
			col = Color(1.0, 0.32, 0.38, a)
		draw_circle(Vector2(px, py), float(p["radius"]) * layer, col)

	# Meteor streaks
	if not lite:
		for s in streaks:
			var period: float = s["period"]
			var phase_t := fmod(time + float(s["offset"]), period) / period
			if phase_t > 0.22:
				continue
			var prog := phase_t / 0.22
			var head := Vector2(
				lerpf(-0.1, 1.1, prog) * area.x,
				(float(s["y"]) + prog * 0.22) * area.y
			)
			var dir := Vector2(1.0, 0.22).normalized()
			var length: float = s["length"]
			var pts := PackedVector2Array([head - dir * length, head - dir * length * 0.4, head])
			var cols := PackedColorArray([
				Color(0.6, 0.85, 1.0, 0.0),
				Color(0.6, 0.85, 1.0, 0.35),
				Color(1.0, 1.0, 1.0, 0.9),
			])
			draw_polyline_colors(pts, cols, 2.5)

	# Rotating rings
	var spin := time * 0.12
	for r in [170.0, 230.0, 300.0]:
		draw_arc(arena_center, r, spin, spin + TAU * 0.72, 80, Color(0.20, 0.65, 0.95, 0.08), 2.0)

	# Radar sweep with fading trail
	if not lite:
		var sweep := time * 0.9
		for k in range(14):
			var a1 := sweep - float(k) * 0.045
			draw_arc(
				arena_center,
				255.0,
				a1 - 0.045,
				a1,
				6,
				Color(0.95, 0.25, 0.35, 0.18 * (1.0 - float(k) / 14.0)),
				4.0
			)
		draw_line(
			arena_center,
			arena_center + Vector2.from_angle(sweep) * 255.0,
			Color(0.95, 0.3, 0.4, 0.22),
			2.0
		)

	# Central pulse
	var center_pulse := (sin(time * 1.5) + 1.0) * 0.5
	draw_circle(arena_center, 80.0 + center_pulse * 25.0, Color(0.10, 0.45, 0.70, 0.03))
	draw_arc(arena_center, 100.0 + center_pulse * 20.0, 0.0, TAU, 64, Color(0.25, 0.75, 1.0, 0.07), 2.0)

	# Ring bursts fired by screen changes
	var burst_radius := maxf(area.x, area.y) * 0.75
	for k in kicks:
		var t := (time - float(k)) / 1.0
		draw_arc(
			arena_center,
			t * burst_radius,
			0.0,
			TAU,
			96,
			Color(0.35, 0.8, 1.0, (1.0 - t) * 0.4),
			2.0 + (1.0 - t) * 6.0
		)

	# Pulsing red danger vignette
	if not lite:
		var vignette := 0.04 + 0.05 * (sin(time * 1.8) + 1.0) * 0.5
		for k in range(4):
			var inset := 5.0 + float(k) * 10.0
			draw_rect(
				Rect2(Vector2(inset, inset), area - Vector2(inset, inset) * 2.0),
				Color(0.95, 0.1, 0.2, vignette * (1.0 - float(k) * 0.22)),
				false,
				10.0
			)
