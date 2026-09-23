
extends Node

## ============================================================
## PerformanceMonitor.gd
## Godot 4.x
##
## Full performance monitor with automatic panel height.
## ============================================================

@export var enabled := true
@export var panel_width := 300
@export var margin := 12
@export var update_interval := 1.0

var panel: Panel
var label: RichTextLabel

var elapsed := 0.0

var min_fps := INF
var max_fps := 0.0

var fps_total := 0.0
var fps_samples := 0

var _has_static_memory_usage := false
var _version_text := ""


func _ready() -> void:
	_create_panel()


func _process(delta: float) -> void:
	elapsed += delta

	var fps := Engine.get_frames_per_second()

	if fps > 0:
		min_fps = min(min_fps, float(fps))
		max_fps = max(max_fps, float(fps))

		fps_total += float(fps)
		fps_samples += 1

	if elapsed >= update_interval:
		elapsed = 0.0
		_update_display()


func _create_panel() -> void:
	# ========================================================
	# CanvasLayer
	# ========================================================

	var canvas := CanvasLayer.new()
	canvas.name = "PerformanceMonitorLayer"
	canvas.layer = 100

	add_child(canvas)

	# ========================================================
	# Panel
	# ========================================================

	panel = Panel.new()
	panel.name = "PerformancePanel"

	panel.position = Vector2(margin, margin)

	canvas.add_child(panel)

	# ========================================================
	# Background
	# ========================================================

	var style := StyleBoxFlat.new()

	style.bg_color = Color(0.015, 0.015, 0.02, 0.94)
	style.border_color = Color(0.35, 0.35, 0.40, 1.0)

	style.set_border_width(SIDE_LEFT, 1)
	style.set_border_width(SIDE_TOP, 1)
	style.set_border_width(SIDE_RIGHT, 1)
	style.set_border_width(SIDE_BOTTOM, 1)

	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10

	panel.add_theme_stylebox_override(
		"panel",
		style
	)

	# ========================================================
	# RichTextLabel
	# ========================================================

	label = RichTextLabel.new()
	label.name = "PerformanceLabel"

	label.position = Vector2(12, 10)

	label.size = Vector2(
		panel_width - 24,
		500
	)

	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false

	label.add_theme_font_size_override(
		"normal_font_size",
		14
	)

	panel.add_child(label)

	_update_display()


func _update_display() -> void:
	var fps := Engine.get_frames_per_second()

	# ========================================================
	# Frame time
	# ========================================================

	var frame_ms := 0.0

	if fps > 0:
		frame_ms = 1000.0 / float(fps)

	# ========================================================
	# Average FPS
	# ========================================================

	var average_fps := 0.0

	if fps_samples > 0:
		average_fps = fps_total / float(fps_samples)

	# ========================================================
	# Memory
	# ========================================================

	var memory_mb := 0.0

	if OS.has_method("get_static_memory_usage"):
		memory_mb = (
			float(OS.get_static_memory_usage())
			/ 1024.0
			/ 1024.0
		)

	# ========================================================
	# Nodes
	# ========================================================

	var node_count := get_tree().get_node_count()

	# ========================================================
	# Rendering information
	# ========================================================

	var objects := 0
	var draw_calls := 0
	var primitives := 0

	objects = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
	)

	draw_calls = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)

	primitives = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	)

	# ========================================================
	# CPU
	# ========================================================

	var process_ms := Performance.get_monitor(
		Performance.TIME_PROCESS
	) * 1000.0

	var physics_ms := Performance.get_monitor(
		Performance.TIME_PHYSICS_PROCESS
	) * 1000.0

	# ========================================================
	# Godot version
	# ========================================================

	var version_info := Engine.get_version_info()

	var version_text := "%d.%d.%d" % [
		version_info.major,
		version_info.minor,
		version_info.patch
	]

	# ========================================================
	# Colors
	# ========================================================

	var fps_color := _get_fps_color(fps)
	var average_color := _get_fps_color(average_fps)
	var frame_color := _get_frame_color(frame_ms)
	var cpu_color := _get_cpu_color(process_ms)

	# ========================================================
	# Status
	# ========================================================

	var status := "GOOD"
	var status_color := Color(0.3, 1.0, 0.4)

	if average_fps < 55.0:
		status = "WARNING"
		status_color = Color(1.0, 0.85, 0.25)

	if average_fps < 40.0:
		status = "POOR"
		status_color = Color(1.0, 0.3, 0.3)

	# ========================================================
	# Text
	# ========================================================

	var lines: Array[String] = []

	lines.append(
		"[font_size=18][b]PERFORMANCE MONITOR[/b][/font_size]"
	)

	lines.append("────────────────────────────")

	lines.append(
		"[color=#%s][b]STATUS: %s[/b][/color]"
		% [
			status_color.to_html(false),
			status
		]
	)

	lines.append("")

	lines.append("[b]FPS[/b]")

	lines.append(
		"Current:     [color=#%s]%d FPS[/color]"
		% [
			fps_color.to_html(false),
			fps
		]
	)

	lines.append(
		"Average:     [color=#%s]%.1f FPS[/color]"
		% [
			average_color.to_html(false),
			average_fps
		]
	)

	lines.append("Min:         %d FPS" % int(min_fps))
	lines.append("Max:         %d FPS" % int(max_fps))

	lines.append("")

	lines.append("[b]FRAME TIME[/b]")

	lines.append(
		"Frame:       [color=#%s]%.2f ms[/color]"
		% [
			frame_color.to_html(false),
			frame_ms
		]
	)

	lines.append("")

	lines.append("[b]CPU[/b]")

	lines.append(
		"Process:     [color=#%s]%.2f ms[/color]"
		% [
			cpu_color.to_html(false),
			process_ms
		]
	)

	lines.append("Physics:     %.2f ms" % physics_ms)

	lines.append("")

	lines.append("[b]RENDERING[/b]")
	lines.append("Objects:     %d" % objects)
	lines.append("Draw Calls:  %d" % draw_calls)
	lines.append("Primitives:  %d" % primitives)

	lines.append("")

	lines.append("[b]GAME[/b]")
	lines.append("Nodes:       %d" % node_count)
	lines.append("Memory:      %.1f MB" % memory_mb)
	lines.append("Godot:       %s" % version_text)

	label.text = "\n".join(lines)

	# ========================================================
	# Automatically resize the panel
	# ========================================================

	await get_tree().process_frame

	panel.size = Vector2(
		panel_width,
		label.get_combined_minimum_size().y + 22
	)


func _get_fps_color(fps: float) -> Color:
	if fps >= 55.0:
		return Color(0.3, 1.0, 0.4)

	if fps >= 40.0:
		return Color(1.0, 0.85, 0.25)

	return Color(1.0, 0.3, 0.3)


func _get_frame_color(frame_ms: float) -> Color:
	if frame_ms <= 16.7:
		return Color(0.3, 1.0, 0.4)

	if frame_ms <= 25.0:
		return Color(1.0, 0.85, 0.25)

	return Color(1.0, 0.3, 0.3)


func _get_cpu_color(process_ms: float) -> Color:
	if process_ms <= 5.0:
		return Color(0.3, 1.0, 0.4)

	if process_ms <= 10.0:
		return Color(1.0, 0.85, 0.25)

	return Color(1.0, 0.3, 0.3)
