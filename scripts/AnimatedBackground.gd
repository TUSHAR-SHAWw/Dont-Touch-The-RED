extends Control

## Shared animated menu background (orbs, grid, radar, particles, meteors).
##
## PERFORMANCE: everything is drawn by ONE fragment shader on ONE rectangle.
## The old version issued ~250 draw_* calls from GDScript every frame (large
## overlapping translucent circles, 80-96 segment arcs, 70 dictionary-driven
## particles). That is CPU heavy on phones and burns fill-rate. Here the script
## only advances a clock, so the per-frame cost is a single uniform update.
##
## The shader can run on a smaller render target (render_scale) and is scaled up,
## which is invisible for soft glows and makes it 4x cheaper at 0.5 on phones.
##
## Public API is unchanged: set_lite(bool), kick(), `visible`.

## 0 = automatic (0.5 on mobile and web, 1.0 on desktop). 1.0 = native
## resolution. Below 1.0 the background renders smaller and is scaled up.
@export_range(0.0, 1.0, 0.05) var render_scale := 0.0

## Background redraws per second. 0 = automatic (30 on mobile and web, every
## frame on desktop). The motion is slow, so 30 looks the same on a phone.
@export_range(0.0, 60.0, 1.0) var update_fps := 0.0

const SHADER_CODE := """
shader_type canvas_item;
render_mode blend_disabled;

uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float t = 0.0;
uniform float kick_t0 = -100.0;
uniform float lite = 0.0;
uniform vec4 dim = vec4(0.0);

const float TAU_C = 6.28318530718;
const float PI_C = 3.14159265359;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// ~1px anti-aliased line: 1 on the line, 0 outside.
float line_mask(float dist, float half_w) {
	return 1.0 - smoothstep(half_w - 0.5, half_w + 0.75, dist);
}

vec3 glow(vec3 col, vec2 p, vec2 pos, float rad, vec3 oc, float ph) {
	vec2 c = rect_size * (pos + 0.05 * vec2(sin(t * 0.25 + ph), cos(t * 0.21 + ph)));
	float r = rad * (1.0 + 0.06 * sin(t * 0.6 + ph));
	float g = clamp(1.0 - length(p - c) / r, 0.0, 1.0);
	return mix(col, oc, g * g * (3.0 - 2.0 * g) * 0.30 + g * 0.06);
}

// One layer of twinkling rising particles. One particle per grid cell, so the
// cost per pixel is constant no matter how many particles are on screen.
vec4 particles(vec2 p, float layer_id, float cell, float speed, float scale) {
	vec2 q = vec2(p.x, p.y + t * speed);
	vec2 g = q / cell;
	vec2 id = floor(g);
	vec2 f = fract(g);

	vec2 h = hash22(id + layer_id * 31.7);
	vec2 h2 = hash22(id + layer_id * 57.3 + 11.0);
	if (h2.x < 0.45) {
		return vec4(0.0);
	}

	float phase = h2.y * TAU_C;
	vec2 pos = 0.3 + 0.4 * h;
	pos.x += sin(t * 0.6 + phase) * 16.0 * scale / cell;

	float d = length((f - pos) * cell);
	float rad = (1.0 + 2.2 * fract(h2.x * 7.31)) * scale;
	float m = 1.0 - smoothstep(rad - 1.0, rad, d);

	float twinkle = 0.6 + 0.4 * sin(t * 2.2 + phase);
	float a = (0.2 + 0.5 * fract(h.x * 5.17)) * twinkle * m;

	vec3 col = vec3(0.55, 0.82, 1.0);
	if (fract(h.y * 9.13) > 0.88) {
		col = vec3(1.0, 0.32, 0.38);
	}
	return vec4(col, a);
}

float streak(vec2 p, float period, float off, float y0, float len) {
	float prog = fract((t + off) / period) / 0.22;
	if (prog >= 1.0) {
		return 0.0;
	}
	vec2 head = vec2(mix(-0.1, 1.1, prog) * rect_size.x, (y0 + prog * 0.22) * rect_size.y);
	vec2 dir = normalize(vec2(1.0, 0.22));
	vec2 v = p - head;
	float along = dot(v, dir);
	float perp = abs(dot(v, vec2(-dir.y, dir.x)));
	float tail = clamp(1.0 + along / len, 0.0, 1.0);
	return step(along, 0.0) * tail * tail * line_mask(perp, 1.2);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 center = rect_size * 0.5;
	float full = 1.0 - lite;

	vec3 col = vec3(0.0314, 0.0431, 0.1255);

	// Drifting glow orbs
	col = glow(col, p, vec2(0.18, 0.25), 330.0, vec3(0.30, 0.18, 0.75), 0.0);
	col = glow(col, p, vec2(0.82, 0.70), 390.0, vec3(0.08, 0.50, 0.75), 1.7);
	if (lite < 0.5) {
		col = glow(col, p, vec2(0.55, 0.42), 280.0, vec3(0.70, 0.10, 0.40), 3.4);
		col = glow(col, p, vec2(0.30, 0.82), 240.0, vec3(0.10, 0.60, 0.50), 5.1);

		// Scrolling grid
		vec2 gp = (p + vec2(t * 12.0, t * 8.0)) / 90.0;
		vec2 gd = abs(fract(gp - 0.5) - 0.5) * 90.0;
		col = mix(col, vec3(0.35, 0.60, 0.95), line_mask(min(gd.x, gd.y), 0.6) * 0.045);
	}

	// Moving diagonal energy lines
	float span = rect_size.y * 0.55;
	float u = p.x - span * (1.0 - p.y / rect_size.y) - t * 45.0;
	float ud = abs(fract(u / 180.0 - 0.5) - 0.5) * 180.0 * 0.876;
	col = mix(col, vec3(0.25, 0.55, 0.85), line_mask(ud, 1.0) * 0.08);

	// Horizontal scan line
	float sy = mod(t * 55.0, rect_size.y + 100.0) - 50.0;
	col = mix(col, vec3(0.35, 0.75, 1.0), line_mask(abs(p.y - sy), 1.0) * 0.07);
	col = mix(col, vec3(0.35, 0.75, 1.0), line_mask(abs(p.y - (sy + 5.0)), 4.0) * 0.025);

	// Parallax particles
	vec4 pc = particles(p, 1.0, 96.0, 0.045 * rect_size.y * 1.05, 1.0);
	col = mix(col, pc.rgb, pc.a);
	if (lite < 0.5) {
		pc = particles(p, 2.0, 120.0, 0.045 * rect_size.y * 0.5, 0.6);
		col = mix(col, pc.rgb, pc.a);
		pc = particles(p, 3.0, 80.0, 0.045 * rect_size.y * 1.6, 1.5);
		col = mix(col, pc.rgb, pc.a);

		// Meteor streaks
		float m = streak(p, 5.3, 0.7, 0.10, 220.0);
		m = max(m, streak(p, 7.1, 3.1, 0.38, 180.0));
		m = max(m, streak(p, 6.2, 5.0, 0.62, 260.0));
		col = mix(col, vec3(0.85, 0.95, 1.0), m * 0.8);
	}

	vec2 dv = p - center;
	float dist = length(dv);
	float ang = atan(dv.y, dv.x);

	// Rotating arc rings
	float spin = t * 0.12;
	float ra = mod(ang - spin, TAU_C);
	float in_arc = step(ra, 0.72 * TAU_C);
	float rings = max(line_mask(abs(dist - 170.0), 1.0), max(line_mask(abs(dist - 230.0), 1.0), line_mask(abs(dist - 300.0), 1.0)));
	col = mix(col, vec3(0.20, 0.65, 0.95), rings * in_arc * 0.08);

	if (lite < 0.5) {
		// Radar sweep with fading trail
		float sweep = t * 0.9;
		float da = mod(sweep - ang, TAU_C);
		float trail = clamp(1.0 - da / 0.63, 0.0, 1.0);
		col = mix(col, vec3(0.95, 0.25, 0.35), line_mask(abs(dist - 255.0), 2.0) * trail * 0.18);
		float dsw = da > PI_C ? da - TAU_C : da;
		float radial = step(0.0, cos(dsw)) * step(dist, 255.0) * line_mask(abs(dist * sin(dsw)), 1.0);
		col = mix(col, vec3(0.95, 0.30, 0.40), radial * 0.22);
	}

	// Central pulse
	float cp = (sin(t * 1.5) + 1.0) * 0.5;
	col = mix(col, vec3(0.10, 0.45, 0.70), (1.0 - smoothstep(79.0 + cp * 25.0, 80.0 + cp * 25.0, dist)) * 0.03);
	col = mix(col, vec3(0.25, 0.75, 1.0), line_mask(abs(dist - (100.0 + cp * 20.0)), 1.0) * 0.07);

	if (lite < 0.5) {
		// Ring burst fired on screen changes
		float age = t - kick_t0;
		if (age >= 0.0 && age < 1.0) {
			float rad = age * max(rect_size.x, rect_size.y) * 0.75;
			float w = 2.0 + (1.0 - age) * 6.0;
			col = mix(col, vec3(0.35, 0.80, 1.0), line_mask(abs(dist - rad), w * 0.5) * (1.0 - age) * 0.4);
		}

		// Pulsing red danger vignette
		float e = min(min(p.x, rect_size.x - p.x), min(p.y, rect_size.y - p.y));
		float v = 0.04 + 0.05 * (sin(t * 1.8) + 1.0) * 0.5;
		col = mix(col, vec3(0.95, 0.10, 0.20), v * 2.4 * (1.0 - smoothstep(0.0, 48.0, e)));
	}

	col = mix(col, dim.rgb, dim.a);
	COLOR = vec4(col, 1.0);
}
"""

var time := 0.0
var lite := false

var _material: ShaderMaterial
var _viewport: SubViewport
var _scale := 1.0
var _interval := 0.0
var _since_render := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	var small_device := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	_scale = render_scale if render_scale > 0.0 else (0.5 if small_device else 1.0)
	var fps := update_fps if update_fps > 0.0 else (30.0 if small_device else 0.0)
	_interval = 1.0 / fps if fps > 0.0 else 0.0

	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader

	var quad := ColorRect.new()
	quad.material = _material
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if _scale < 0.99 or _interval > 0.0:
		# Offscreen: render at a lower resolution and/or lower rate, then show
		# the result stretched over this control.
		_viewport = SubViewport.new()
		_viewport.disable_3d = true
		_viewport.transparent_bg = false
		_viewport.gui_disable_input = true
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_viewport)
		_viewport.add_child(quad)

		var screen := TextureRect.new()
		screen.texture = _viewport.get_texture()
		screen.stretch_mode = TextureRect.STRETCH_SCALE
		screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(screen)
	else:
		add_child(quad)

	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	_on_resized()
	_on_visibility_changed()


## Reduced effects: fewer layers and no grid / radar / meteors / vignette.
func set_lite(enabled: bool) -> void:
	lite = enabled
	if _material:
		_material.set_shader_parameter("lite", 1.0 if enabled else 0.0)


## Expanding ring burst, fired on every screen change.
## Bakes a translucent colour over the whole background (replaces a full-screen ColorRect).
func set_dim(color: Color) -> void:
	if _material:
		_material.set_shader_parameter("dim", Vector4(color.r, color.g, color.b, color.a))


func kick() -> void:
	if lite or _material == null:
		return
	_material.set_shader_parameter("kick_t0", time)


func _on_resized() -> void:
	if _material == null:
		return
	var s := size
	if s.x < 1.0 or s.y < 1.0:
		return
	_material.set_shader_parameter("rect_size", s)
	if _viewport:
		_viewport.size = Vector2i(maxi(1, int(s.x * _scale)), maxi(1, int(s.y * _scale)))


## The clock (and the offscreen render) only runs while the background is visible.
func _on_visibility_changed() -> void:
	var active := is_visible_in_tree()
	set_process(active)
	if active:
		_render_now()


func _process(delta: float) -> void:
	time += delta
	if _viewport == null:
		_material.set_shader_parameter("t", time)
		return

	_since_render += delta
	if _since_render >= _interval:
		_render_now()


func _render_now() -> void:
	_since_render = 0.0
	_material.set_shader_parameter("t", time)
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
