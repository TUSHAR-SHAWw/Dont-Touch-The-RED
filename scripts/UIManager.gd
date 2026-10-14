extends CanvasLayer

const SkinCatalog := preload("res://scripts/SkinCatalog.gd")
const AnimatedBackground := preload("res://scripts/AnimatedBackground.gd")
const TouchJoystick := preload("res://scripts/TouchJoystick.gd")
const CurrencyIcon := preload("res://scripts/CurrencyIcon.gd")
const CountdownRing := preload("res://scripts/CountdownRing.gd")

const ICON_SHIELD := preload("res://assets/shield.png")
const ICON_DOUBLE := preload("res://assets/double.png")
const ICON_MAGNET := preload("res://assets/magnet.png")

## All game UI built in code with responsive anchors/containers so it adapts to
## any aspect ratio (web, desktop, mobile).
##
## Animation overview
##  - Live background: drifting glow orbs, scrolling grid, radar sweep, parallax
##    particles, meteor streaks, pulsing red vignette, ring burst on screen change
##  - Menu: pulsing + swaying title, glitching red title, shine sweep on PLAY
##  - Every screen: staggered pop-in of its elements
##  - Every button: hover grow, press squash
##  - HUD: score / multiplier / coin pops, blinking low-time powerups
##  - Game over: score count-up, NEW BEST pulse
##  - "Reduced effects" only removes the heaviest stuff (glitch, shine, streaks,
##    vignette, flashes, stagger) - the UI still moves.

signal play_pressed
signal try_again_pressed
signal menu_pressed
signal mode_selected(mode)
signal skin_selected(skin)
signal skin_menu_pressed
signal skin_menu_closed
signal multiplier_upgrade_pressed
signal control_mode_selected(enabled)
signal touch_vector_changed(value)
signal settings_menu_pressed
signal settings_menu_closed
signal setting_changed(name, value)
signal volume_changed(name, value)
signal reset_game_requested
signal quit_requested
signal pause_requested
signal resume_requested
signal pause_settings_requested
signal pause_menu_requested
signal shop_menu_pressed
signal shop_menu_closed
signal shop_action(item, action)
signal item_use_requested(item)
signal revive_pressed
signal revive_ad_pressed
signal revive_declined
signal gem_ad_requested(placement)


# ============================================================================
# CONSTANTS
# ============================================================================

const OVERLAY_BG := Color(0.05, 0.05, 0.09, 0.82)
const MENU_OVERLAY := Color(0.015, 0.02, 0.07, 0.45)
const ACCENT := Color("#e02323")
const DIM := Color(0.65, 0.65, 0.7)
const LOCKED_DIM := Color(0.55, 0.55, 0.6)

const SHOP_PRICES := [30, 60, 90]
const MULTIPLIER_MAX_LEVEL := 8
const MULTIPLIER_STEP := 0.5
const MULTIPLIER_MAX := 5.0
const RESET_CONFIRM_SECONDS := 3.0
const SKIN_CARD_SIZE := 142
const GEM_COLOR := Color("#7be9ff")
const COIN_COLOR := Color("#f0c35c")

const HOVER_SCALE := 1.06
const PRESS_SCALE := 0.94
const STAGGER_STEP := 0.055

const MODE_NAMES: Array[String] = ["CLASSIC", "RUSH", "ZEN"]
const MODE_SUBTITLES: Array[String] = ["BALANCED", "HIGH SCORE", "RELAXED"]

const EFFECT_COLORS := {
	"shield": Color("#72d99a"),
	"score": Color("#ffcc58"),
	"magnet": Color("#70c8ff"),
}


# ============================================================================
# VARIABLES
# ============================================================================

var _background: AnimatedBackground

# HUD
var hud: Control
var hud_timer: Label
var hud_best: Label
var _score_label: Label
var _multiplier_label: Label
var _coins_label: Label
var _stage_label: Label
var _effects_bg: Control
var _effect_labels: Dictionary = {}
var _effects_empty_label: Label
var _item_bar: HBoxContainer
var _item_buttons: Array[Button] = []
var _hud_bar: ColorRect
var _hud_bar_accent: ColorRect
var _stage_background: ColorRect
var _pause_button: Button
var _gem_chip: HBoxContainer
var _gem_label: Label
var _gem_icon: Control

# Panels
var menu_panel: Control
var go_panel: Control
var skin_panel: Control
var settings_panel: Control
var shop_panel: Control
var pause_panel: Control
var revive_panel: Control

# Centers
var _menu_center: CenterContainer
var _skin_center: CenterContainer
var _go_center: CenterContainer
var _settings_center: CenterContainer
var _shop_center: CenterContainer
var _pause_center: CenterContainer
var _revive_center: CenterContainer

# Menu
var _menu_title: Label
var _red_title: Label
var _play_button: Button
var _shine: ColorRect
var _menu_best_card_value: Label
var _menu_coin_card_value: Label
var _menu_gem_card_value: Label
var _selected_mode_label: Label
var _mode_buttons: Array[Button] = []

# Game over
var go_score: Label
var go_best: Label
var _new_best_label: Label
var _try_again_button: Button
var _go_gems_label: Label
var _go_ad_button: Button

# Skins
var _skin_scroll: ScrollContainer
var _skin_buttons: Array[Button] = []
var _skin_textures: Array[TextureRect] = []
var _skin_costs: Array = []
var _skin_names: Array = []
var _skin_coins_label: Label

# Shop
var _shop_buttons: Array[Button] = []
var _shop_cards: Array[Control] = []
var _shop_icons: Array[Control] = []
var _shop_glows: Array[Control] = []
var _shop_owned_labels: Array[Label] = []
var _shop_colors: Array[Color] = []
var _shine_buttons: Array[Button] = []
var _shop_tweens: Array[Tween] = []
var _shop_coin_chip: Control
var _shop_gem_chip: Control
var _shop_coins_label: Label
var _shop_gem_label: Label
var _shop_hint: Label
var _shop_hint_token := 0
var _upgrade_row: Control
var _upgrade_button: Button
var _upgrade_label: Label
var _shop_gem_button: Button

# Revive prompt + ad placeholder
var _revive_ring: CountdownRing
var _revive_number: Label
var _revive_subtitle: Label
var _revive_info: Label
var _revive_button: Button
var _revive_ad_button: Button
var _revive_skip_button: Button
var _revive_gems_label: Label
var _revive_last_second := -1
var _revive_pulse_tween: Tween
var _ad_panel: Control
var _ad_bar: ColorRect
var _ad_title: Label
var _ad_tween: Tween
var _ad_pulse_tween: Tween

# Settings
var _settings_scroll: ScrollContainer
var _setting_buttons: Dictionary = {}
var _setting_sliders: Dictionary = {}
var _setting_states: Dictionary = {}
var _reset_button: Button
var _reset_armed := false
var _reset_token := 0

# Loading
var _loading_panel: Control
var _loading_label: Label
var _loading_bar: ColorRect

# Overlay effects
var _flash: ColorRect
var _powerup_label: Label

# Touch
var _touch_joystick: TouchJoystick

# State cache
var _total_coins := 0
var _gems := 0
var _gem_value_labels: Array[Label] = []
var _gem_icons: Array[Control] = []
var _multiplier_level := 0
var _inventory: Array = []
var _reduced_effects := false
var _touch_controls := false
var _last_score := 0
## Blurred StyleBox shadows are costly on phones, so they are skipped there.
var _lite_shadows := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
var _last_sec := -1
var _last_time_text := ""
var _last_fx_key := ""
var _last_multiplier := 1.0
var _last_hud_coins := -1

# Layout
var _scale_factor := 1.0
var _settings_scale := 1.0

# Tweens
var _title_tween: Tween
var _sway_tween: Tween
var _play_tween: Tween
var _shine_tween: Tween
var _glitch_tween: Tween
var _flash_tween: Tween
var _pulse_tween: Tween
var _stage_tween: Tween
var _powerup_tween: Tween
var _loading_tween: Tween
var _loading_pulse_tween: Tween
var _score_tween: Tween
var _best_tween: Tween
var _equipped_tween: Tween
var _center_tweens: Dictionary = {}
var _stagger_tweens: Dictionary = {}
var _pop_tweens: Dictionary = {}

# Caches
var _style_cache: Dictionary = {}
var _focus_buttons: Dictionary = {}


# ============================================================================
# READY
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_hud()

	# One shared animated background: above the HUD, below every panel.
	_background = AnimatedBackground.new()
	_full_rect(_background)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.visible = false
	add_child(_background)

	_build_menu()
	_build_game_over()
	_build_skin_menu()
	_build_settings_menu()
	_build_shop_menu()
	_build_pause_menu()
	_build_revive_menu()
	_build_overlays()
	_build_touch_joystick()
	_build_loading_screen()
	_build_ad_placeholder()

	_apply_responsive_layout()
	get_viewport().size_changed.connect(_apply_responsive_layout)

	_highlight_mode(0)


# ============================================================================
# SETTINGS / GAME STATE
# ============================================================================

func set_touch_controls(enabled: bool) -> void:
	_touch_controls = enabled
	if is_instance_valid(_touch_joystick):
		_touch_joystick.visible = enabled and hud.visible and not pause_panel.visible
	_set_setting_button("touch_controls", enabled, "TOUCH JOYSTICK")


func set_settings(
	music_enabled: bool,
	sfx_enabled: bool,
	shake_enabled: bool,
	reduced_effects: bool,
	touch_enabled: bool,
	music_volume_db: float = -12.0,
	sfx_volume_db: float = -6.0
) -> void:
	_set_setting_button("music", music_enabled, "MUSIC")
	_set_setting_button("sfx", sfx_enabled, "SFX")
	_set_volume_slider("music_volume", music_volume_db)
	_set_volume_slider("sfx_volume", sfx_volume_db)
	_set_setting_button("shake", shake_enabled, "SCREEN SHAKE")
	_set_setting_button("reduced_effects", reduced_effects, "REDUCED EFFECTS")
	_set_setting_button("touch_controls", touch_enabled, "TOUCH JOYSTICK")
	set_reduced_effects(reduced_effects)
	set_touch_controls(touch_enabled)


func _set_volume_slider(key: String, value: float) -> void:
	if not _setting_sliders.has(key):
		return
	var slider: HSlider = _setting_sliders[key]
	# No signal: otherwise syncing the UI would re-save the value it just read.
	slider.set_value_no_signal(value)


func _set_setting_button(key: String, enabled: bool, label: String) -> void:
	if not _setting_buttons.has(key):
		return
	_setting_states[key] = enabled
	var button: Button = _setting_buttons[key]
	button.text = "%s: %s" % [label, "ON" if enabled else "OFF"]
	button.modulate = Color.WHITE if enabled else DIM


func set_reduced_effects(enabled: bool) -> void:
	_reduced_effects = enabled
	if is_instance_valid(_background):
		_background.set_lite(enabled)
	if is_instance_valid(menu_panel) and menu_panel.visible:
		_start_menu_tweens()


# ============================================================================
# PROGRESSION
# ============================================================================

func set_progression(
	total_coins: int,
	selected_skin: int,
	unlocked: Array,
	multiplier_level := 0
) -> void:

	_total_coins = total_coins
	_multiplier_level = multiplier_level

	if is_instance_valid(_coins_label):
		_coins_label.text = "COINS: %d" % total_coins
	if is_instance_valid(_skin_coins_label):
		_skin_coins_label.text = "YOUR COINS: %d" % total_coins

	_tween_number(_menu_coin_card_value, total_coins)

	_kill_tween(_equipped_tween)

	for i in range(_skin_buttons.size()):
		var owned: bool = i < unlocked.size() and bool(unlocked[i])
		var button := _skin_buttons[i]
		var skin_name: String = str(_skin_names[i]) if i < _skin_names.size() else ""
		var cost: int = int(_skin_costs[i]) if i < _skin_costs.size() else 0

		if owned and i == selected_skin:
			button.text = "EQUIPPED"
			button.modulate = Color(1.0, 0.92, 0.6)
		elif owned:
			button.text = skin_name
			button.modulate = Color.WHITE
		else:
			button.text = "%s  %d C" % [skin_name, cost]
			button.modulate = Color.WHITE if total_coins >= cost else LOCKED_DIM

		if i < _skin_textures.size():
			_skin_textures[i].modulate = Color.WHITE if owned else Color(0.42, 0.42, 0.48)

	# Equipped skin gets a soft golden glow pulse.
	if selected_skin >= 0 and selected_skin < _skin_textures.size() \
			and selected_skin < unlocked.size() and bool(unlocked[selected_skin]):
		var tex := _skin_textures[selected_skin]
		_equipped_tween = create_tween().set_loops()
		_equipped_tween.tween_property(tex, "modulate", Color(1.3, 1.2, 0.8), 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_equipped_tween.tween_property(tex, "modulate", Color.WHITE, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_refresh_shop()


## Gem balance. `animate` plays the "gained" effect (ad reward).
func set_gems(value: int, animate := false) -> void:
	var gained := value > _gems
	_gems = value
	if is_instance_valid(_gem_label):
		_gem_label.text = str(value)
	if is_instance_valid(_go_gems_label):
		_go_gems_label.text = "GEMS: %d" % value
	if is_instance_valid(_revive_gems_label):
		_revive_gems_label.text = str(value)
	for label in _gem_value_labels:
		_tween_number(label, value)
	if animate and gained:
		_pop(_gem_chip, 1.5, 0.4, 0.0)
		for icon in _gem_icons:
			if is_instance_valid(icon):
				icon.sparkle()
		if is_instance_valid(_shop_gem_chip):
			_pop(_shop_gem_chip, 1.25, 0.35, 0.0)
	_refresh_revive_buttons()


func set_shop(total_coins: int, inventory: Array) -> void:
	_total_coins = total_coins
	_inventory = inventory.duplicate()
	if is_instance_valid(_coins_label):
		_coins_label.text = "COINS: %d" % total_coins
	_tween_number(_menu_coin_card_value, total_coins)
	_refresh_shop()


func _refresh_shop() -> void:
	if is_instance_valid(_shop_coins_label):
		_tween_number(_shop_coins_label, _total_coins)

	for i in range(_shop_buttons.size()):
		var count := int(_inventory[i]) if i < _inventory.size() else 0
		var price: int = SHOP_PRICES[i]
		_shop_buttons[i].text = "BUY  %d" % price
		_shop_buttons[i].modulate = Color.WHITE if _total_coins >= price else DIM
		if i < _shop_owned_labels.size():
			_shop_owned_labels[i].text = "OWNED: %d" % count

	if is_instance_valid(_upgrade_label):
		_upgrade_label.text = "PERMANENT MULTIPLIER  x%.1f" % minf(
			MULTIPLIER_MAX,
			1.0 + _multiplier_level * MULTIPLIER_STEP
		)

	if is_instance_valid(_upgrade_button):
		if _multiplier_level >= MULTIPLIER_MAX_LEVEL:
			_upgrade_button.text = "MAXED"
			_upgrade_button.disabled = true
		else:
			var cost := 50 + _multiplier_level * 75
			_upgrade_button.text = "UPGRADE  %d" % cost
			_upgrade_button.disabled = false
			_upgrade_button.modulate = Color.WHITE if _total_coins >= cost else DIM


func set_item_inventory(inventory: Array) -> void:
	var labels := ["1 SHIELD", "2 DOUBLE", "3 MAGNET"]
	for i in range(_item_buttons.size()):
		var count := int(inventory[i]) if i < inventory.size() else 0
		_item_buttons[i].text = "%s  x%d" % [labels[i], count]
		_item_buttons[i].disabled = count <= 0


# ============================================================================
# EFFECTS
# ============================================================================

func flash_danger() -> void:
	if _reduced_effects:
		return
	_kill_tween(_flash_tween)
	_flash.color.a = 0.42
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, 0.3)


func pulse_danger() -> void:
	if not hud.visible:
		return
	_kill_tween(_pulse_tween)
	hud_timer.scale = Vector2.ONE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(hud_timer, "scale", Vector2(1.12, 1.12), 0.06)
	_pulse_tween.tween_property(hud_timer, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_stage(title: String, subtext := "") -> void:
	if not is_instance_valid(_stage_label):
		return

	var display_text := title
	if not subtext.is_empty():
		display_text = title + "\n" + subtext
	_stage_label.text = display_text

	# Animate the font color itself (animating modulate would multiply with it).
	_kill_tween(_stage_tween)
	_stage_label.scale = Vector2(1.18, 1.18)
	_stage_tween = create_tween().set_parallel(true)
	_stage_tween.tween_method(
		func(c: Color) -> void:
			_stage_label.add_theme_color_override("font_color", c),
		Color("#fff1c4"),
		Color("#f3d17b"),
		0.6
	)
	_stage_tween.tween_property(_stage_label, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_milestone(seconds: int) -> void:
	show_powerup("%d SECONDS SURVIVED" % seconds)


func show_powerup(text: String) -> void:
	_kill_tween(_powerup_tween)
	_powerup_label.text = text
	_powerup_label.modulate = Color(1.0, 0.8, 0.3, 0.0)
	_powerup_label.scale = Vector2(1.5, 1.5)

	_powerup_tween = create_tween().set_parallel(true)
	_powerup_tween.tween_property(_powerup_label, "modulate:a", 1.0, 0.1)
	_powerup_tween.tween_property(_powerup_label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_powerup_tween.chain().tween_interval(1.0)
	_powerup_tween.chain().tween_property(_powerup_label, "modulate:a", 0.0, 0.35)


func show_pickup(text: String, color: Color, screen_pos := Vector2(-1.0, -1.0)) -> void:
	var popup := _label(text, 28, color)
	var viewport_size := get_viewport().get_visible_rect().size
	var origin := viewport_size * 0.5
	if screen_pos.x >= 0.0:
		origin = Vector2(
			clampf(screen_pos.x, 90.0, maxf(90.0, viewport_size.x - 90.0)),
			clampf(screen_pos.y, 60.0, maxf(60.0, viewport_size.y - 40.0))
		)

	popup.size = Vector2(180.0, 44.0)
	popup.pivot_offset = popup.size * 0.5
	popup.position = origin + Vector2(-90.0 + randf_range(-20.0, 20.0), -58.0)
	popup.modulate.a = 0.0
	popup.scale = Vector2(0.6, 0.6)
	popup.rotation = randf_range(-0.14, 0.14)
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	popup.add_theme_constant_override("outline_size", 6)
	add_child(popup)

	var tween := popup.create_tween().set_parallel(true)
	tween.tween_property(popup, "modulate:a", 1.0, 0.08)
	tween.tween_property(popup, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "rotation", 0.0, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "position:y", popup.position.y - 56.0, 0.65) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, 0.25).set_delay(0.65)
	tween.chain().tween_callback(popup.queue_free)


# ============================================================================
# PUBLIC SCREEN FUNCTIONS
# ============================================================================

func show_menu(best: int) -> void:
	hide_loading()
	_show_only(menu_panel)

	_play_button.disabled = false
	_tween_number(_menu_best_card_value, best, 0)
	_tween_number(_menu_coin_card_value, _total_coins, 0)

	_animate_center(_menu_center)


func set_selected_mode(mode: int) -> void:
	if mode < 0 or mode >= MODE_NAMES.size():
		return
	if is_instance_valid(_selected_mode_label):
		_selected_mode_label.text = "SELECTED: " + MODE_NAMES[mode]
		_pop(_selected_mode_label, 1.25, 0.25)
	_highlight_mode(mode)


func show_loading(text := "LOADING") -> void:
	_loading_panel.visible = true
	_loading_label.text = text
	_loading_bar.size = Vector2(0.0, 6.0)
	var load_width := minf(420.0, maxf(180.0, get_viewport().get_visible_rect().size.x - 48.0))

	_kill_tween(_loading_tween)
	_loading_tween = create_tween()
	_loading_tween.tween_property(_loading_bar, "size:x", load_width, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_kill_tween(_loading_pulse_tween)
	_loading_pulse_tween = create_tween().set_loops()
	_loading_pulse_tween.tween_property(_loading_label, "modulate:a", 0.45, 0.5) \
		.set_trans(Tween.TRANS_SINE)
	_loading_pulse_tween.tween_property(_loading_label, "modulate:a", 1.0, 0.5) \
		.set_trans(Tween.TRANS_SINE)


func hide_loading() -> void:
	_loading_panel.visible = false
	_kill_tween(_loading_pulse_tween)
	if is_instance_valid(_loading_label):
		_loading_label.modulate.a = 1.0


func show_skin_menu() -> void:
	_show_only(skin_panel)
	_animate_center(_skin_center)


func show_settings() -> void:
	_disarm_reset()
	_show_only(settings_panel)
	_animate_center(_settings_center)


func show_shop() -> void:
	_show_only(shop_panel)
	_refresh_shop()
	_animate_center(_shop_center)


func show_pause() -> void:
	_show_only(pause_panel, false, true)
	_animate_center(_pause_center)


func show_revive(gems: int, total_time: float, revives_left: int) -> void:
	_gems = gems
	_revive_last_second = -1
	_revive_info.text = "REVIVES LEFT THIS RUN: %d" % revives_left
	_refresh_revive_buttons()
	_show_only(revive_panel, false, true)
	update_revive_timer(total_time, total_time)
	_animate_center(_revive_center)
	_kill_tween(_revive_pulse_tween)
	if _revive_button.visible:
		_revive_pulse_tween = _loop_pulse(_revive_button, 1.04, 0.6)


func hide_revive() -> void:
	if not is_instance_valid(revive_panel) or not revive_panel.visible:
		return
	revive_panel.visible = false
	_kill_tween(_revive_pulse_tween)
	_revive_button.scale = Vector2.ONE
	_touch_joystick.visible = _touch_controls and hud.visible and not pause_panel.visible


func update_revive_timer(left: float, total: float) -> void:
	if not is_instance_valid(_revive_ring):
		return
	_revive_ring.progress = left / maxf(total, 0.01)
	var sec := maxi(0, ceili(left))
	if sec != _revive_last_second:
		_revive_last_second = sec
		_revive_number.text = str(sec)
		_revive_number.add_theme_color_override("font_color", Color("#ff6b7a") if sec <= 2 else Color.WHITE)
		_pop(_revive_number, 1.35, 0.3, 0.0)


func _refresh_revive_buttons() -> void:
	if not is_instance_valid(_revive_button):
		return
	if _gems > 0:
		_revive_subtitle.text = "SPEND 1 GEM TO KEEP YOUR RUN GOING"
		_revive_button.visible = true
		_revive_ad_button.text = "OR WATCH AN AD: FREE REVIVE"
	else:
		_revive_subtitle.text = "OUT OF GEMS - WATCH AN AD TO CONTINUE"
		_revive_button.visible = false
		_revive_ad_button.text = "WATCH AD TO REVIVE"
	_revive_ad_button.custom_minimum_size.y = 58.0 if _gems > 0 else 72.0
	_focus_buttons[revive_panel] = _revive_button if _gems > 0 else _revive_ad_button


func show_ad_placeholder(seconds: float) -> void:
	_ad_panel.visible = true
	_ad_bar.size = Vector2(0.0, _ad_bar.size.y)
	_kill_tween(_ad_tween)
	_ad_tween = create_tween()
	_ad_tween.tween_property(_ad_bar, "size:x", 320.0, maxf(seconds, 0.1))
	_kill_tween(_ad_pulse_tween)
	_ad_pulse_tween = create_tween().set_loops()
	_ad_pulse_tween.tween_property(_ad_title, "modulate:a", 0.55, 0.45).set_trans(Tween.TRANS_SINE)
	_ad_pulse_tween.tween_property(_ad_title, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)


func hide_ad_placeholder() -> void:
	if not is_instance_valid(_ad_panel):
		return
	_ad_panel.visible = false
	_kill_tween(_ad_tween)
	_kill_tween(_ad_pulse_tween)


func hide_pause() -> void:
	pause_panel.visible = false
	_touch_joystick.visible = _touch_controls and hud.visible


func show_hud(best: int, total_coins := 0, multiplier := 1.0) -> void:
	hide_loading()
	_show_only(null, false, true)
	_touch_joystick.visible = _touch_controls

	# Reset pop trackers so the HUD doesn't "pop" just from starting a run.
	_last_score = -1 # -1 forces the label refresh below without a pop
	_last_multiplier = multiplier
	_multiplier_label.text = "x%.1f" % multiplier
	_last_sec = -1
	_last_fx_key = ""
	_last_hud_coins = -1

	update_timer(0.0, 0, multiplier, total_coins)
	hud_best.text = "BEST: %d" % best


func show_game_over(score: int, best: int, earned_coins := 0, multiplier := 1.0) -> void:
	_show_only(go_panel)

	go_best.text = "BEST: %d  COINS: +%d  MULTIPLIER X%.1f" % [best, earned_coins, multiplier]
	_go_gems_label.text = "GEMS: %d" % _gems

	var is_new_best := score > 0 and score >= best
	_new_best_label.visible = is_new_best

	_kill_tween(_score_tween)
	_kill_tween(_best_tween)
	_new_best_label.scale = Vector2.ONE

	if _reduced_effects:
		go_score.text = "SCORE: %d" % score
	else:
		# Score counts up, then pops.
		go_score.text = "SCORE: 0"
		_score_tween = create_tween()
		_score_tween.tween_interval(0.3)
		_score_tween.tween_method(
			func(v: float) -> void:
				go_score.text = "SCORE: %d" % int(v),
			0.0,
			float(score),
			0.9
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_score_tween.tween_callback(func() -> void: _pop(go_score, 1.22, 0.3))

		if is_new_best:
			_best_tween = create_tween().set_loops()
			_best_tween.tween_property(_new_best_label, "scale", Vector2(1.16, 1.16), 0.45) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_best_tween.tween_property(_new_best_label, "scale", Vector2.ONE, 0.45) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_animate_center(_go_center)


func update_timer(
	seconds: float,
	score := 0,
	multiplier := 1.0,
	total_coins := -1
) -> void:

	# Only touch labels when the value changed (text updates re-layout the label).
	var sec := int(seconds)
	if sec != _last_sec:
		_last_sec = sec
		hud_timer.text = "TIME: " + _fmt_time(sec)

	if score != _last_score:
		_score_label.text = "SCORE: %d" % score
		if _last_score >= 0 and score > _last_score:
			_pop(_score_label, 1.18, 0.2)
		_last_score = score

	if not is_equal_approx(multiplier, _last_multiplier):
		_multiplier_label.text = "x%.1f" % multiplier
		_pop(_multiplier_label, 1.5, 0.35)
		_last_multiplier = multiplier

	# Only touch the coin label when the caller supplies a value.
	if total_coins >= 0:
		_coins_label.text = "COINS: %d" % total_coins
		if _last_hud_coins >= 0 and total_coins > _last_hud_coins:
			_pop(_coins_label, 1.35, 0.3)
		_last_hud_coins = total_coins


func update_active_effects(shield: bool, score_time: float, magnet_time: float) -> void:
	var has_score := score_time > 0.0
	var has_magnet := magnet_time > 0.0

	var key := "%d|%d|%d" % [int(shield), ceili(score_time), ceili(magnet_time)]
	var blinking := (has_score and score_time <= 3.0) or (has_magnet and magnet_time <= 3.0)
	if key == _last_fx_key and not blinking:
		return # nothing visible changed
	_last_fx_key = key

	_effect_labels["shield"].visible = shield
	_effect_labels["score"].visible = has_score
	_effect_labels["magnet"].visible = has_magnet

	if has_score:
		_effect_labels["score"].text = "DOUBLE SCORE  %02ds" % ceili(score_time)
		_effect_labels["score"].modulate.a = _blink(score_time)
	if has_magnet:
		_effect_labels["magnet"].text = "COIN MAGNET   %02ds" % ceili(magnet_time)
		_effect_labels["magnet"].modulate.a = _blink(magnet_time)

	# The ACTIVE POWERUPS panel is permanent. Keep the panel visible even when
	# there are no active effects, and show a small empty-state message.
	_effects_bg.visible = true
	if is_instance_valid(_effects_empty_label):
		_effects_empty_label.visible = not (shield or has_score or has_magnet)


## Powerups blink when they are about to run out.
func _blink(time_left: float) -> float:
	if time_left > 3.0 or _reduced_effects:
		return 1.0
	return 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.018)


# ============================================================================
# SCREEN SWITCHING
# ============================================================================

func _show_only(target: Control, show_background := true, keep_hud := false) -> void:
	for p in [menu_panel, go_panel, skin_panel, settings_panel, shop_panel, pause_panel, revive_panel]:
		p.visible = (p == target)

	hud.visible = keep_hud
	_background.visible = show_background and target != null
	_touch_joystick.visible = false

	# The dim is baked into the background shader, so the full-screen alpha
	# overlay is hidden whenever the background is showing.
	if target != null and target.has_meta("overlay"):
		var ov := target.get_meta("overlay") as ColorRect
		if _background.visible:
			_background.set_dim(ov.color)
		ov.visible = not _background.visible

	if _background.visible:
		_background.kick()

	if target == menu_panel:
		_start_menu_tweens()
	else:
		_stop_menu_tweens()

	if target == shop_panel:
		_start_shop_tweens()
	else:
		_stop_shop_tweens()

	if target != go_panel:
		_kill_tween(_score_tween)
		_kill_tween(_best_tween)

	if target != null:
		_focus_default(target)


func _focus_default(panel: Control) -> void:
	if OS.has_feature("mobile") or not _focus_buttons.has(panel):
		return
	var button: Button = _focus_buttons[panel]
	if is_instance_valid(button):
		button.grab_focus.call_deferred()


# ============================================================================
# HUD
# ============================================================================

func _build_hud() -> void:
	hud = Control.new()
	_full_rect(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	# Top HUD bar. Its height and child positions are adjusted in
	# _apply_responsive_layout() so narrow screens never crush the timer.
	_hud_bar = ColorRect.new()
	_hud_bar.color = Color(0.07, 0.07, 0.10, 0.82)
	_set_rect(_hud_bar, Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 92))
	_hud_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hud_bar)

	_hud_bar_accent = ColorRect.new()
	_hud_bar_accent.color = Color("#f59e0b")
	_set_rect(_hud_bar_accent, Vector4(0, 1, 1, 1), Vector4(0, -4, 0, 0))
	_hud_bar_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_bar.add_child(_hud_bar_accent)

	# Center timer. The width is deliberately smaller than the old 440px
	# fixed box; _apply_responsive_layout() gives it a safe width on every
	# aspect ratio.
	hud_timer = _label("TIME: 00:00", 52, Color.WHITE)
	hud_timer.clip_text = false
	hud.add_child(hud_timer)
	hud_timer.z_index = 20
	_center_pivot(hud_timer)

	# Best score lives in the upper-right corner.
	hud_best = _label("BEST: 0", 30, Color("#c5c5cf"))
	hud_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(hud_best)
	hud_best.z_index = 20

	# Gem counter sits under the best score (upper-right).
	_gem_chip = HBoxContainer.new()
	_gem_chip.alignment = BoxContainer.ALIGNMENT_END
	_gem_chip.add_theme_constant_override("separation", 6)
	_gem_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_gem_chip)
	_gem_chip.z_index = 20
	var hud_gem_icon := CurrencyIcon.new()
	hud_gem_icon.kind = CurrencyIcon.Kind.GEM
	hud_gem_icon.custom_minimum_size = Vector2(26, 26)
	_gem_chip.add_child(hud_gem_icon)
	_gem_icon = hud_gem_icon
	_gem_icons.append(hud_gem_icon)
	_gem_label = _label("0", 26, GEM_COLOR)
	_gem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gem_chip.add_child(_gem_label)
	_center_pivot(_gem_chip)

	# Score stack on the upper-left.
	_score_label = _label("SCORE: 0", 24, Color("#e8e8ef"))
	hud.add_child(_score_label)
	_score_label.z_index = 20
	_center_pivot(_score_label)

	_multiplier_label = _label("x1.0", 30, Color("#ffcc58"))
	hud.add_child(_multiplier_label)
	_multiplier_label.z_index = 20
	_center_pivot(_multiplier_label)

	_coins_label = _label("COINS: 0", 20, Color("#f0c35c"))
	hud.add_child(_coins_label)
	_coins_label.z_index = 30
	_center_pivot(_coins_label)

	# Stage panel. It remains on the right on desktop, but moves below the
	# top bar on narrow screens instead of consuming almost the whole width.
	_stage_background = ColorRect.new()
	_stage_background.color = Color(0.05, 0.05, 0.09, 0.78)
	_stage_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_stage_background)
	_stage_background.z_index = 5

	var stage_box := VBoxContainer.new()
	_set_rect(stage_box, Vector4(0, 0, 1, 1), Vector4(12, 8, -12, -8))
	_stage_background.add_child(stage_box)

	var stage_title := _label("STAGE", 16, Color("#b8b8c4"))
	stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stage_box.add_child(stage_title)

	_stage_label = _label("1\nCOLD START", 18, Color("#f3d17b"))
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stage_box.add_child(_stage_label)
	_center_pivot(_stage_label)

	# Active effects panel. Like the stage panel, its position/width is
	# responsive and therefore cannot cover the whole HUD on phones.
	_effects_bg = ColorRect.new()
	(_effects_bg as ColorRect).color = Color(0.05, 0.05, 0.09, 0.78)
	_effects_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects_bg.visible = true
	hud.add_child(_effects_bg)
	_effects_bg.z_index = 5

	var effects_box := VBoxContainer.new()
	_set_rect(effects_box, Vector4(0, 0, 1, 1), Vector4(12, 8, -12, -8))
	_effects_bg.add_child(effects_box)
	effects_box.z_index = 10

	var effects_title := _label("ACTIVE POWERUPS", 16, Color("#b8b8c4"))
	effects_title.z_index = 15
	effects_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	effects_box.add_child(effects_title)

	for key in ["shield", "score", "magnet"]:
		var effect_label := _label("", 19, EFFECT_COLORS[key])
		effect_label.z_index = 15
		effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		effect_label.visible = false
		_effect_labels[key] = effect_label
		effects_box.add_child(effect_label)

	_effect_labels["shield"].text = "SHIELD       READY"

	_effects_empty_label = _label("NO ACTIVE POWERUPS", 15, Color("#777d91"))
	_effects_empty_label.z_index = 15
	effects_box.add_child(_effects_empty_label)

	# Bottom item bar. Its width and location are recalculated for touch mode
	# so it never sits underneath the joystick.
	_item_bar = HBoxContainer.new()
	_item_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_item_bar.add_theme_constant_override("separation", 8)
	hud.add_child(_item_bar)

	for i in range(3):
		var item_button := _button("ITEM", Color("#3a3a44"))
		item_button.custom_minimum_size = Vector2(0, 52)
		item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_button.add_theme_font_size_override("font_size", 16)
		item_button.pressed.connect(_on_item_pressed.bind(i))
		_item_bar.add_child(item_button)
		_item_buttons.append(item_button)

	_pause_button = _button("PAUSE", Color("#3a3a44"))
	_pause_button.custom_minimum_size = Vector2(132, 48)
	_pause_button.add_theme_font_size_override("font_size", 18)
	_pause_button.pressed.connect(func() -> void: pause_requested.emit())
	hud.add_child(_pause_button)


func _on_item_pressed(index: int) -> void:
	item_use_requested.emit(index)


# ============================================================================
# MAIN MENU
# ============================================================================

func _build_menu() -> void:
	var screen := _create_screen(12)
	menu_panel = screen["panel"]
	_menu_center = screen["center"]
	var box: VBoxContainer = screen["box"]

	_menu_title = _label("DON'T TOUCH", 58, Color.WHITE)
	_add_title_shadow(_menu_title)
	box.add_child(_menu_title)
	_center_pivot(_menu_title)

	_red_title = _label("THE RED", 58, ACCENT)
	_add_title_shadow(_red_title)
	box.add_child(_red_title)
	_center_pivot(_red_title)

	box.add_child(_label("DODGE  •  SURVIVE  •  SCORE", 19, Color("#9da3b4")))

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 10)

	var best_card := _stat_card("BEST", "0", Color("#f7c85b"))
	stats.add_child(best_card)
	_menu_best_card_value = best_card.get_meta("value_label") as Label

	var coin_card := _stat_card("COINS", "0", COIN_COLOR, CurrencyIcon.Kind.COIN)
	stats.add_child(coin_card)
	_menu_coin_card_value = coin_card.get_meta("value_label") as Label

	var gem_card := _stat_card("GEMS", "0", GEM_COLOR, CurrencyIcon.Kind.GEM)
	stats.add_child(gem_card)
	_menu_gem_card_value = gem_card.get_meta("value_label") as Label
	_gem_value_labels.append(_menu_gem_card_value)
	_gem_icons.append(gem_card.get_meta("icon"))

	box.add_child(stats)

	# Play button (pulses by itself, so it skips hover scaling)
	_play_button = _button("PLAY", ACCENT)
	_play_button.custom_minimum_size = Vector2(360, 76)
	_play_button.add_theme_font_size_override("font_size", 30)
	_play_button.set_meta("no_hover_scale", true)
	_play_button.clip_contents = true
	_play_button.pressed.connect(_on_play_pressed)
	box.add_child(_play_button)
	_focus_buttons[menu_panel] = _play_button

	# Shine strip that sweeps across the play button
	_shine = ColorRect.new()
	_shine.color = Color(1.0, 1.0, 1.0, 0.16)
	_shine.size = Vector2(46.0, 76.0)
	_shine.position = Vector2(-60.0, 0.0)
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play_button.add_child(_shine)
	_play_button.resized.connect(
		func() -> void:
			_shine.size.y = _play_button.size.y
	)

	box.add_child(_label("GAME MODE", 15, Color("#777d91")))

	var modes := HBoxContainer.new()
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	modes.add_theme_constant_override("separation", 8)

	for i in range(MODE_NAMES.size()):
		var mode_button := _button(MODE_NAMES[i] + "\n" + MODE_SUBTITLES[i], Color("#292d3a"))
		mode_button.custom_minimum_size = Vector2(120, 62)
		mode_button.add_theme_font_size_override("font_size", 16)
		mode_button.pressed.connect(_on_mode_pressed.bind(i))
		modes.add_child(mode_button)
		_mode_buttons.append(mode_button)

	box.add_child(modes)

	_selected_mode_label = _label("SELECTED: CLASSIC", 14, Color("#f7c85b"))
	box.add_child(_selected_mode_label)
	_center_pivot(_selected_mode_label)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 8)

	_add_menu_nav_button(nav, "SKINS", func() -> void: skin_menu_pressed.emit())
	_add_menu_nav_button(nav, "SHOP", func() -> void: shop_menu_pressed.emit())
	_add_menu_nav_button(nav, "SETTINGS", func() -> void: settings_menu_pressed.emit())

	box.add_child(nav)


func _on_play_pressed() -> void:
	_play_button.disabled = true
	play_transition()
	play_pressed.emit()


func _on_mode_pressed(index: int) -> void:
	mode_selected.emit(index)


func _highlight_mode(mode: int) -> void:
	for i in range(_mode_buttons.size()):
		_mode_buttons[i].modulate = Color.WHITE if i == mode else DIM
		if i == mode:
			_pop(_mode_buttons[i], 1.1, 0.25)


func _add_title_shadow(l: Label) -> void:
	if _lite_shadows:
		return
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 4)


func _add_menu_nav_button(parent: HBoxContainer, text: String, action: Callable) -> void:
	var button := _button(text, Color("#20232d"))
	button.custom_minimum_size = Vector2(112, 46)
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(action)
	parent.add_child(button)


# ============================================================================
# STAT CARD
# ============================================================================

func _stat_card(title: String, value: String, color: Color, icon_kind := -1) -> PanelContainer:
	var panel := PanelContainer.new()

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151923")
	style.border_color = Color("#2b3040")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(130, 58)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_label(title, 12, Color("#8b91a3")))

	var value_label := _label(value, 21, color)
	if icon_kind >= 0:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		var icon := CurrencyIcon.new()
		icon.kind = icon_kind as CurrencyIcon.Kind
		icon.custom_minimum_size = Vector2(22, 22)
		icon.animated = icon_kind == CurrencyIcon.Kind.GEM
		row.add_child(icon)
		row.add_child(value_label)
		box.add_child(row)
		panel.set_meta("icon", icon)
	else:
		box.add_child(value_label)
	_center_pivot(value_label)

	panel.add_child(box)
	panel.set_meta("value_label", value_label)
	return panel


# ============================================================================
# SETTINGS MENU
# ============================================================================

func _build_settings_menu() -> void:
	var screen := _create_screen(10)
	settings_panel = screen["panel"]
	_settings_center = screen["center"]
	var box: VBoxContainer = screen["box"]

	box.add_child(_label("SETTINGS", 52, Color.WHITE))
	box.add_child(_label("TUNE THE EXPERIENCE", 20, Color("#b8b8c4")))

	_settings_scroll = ScrollContainer.new()
	_settings_scroll.name = "SettingsScroll"
	_settings_scroll.custom_minimum_size = Vector2(360, 360)
	_settings_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_settings_scroll.follow_focus = true
	box.add_child(_settings_scroll)

	var settings_box := VBoxContainer.new()
	settings_box.name = "SettingsContent"
	settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_box.add_theme_constant_override("separation", 8)
	_settings_scroll.add_child(settings_box)

	_add_setting_button(settings_box, "music", "MUSIC")
	_add_setting_button(settings_box, "sfx", "SFX")
	_add_volume_slider(settings_box, "music_volume", "MUSIC VOLUME", -40.0, 6.0, 0.5)
	_add_volume_slider(settings_box, "sfx_volume", "SFX VOLUME", -40.0, 6.0, 0.5)
	_add_setting_button(settings_box, "shake", "SCREEN SHAKE")
	_add_setting_button(settings_box, "reduced_effects", "REDUCED EFFECTS")
	_add_setting_button(settings_box, "touch_controls", "TOUCH JOYSTICK")

	_reset_button = _button("RESET GAME DATA", Color("#6d2020"))
	_reset_button.custom_minimum_size = Vector2(320, 58)
	_reset_button.add_theme_font_size_override("font_size", 18)
	_reset_button.pressed.connect(_on_reset_pressed)
	settings_box.add_child(_reset_button)

	# BACK stays outside the scroll area so it is always reachable.
	var back := _button("BACK", Color("#3a3a44"))
	back.custom_minimum_size = Vector2(320, 58)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(func() -> void: settings_menu_closed.emit())
	box.add_child(back)
	_focus_buttons[settings_panel] = back


func _add_setting_button(box: VBoxContainer, key: String, label: String) -> void:
	var button := _button(label + ": OFF", Color("#3a3a44"))
	button.custom_minimum_size = Vector2(320, 58)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_on_setting_pressed.bind(key))
	_setting_buttons[key] = button
	_setting_states[key] = false
	button.modulate = DIM
	box.add_child(button)


func _add_volume_slider(box: VBoxContainer, key: String, label: String, min_db: float, max_db: float, step: float) -> void:
	var container := HBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 12)
	
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.custom_minimum_size = Vector2(160, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	container.add_child(lbl)
	
	var slider := HSlider.new()
	slider.name = key
	slider.custom_minimum_size = Vector2(160, 40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = min_db
	slider.max_value = max_db
	slider.step = step
	slider.value = 0.0
	slider.value_changed.connect(func(v: float) -> void: _on_volume_changed(key, v))
	_setting_sliders[key] = slider
	container.add_child(slider)
	
	box.add_child(container)


func _on_volume_changed(key: String, value: float) -> void:
	volume_changed.emit(key, value)


func _on_setting_pressed(key: String) -> void:
	setting_changed.emit(key, not bool(_setting_states.get(key, false)))


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_token += 1
		var token := _reset_token
		_reset_button.text = "TAP AGAIN TO CONFIRM"
		_pop(_reset_button, 1.08, 0.25)

		get_tree().create_timer(RESET_CONFIRM_SECONDS).timeout.connect(
			func() -> void:
				if token == _reset_token:
					_disarm_reset()
		)
		return

	_disarm_reset()
	reset_game_requested.emit()


func _disarm_reset() -> void:
	_reset_armed = false
	_reset_token += 1
	if is_instance_valid(_reset_button):
		_reset_button.text = "RESET GAME DATA"


# ============================================================================
# SHOP
# ============================================================================

func _build_shop_menu() -> void:
	var screen := _create_screen(10)
	shop_panel = screen["panel"]
	_shop_center = screen["center"]
	var box: VBoxContainer = screen["box"]

	box.add_child(_label("ITEM SHOP", 46, Color.WHITE))

	# Currency bar: coins + gems.
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 14)
	_shop_coin_chip = _currency_chip(CurrencyIcon.Kind.COIN, COIN_COLOR)
	_shop_coins_label = _shop_coin_chip.get_meta("value_label")
	bar.add_child(_shop_coin_chip)
	_shop_gem_chip = _currency_chip(CurrencyIcon.Kind.GEM, GEM_COLOR)
	_shop_gem_label = _shop_gem_chip.get_meta("value_label")
	_gem_value_labels.append(_shop_gem_label)
	_gem_icons.append(_shop_gem_chip.get_meta("icon"))
	bar.add_child(_shop_gem_chip)
	box.add_child(bar)

	_shop_hint = _label("BUY ITEMS HERE, USE THEM IN A RUN WITH KEYS 1 / 2 / 3", 14, Color("#9da3b4"))
	box.add_child(_shop_hint)

	# Item cards.
	var row := HBoxContainer.new()
	row.name = "ShopRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var defs := _shop_item_defs()
	for i in range(defs.size()):
		row.add_child(_make_shop_card(i, defs[i]))
	box.add_child(row)

	# Permanent multiplier.
	_upgrade_row = _make_wide_card(Color("#ffcc58"))
	var upgrade_box := _upgrade_row.get_child(0) as HBoxContainer
	_upgrade_label = _label("PERMANENT MULTIPLIER  x1.0", 17, Color("#ffcc58"))
	_upgrade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_upgrade_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_box.add_child(_upgrade_label)
	_upgrade_button = _button("UPGRADE", Color("#8b5a12"))
	_upgrade_button.custom_minimum_size = Vector2(190, 44)
	_upgrade_button.add_theme_font_size_override("font_size", 17)
	_upgrade_button.pressed.connect(func() -> void: multiplier_upgrade_pressed.emit())
	upgrade_box.add_child(_upgrade_button)
	_add_coin_to_button(_upgrade_button)
	box.add_child(_upgrade_row)

	# Gems (rewarded ad placeholder).
	var gem_row := _make_wide_card(GEM_COLOR)
	var gem_box := gem_row.get_child(0) as HBoxContainer
	var gem_icon := CurrencyIcon.new()
	gem_icon.kind = CurrencyIcon.Kind.GEM
	gem_icon.custom_minimum_size = Vector2(46, 46)
	gem_box.add_child(gem_icon)
	_gem_icons.append(gem_icon)
	var gem_text := VBoxContainer.new()
	gem_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gem_title := _label("GEMS  -  SECOND CHANCE", 17, GEM_COLOR)
	gem_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gem_text.add_child(gem_title)
	var gem_desc := _label("1 GEM REVIVES YOU WHEN YOU DIE", 13, Color("#9da3b4"))
	gem_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gem_text.add_child(gem_desc)
	gem_box.add_child(gem_text)
	_shop_gem_button = _button("WATCH AD  +1 GEM", Color("#5b21b6"))
	_shop_gem_button.custom_minimum_size = Vector2(190, 44)
	_shop_gem_button.add_theme_font_size_override("font_size", 16)
	_shop_gem_button.pressed.connect(func() -> void: gem_ad_requested.emit("shop"))
	gem_box.add_child(_shop_gem_button)
	_add_shine(_shop_gem_button)
	box.add_child(gem_row)

	var back := _button("BACK", Color("#3a3a44"))
	back.custom_minimum_size = Vector2(320, 50)
	back.pressed.connect(func() -> void: shop_menu_closed.emit())
	box.add_child(back)
	_focus_buttons[shop_panel] = back

	_refresh_shop()


func _shop_item_defs() -> Array:
	return [
		{"title": "SHIELD", "desc": "ABSORBS ONE HIT", "color": EFFECT_COLORS["shield"], "icon": ICON_SHIELD},
		{"title": "DOUBLE SCORE", "desc": "2X SCORE FOR 8 SECONDS", "color": EFFECT_COLORS["score"], "icon": ICON_DOUBLE},
		{"title": "COIN MAGNET", "desc": "PULLS COINS FOR 8 SECONDS", "color": EFFECT_COLORS["magnet"], "icon": ICON_MAGNET},
	]


func _card_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151923")
	style.border_color = color.darkened(0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 12.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


## Full-width card with a horizontal box as its only child.
func _make_wide_card(color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	var style := _card_style(color)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)
	card.set_meta("style", style)
	card.set_meta("base_color", color)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)
	_center_pivot(card)
	return card


func _make_shop_card(index: int, def: Dictionary) -> Control:
	var color: Color = def["color"]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(196, 0)
	var style := _card_style(color)
	card.add_theme_stylebox_override("panel", style)
	card.set_meta("style", style)
	card.set_meta("base_color", color)
	_center_pivot(card)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)

	# Icon with a soft pulsing glow behind it. The icon floats up and down.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 76)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(holder)

	var glow := TextureRect.new()
	glow.texture = def["icon"]
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.size = Vector2(92, 92)
	glow.pivot_offset = Vector2(46, 46)
	glow.modulate = Color(color, 0.18)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)

	var icon := TextureRect.new()
	icon.texture = def["icon"]
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(64, 64)
	icon.pivot_offset = Vector2(32, 32)
	icon.position = Vector2(0.0, 8.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	holder.resized.connect(
		func() -> void:
			icon.position.x = (holder.size.x - icon.size.x) * 0.5
			glow.position = Vector2((holder.size.x - glow.size.x) * 0.5, -8.0)
	)

	col.add_child(_label(str(def["title"]), 18, color))

	var desc := _label(str(def["desc"]), 13, Color("#9da3b4"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(172, 34)
	col.add_child(desc)

	var owned := _label("OWNED: 0", 14, Color("#d6d9e4"))
	col.add_child(owned)

	var button := _button("BUY", color.darkened(0.45))
	button.custom_minimum_size = Vector2(172, 46)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(_on_shop_pressed.bind(index))
	col.add_child(button)
	_add_coin_to_button(button)
	_add_shine(button)

	_shop_cards.append(card)
	_shop_icons.append(icon)
	_shop_glows.append(glow)
	_shop_owned_labels.append(owned)
	_shop_buttons.append(button)
	_shop_colors.append(color)
	return card


## Small coin icon on the right edge of a price button.
func _add_coin_to_button(button: Button) -> void:
	var coin := CurrencyIcon.new()
	coin.kind = CurrencyIcon.Kind.COIN
	coin.animated = false
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_rect(coin, Vector4(1, 0.5, 1, 0.5), Vector4(-38, -12, -14, 12))
	button.add_child(coin)


## Light strip that sweeps across a button now and then (see _start_shop_tweens).
func _add_shine(button: Button) -> void:
	button.clip_contents = true
	var shine := ColorRect.new()
	shine.color = Color(1.0, 1.0, 1.0, 0.16)
	shine.size = Vector2(34.0, 120.0)
	shine.position = Vector2(-60.0, -8.0)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(shine)
	button.set_meta("shine", shine)
	_shine_buttons.append(button)


func _currency_chip(kind: int, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#10131c")
	style.border_color = color.darkened(0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 14.0
	style.content_margin_right = 18.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var icon := CurrencyIcon.new()
	icon.kind = kind as CurrencyIcon.Kind
	icon.custom_minimum_size = Vector2(28, 28)
	row.add_child(icon)

	var label := _label("0", 22, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(56, 0)
	row.add_child(label)

	panel.set_meta("value_label", label)
	panel.set_meta("icon", icon)
	_center_pivot(panel)
	return panel


# --- Shop animation --------------------------------------------------------

func _start_shop_tweens() -> void:
	_stop_shop_tweens()
	if _reduced_effects:
		return

	# Cards fly in one after another.
	for i in range(_shop_cards.size()):
		var card := _shop_cards[i]
		card.modulate.a = 0.0
		card.scale = Vector2(0.6, 0.6)
		card.rotation = -0.14 if i % 2 == 0 else 0.14
		var intro := create_tween().set_parallel(true)
		var delay := 0.12 + i * 0.09
		intro.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(delay)
		intro.tween_property(card, "scale", Vector2.ONE, 0.5).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		intro.tween_property(card, "rotation", 0.0, 0.5).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_shop_tweens.append(intro)

	for wide in [_upgrade_row]:
		if is_instance_valid(wide):
			wide.modulate.a = 0.0
			wide.scale = Vector2(0.9, 0.9)
			var wide_intro := create_tween().set_parallel(true)
			wide_intro.tween_property(wide, "modulate:a", 1.0, 0.25).set_delay(0.5)
			wide_intro.tween_property(wide, "scale", Vector2.ONE, 0.4).set_delay(0.5) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_shop_tweens.append(wide_intro)

	# Idle loops: icons float and sway, glows pulse, card borders breathe.
	for i in range(_shop_icons.size()):
		var icon := _shop_icons[i]
		var period := 1.0 + i * 0.17
		var bob := create_tween().set_loops()
		bob.tween_property(icon, "position:y", 0.0, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(icon, "position:y", 8.0, period).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shop_tweens.append(bob)

		var sway := create_tween().set_loops()
		icon.rotation = -0.07
		sway.tween_property(icon, "rotation", 0.07, period * 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway.tween_property(icon, "rotation", -0.07, period * 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shop_tweens.append(sway)

		var glow := _shop_glows[i]
		var pulse := create_tween().set_loops()
		pulse.tween_property(glow, "modulate:a", 0.36, 0.9 + i * 0.1).set_trans(Tween.TRANS_SINE)
		pulse.parallel().tween_property(glow, "scale", Vector2(1.18, 1.18), 0.9 + i * 0.1).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(glow, "modulate:a", 0.12, 0.9 + i * 0.1).set_trans(Tween.TRANS_SINE)
		pulse.parallel().tween_property(glow, "scale", Vector2.ONE, 0.9 + i * 0.1).set_trans(Tween.TRANS_SINE)
		_shop_tweens.append(pulse)

		var card := _shop_cards[i]
		var style: StyleBoxFlat = card.get_meta("style")
		var base: Color = card.get_meta("base_color")
		var border := create_tween().set_loops()
		border.tween_property(style, "border_color", base.lightened(0.15), 1.1)
		border.tween_property(style, "border_color", base.darkened(0.45), 1.1)
		_shop_tweens.append(border)

	# Shine sweeps (staggered so they do not all fire together).
	for i in range(_shine_buttons.size()):
		var button := _shine_buttons[i]
		var shine: ColorRect = button.get_meta("shine")
		var sweep := create_tween().set_loops()
		sweep.tween_interval(0.4 + i * 0.35)
		sweep.tween_method(
			func(t: float) -> void:
				shine.position.x = lerpf(-60.0, button.size.x + 30.0, t),
			0.0,
			1.0,
			0.6
		).set_trans(Tween.TRANS_SINE)
		sweep.tween_interval(2.0)
		_shop_tweens.append(sweep)


func _stop_shop_tweens() -> void:
	for t in _shop_tweens:
		_kill_tween(t)
	_shop_tweens.clear()
	for i in range(_shop_cards.size()):
		_shop_cards[i].modulate = Color.WHITE
		_shop_cards[i].scale = Vector2.ONE
		_shop_cards[i].rotation = 0.0
		_shop_icons[i].position.y = 8.0
		_shop_icons[i].rotation = 0.0
		_shop_glows[i].modulate.a = 0.18
		_shop_glows[i].scale = Vector2.ONE
		var style: StyleBoxFlat = _shop_cards[i].get_meta("style")
		style.border_color = (_shop_cards[i].get_meta("base_color") as Color).darkened(0.45)
	if is_instance_valid(_upgrade_row):
		_upgrade_row.modulate = Color.WHITE
		_upgrade_row.scale = Vector2.ONE
	for button in _shine_buttons:
		var shine: ColorRect = button.get_meta("shine")
		shine.position.x = -60.0


## Centre of a control in UI coordinates (accounts for the screen's scale).
func _control_center(c: Control) -> Vector2:
	return c.get_global_transform() * (c.size * 0.5)


func _burst_at(pos: Vector2, color: Color, amount := 24) -> void:
	if _reduced_effects:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 340.0
	p.gravity = Vector2(0.0, 560.0)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.5
	p.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func _shake_control(c: Control, flash := true) -> void:
	if not is_instance_valid(c):
		return
	_kill_tween(c.get_meta("shake_tween", null))
	c.rotation = 0.0
	if flash:
		c.modulate = Color(1.6, 0.7, 0.7)
	var t := create_tween()
	if not _reduced_effects:
		for k in range(5):
			var angle := 0.045 * (1.0 - float(k) / 5.0) * (1.0 if k % 2 == 0 else -1.0)
			t.tween_property(c, "rotation", angle, 0.045)
	t.tween_property(c, "rotation", 0.0, 0.05)
	if flash:
		t.parallel().tween_property(c, "modulate", Color.WHITE, 0.3)
	c.set_meta("shake_tween", t)


func _flash_hint(text: String, color: Color) -> void:
	if not is_instance_valid(_shop_hint):
		return
	_shop_hint_token += 1
	var token := _shop_hint_token
	var original := "BUY ITEMS HERE, USE THEM IN A RUN WITH KEYS 1 / 2 / 3"
	_shop_hint.text = text
	_shop_hint.add_theme_color_override("font_color", color)
	_pop(_shop_hint, 1.2, 0.25, 0.0)
	get_tree().create_timer(1.6).timeout.connect(
		func() -> void:
			if token == _shop_hint_token and is_instance_valid(_shop_hint):
				_shop_hint.text = original
				_shop_hint.add_theme_color_override("font_color", Color("#9da3b4"))
	)


## Called when a purchase succeeds: card punch, flash, icon pop, sparks, "+1".
func play_shop_purchase(item: int) -> void:
	if item < 0 or item >= _shop_cards.size() or not shop_panel.visible:
		return
	var card := _shop_cards[item]
	var color := _shop_colors[item]
	var center := _control_center(card)
	_pop(card, 1.12, 0.4, 0.0)
	_pop(_shop_icons[item], 1.5, 0.5, 0.0)
	_pop(_shop_owned_labels[item], 1.6, 0.4, 0.0)
	_pop(_shop_coin_chip, 1.2, 0.3, 0.0)
	if not _reduced_effects:
		card.modulate = Color(1.8, 1.8, 1.5)
		create_tween().tween_property(card, "modulate", Color.WHITE, 0.4)
	_burst_at(center, color)
	show_pickup("+1", color, center)
	_flash_hint("PURCHASED!", color)


func play_upgrade_effect() -> void:
	if not shop_panel.visible:
		return
	var center := _control_center(_upgrade_row)
	_pop(_upgrade_row, 1.06, 0.4, 0.0)
	_pop(_upgrade_label, 1.2, 0.4, 0.0)
	if not _reduced_effects:
		_upgrade_row.modulate = Color(1.7, 1.6, 1.2)
		create_tween().tween_property(_upgrade_row, "modulate", Color.WHITE, 0.4)
	_burst_at(center, Color("#ffcc58"))
	show_pickup("UPGRADED!", Color("#ffcc58"), center)


## Not enough coins: shake the card and say so.
func shop_denied(item: int) -> void:
	var target: Control = null
	if item >= 0 and item < _shop_cards.size():
		target = _shop_cards[item]
	elif item == 3:
		target = _upgrade_row
	if target == null:
		return
	_shake_control(target)
	_flash_hint("NOT ENOUGH COINS", Color("#ff6b7a"))


func skin_denied(skin: int) -> void:
	if skin >= 0 and skin < _skin_buttons.size():
		_shake_control(_skin_buttons[skin], false)


func play_skin_effect(skin: int, unlocked_now: bool) -> void:
	if skin < 0 or skin >= _skin_textures.size() or not skin_panel.visible:
		return
	var tex := _skin_textures[skin]
	_pop(tex, 1.3, 0.4, 0.0)
	if unlocked_now:
		var center := _control_center(tex)
		_burst_at(center, Color("#ffd166"), 30)
		show_pickup("UNLOCKED!", Color("#ffd166"), center)


func _on_shop_pressed(item: int) -> void:
	shop_action.emit(item, "buy")


# ============================================================================
# SKIN MENU
# ============================================================================

func _build_skin_menu() -> void:
	var screen := _create_screen()
	skin_panel = screen["panel"]
	_skin_center = screen["center"]
	var box: VBoxContainer = screen["box"]

	box.add_child(_label("SKIN SHOP", 48, Color.WHITE))
	box.add_child(_label("BUY AND EQUIP IMAGE-BASED SKINS", 18, Color("#b8b8c4")))
	_skin_coins_label = _label("YOUR COINS: 0", 18, COIN_COLOR)
	box.add_child(_skin_coins_label)

	_skin_scroll = ScrollContainer.new()
	_skin_scroll.name = "SkinScroll"
	_skin_scroll.custom_minimum_size = Vector2(620, 430)
	_skin_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skin_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_skin_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_skin_scroll.follow_focus = true
	box.add_child(_skin_scroll)

	var grid := GridContainer.new()
	grid.name = "SkinGrid"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_skin_scroll.add_child(grid)

	_skin_costs.clear()
	_skin_names.clear()

	for i in range(SkinCatalog.count()):
		var skin_data = SkinCatalog.get_skin(i)
		_skin_costs.append(int(skin_data.cost))
		_skin_names.append(str(skin_data.name))

		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(SKIN_CARD_SIZE, SKIN_CARD_SIZE + 46)
		card.add_theme_constant_override("separation", 5)

		var skin_texture := TextureRect.new()
		skin_texture.custom_minimum_size = Vector2(SKIN_CARD_SIZE, SKIN_CARD_SIZE)
		skin_texture.texture = SkinCatalog.get_texture(i)
		skin_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		skin_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.add_child(skin_texture)
		_skin_textures.append(skin_texture)

		var skin_button := _button(str(skin_data.name), Color("#292d3a"))
		skin_button.custom_minimum_size = Vector2(SKIN_CARD_SIZE, 40)
		skin_button.add_theme_font_size_override("font_size", 16)
		skin_button.add_theme_color_override("font_color", Color.WHITE)
		skin_button.add_theme_color_override("font_hover_color", Color.WHITE)
		skin_button.pressed.connect(_on_skin_pressed.bind(i))
		card.add_child(skin_button)

		grid.add_child(card)
		_skin_buttons.append(skin_button)

	var back := _button("BACK", Color("#3a3a44"))
	back.custom_minimum_size = Vector2(320, 52)
	back.pressed.connect(func() -> void: skin_menu_closed.emit())
	box.add_child(back)
	_focus_buttons[skin_panel] = back


func _on_skin_pressed(index: int) -> void:
	skin_selected.emit(index)


# ============================================================================
# GAME OVER
# ============================================================================

func _build_game_over() -> void:
	var screen := _create_screen(16)
	go_panel = screen["panel"]
	_go_center = screen["center"]
	var box: VBoxContainer = screen["box"]

	box.add_child(_label("GAME OVER", 62, Color("#ff5b5b")))
	box.add_child(_label("THE ARENA WINS THIS ROUND", 22, Color("#f7c85b")))

	_new_best_label = _label("NEW BEST!", 30, Color("#ffd166"))
	_new_best_label.visible = false
	box.add_child(_new_best_label)
	_center_pivot(_new_best_label)

	go_score = _label("SCORE: 0", 42, Color.WHITE)
	box.add_child(go_score)
	_center_pivot(go_score)

	go_best = _label("BEST: 0", 30, Color("#cfcfd8"))
	go_best.z_index = 30
	box.add_child(go_best)

	_go_gems_label = _label("GEMS: 0", 20, GEM_COLOR)
	box.add_child(_go_gems_label)

	_try_again_button = _button("TRY AGAIN", ACCENT)
	_try_again_button.pressed.connect(func() -> void: try_again_pressed.emit())
	box.add_child(_try_again_button)
	_focus_buttons[go_panel] = _try_again_button

	_go_ad_button = _button("WATCH AD  +1 GEM", Color("#5b21b6"))
	_go_ad_button.custom_minimum_size = Vector2(320, 50)
	_go_ad_button.add_theme_font_size_override("font_size", 18)
	_go_ad_button.pressed.connect(func() -> void: gem_ad_requested.emit("gameover"))
	box.add_child(_go_ad_button)
	_add_shine(_go_ad_button)

	var menu := _button("MENU", Color("#3a3a44"))
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	box.add_child(menu)


# ============================================================================
# PAUSE MENU
# ============================================================================

func _build_pause_menu() -> void:
	var screen := _create_screen(22, OVERLAY_BG)
	pause_panel = screen["panel"]
	_pause_center = screen["center"]
	var box: VBoxContainer = screen["box"]

	box.add_child(_label("PAUSED", 58, Color.WHITE))

	var resume := _button("RESUME", ACCENT)
	resume.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(resume)
	_focus_buttons[pause_panel] = resume

	var settings := _button("SETTINGS", Color("#3a3a44"))
	settings.pressed.connect(func() -> void: pause_settings_requested.emit())
	box.add_child(settings)

	var menu := _button("QUIT TO MENU", Color("#6d2020"))
	menu.pressed.connect(func() -> void: pause_menu_requested.emit())
	box.add_child(menu)


# ============================================================================
# REVIVE PROMPT (spend a gem to continue after dying)
# ============================================================================

func _build_revive_menu() -> void:
	var screen := _create_screen(12, Color(0.02, 0.03, 0.08, 0.74))
	revive_panel = screen["panel"]
	_revive_center = screen["center"]
	var box: VBoxContainer = screen["box"]

	box.add_child(_label("SECOND CHANCE", 18, GEM_COLOR))
	box.add_child(_label("REVIVE?", 58, Color.WHITE))

	# Countdown ring with a gem in the middle.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(190, 190)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)

	_revive_ring = CountdownRing.new()
	_full_rect(_revive_ring)
	_revive_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_revive_ring)

	var ring_gem := CurrencyIcon.new()
	ring_gem.kind = CurrencyIcon.Kind.GEM
	_set_rect(ring_gem, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-34, -64, 34, 4))
	holder.add_child(ring_gem)
	_gem_icons.append(ring_gem)

	_revive_number = _label("6", 44, Color.WHITE)
	_set_rect(_revive_number, Vector4(0, 0.5, 1, 0.5), Vector4(0, 4, 0, 60))
	holder.add_child(_revive_number)
	_center_pivot(_revive_number)

	_revive_subtitle = _label("SPEND 1 GEM TO KEEP YOUR RUN GOING", 18, Color("#b8b8c4"))
	box.add_child(_revive_subtitle)

	var gems_chip := _currency_chip(CurrencyIcon.Kind.GEM, GEM_COLOR)
	gems_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_revive_gems_label = gems_chip.get_meta("value_label")
	_gem_icons.append(gems_chip.get_meta("icon"))
	box.add_child(gems_chip)

	_revive_button = _button("REVIVE  -1 GEM", Color("#0e7490"))
	_revive_button.custom_minimum_size = Vector2(360, 68)
	_revive_button.add_theme_font_size_override("font_size", 26)
	_revive_button.set_meta("no_hover_scale", true)
	_revive_button.pressed.connect(func() -> void: revive_pressed.emit())
	box.add_child(_revive_button)
	_focus_buttons[revive_panel] = _revive_button

	_revive_ad_button = _button("OR WATCH AN AD: FREE REVIVE", Color("#5b21b6"))
	_revive_ad_button.custom_minimum_size = Vector2(360, 58)
	_revive_ad_button.add_theme_font_size_override("font_size", 18)
	_revive_ad_button.pressed.connect(func() -> void: revive_ad_pressed.emit())
	box.add_child(_revive_ad_button)

	_revive_skip_button = _button("NO THANKS", Color("#3a3a44"))
	_revive_skip_button.custom_minimum_size = Vector2(240, 44)
	_revive_skip_button.add_theme_font_size_override("font_size", 16)
	_revive_skip_button.pressed.connect(func() -> void: revive_declined.emit())
	box.add_child(_revive_skip_button)

	_revive_info = _label("", 14, Color("#777d91"))
	box.add_child(_revive_info)


# ============================================================================
# AD PLACEHOLDER (no real ads: this is where an ad SDK would draw its screen)
# ============================================================================

func _build_ad_placeholder() -> void:
	_ad_panel = _make_panel(Color(0.02, 0.02, 0.05, 0.94))
	add_child(_ad_panel)

	var center := CenterContainer.new()
	_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ad_panel.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	_ad_title = _label("AD PLACEHOLDER", 44, Color.WHITE)
	box.add_child(_ad_title)
	box.add_child(_label("A REWARDED AD WOULD PLAY HERE", 18, Color("#9da3b4")))

	var track := ColorRect.new()
	track.color = Color("#303443")
	track.custom_minimum_size = Vector2(320, 10)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(track)

	_ad_bar = ColorRect.new()
	_ad_bar.color = Color("#a78bfa")
	_ad_bar.size = Vector2(0.0, 10.0)
	track.add_child(_ad_bar)

	var reward := HBoxContainer.new()
	reward.alignment = BoxContainer.ALIGNMENT_CENTER
	reward.add_theme_constant_override("separation", 8)
	var reward_icon := CurrencyIcon.new()
	reward_icon.kind = CurrencyIcon.Kind.GEM
	reward_icon.custom_minimum_size = Vector2(30, 30)
	reward.add_child(reward_icon)
	reward.add_child(_label("REWARD: +1 GEM", 22, GEM_COLOR))
	box.add_child(reward)


# ============================================================================
# FLASH + POWERUP POPUP
# ============================================================================

func _build_overlays() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(0.9, 0.05, 0.05, 0.0)
	_full_rect(_flash)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

	_powerup_label = _label("POWERUP", 28, Color("#ffcc58"))
	_set_rect(_powerup_label, Vector4(0.5, 0, 0.5, 0), Vector4(-260, 104, 260, 146))
	_powerup_label.modulate.a = 0.0
	_powerup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_powerup_label)
	_center_pivot(_powerup_label)


# ============================================================================
# LOADING SCREEN
# ============================================================================

func _build_loading_screen() -> void:
	_loading_panel = Control.new()
	_full_rect(_loading_panel)
	_loading_panel.visible = false
	_loading_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	_full_rect(backdrop)
	backdrop.color = Color("#11131d")
	_loading_panel.add_child(backdrop)

	_loading_label = _label("LOADING RUN", 34, Color.WHITE)
	_set_rect(_loading_label, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-220, -30, 220, 18))
	_loading_panel.add_child(_loading_label)

	var track := ColorRect.new()
	track.color = Color("#303443")
	_set_rect(track, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-210, 34, 210, 40))
	_loading_panel.add_child(track)

	_loading_bar = ColorRect.new()
	_loading_bar.position = Vector2.ZERO
	_loading_bar.size = Vector2(0.0, 6.0)
	_loading_bar.color = Color("#f59e0b")
	track.add_child(_loading_bar)

	add_child(_loading_panel)


# ============================================================================
# MENU TWEENS
# ============================================================================

func _start_menu_tweens() -> void:
	_stop_menu_tweens()

	# Title: breathing pulse + gentle sway
	if is_instance_valid(_menu_title):
		_title_tween = _loop_pulse(_menu_title, 1.04, 1.0)

		_menu_title.rotation = -0.012
		_sway_tween = create_tween().set_loops()
		_sway_tween.tween_property(_menu_title, "rotation", 0.012, 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_sway_tween.tween_property(_menu_title, "rotation", -0.012, 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Play button: pulse
	if is_instance_valid(_play_button):
		_play_tween = _loop_pulse(_play_button, 1.04, 0.75)

	if _reduced_effects:
		return

	# Shine sweep across PLAY
	if is_instance_valid(_play_button) and is_instance_valid(_shine):
		_shine_tween = create_tween().set_loops()
		_shine_tween.tween_method(
			func(t: float) -> void:
				_shine.position.x = lerpf(-60.0, _play_button.size.x + 20.0, t),
			0.0,
			1.0,
			0.7
		).set_trans(Tween.TRANS_SINE)
		_shine_tween.tween_interval(1.8)

	# "THE RED" glitches every couple of seconds
	if is_instance_valid(_red_title):
		_glitch_tween = create_tween().set_loops()
		_glitch_tween.tween_interval(2.4)
		_glitch_tween.tween_property(_red_title, "modulate", Color(1.9, 0.6, 0.6, 1.0), 0.05)
		_glitch_tween.tween_property(_red_title, "rotation", 0.04, 0.04)
		_glitch_tween.tween_property(_red_title, "modulate:a", 0.35, 0.04)
		_glitch_tween.tween_property(_red_title, "rotation", -0.035, 0.04)
		_glitch_tween.tween_property(_red_title, "modulate", Color.WHITE, 0.06)
		_glitch_tween.tween_property(_red_title, "rotation", 0.0, 0.06)


func _stop_menu_tweens() -> void:
	for t in [_title_tween, _sway_tween, _play_tween, _shine_tween, _glitch_tween]:
		_kill_tween(t)

	if is_instance_valid(_menu_title):
		_menu_title.scale = Vector2.ONE
		_menu_title.rotation = 0.0
	if is_instance_valid(_play_button):
		_play_button.scale = Vector2.ONE
	if is_instance_valid(_red_title):
		_red_title.modulate = Color.WHITE
		_red_title.rotation = 0.0
	if is_instance_valid(_shine):
		_shine.position.x = -60.0


func _loop_pulse(node: Control, amount: float, half_time: float) -> Tween:
	node.scale = Vector2.ONE
	var tween := create_tween().set_loops()
	tween.tween_property(node, "scale", Vector2.ONE * amount, half_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, half_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


# ============================================================================
# SCREEN ANIMATION
# ============================================================================

func _center_scale(center: CenterContainer) -> float:
	return _settings_scale if center == _settings_center else _scale_factor


func _animate_center(center: CenterContainer) -> void:
	if not is_instance_valid(center):
		return

	_kill_tween(_center_tweens.get(center))

	# Always animate towards the stored target (never read the current scale,
	# which may be mid-tween). Position is not tweened: the container owns it.
	var target := Vector2.ONE * _center_scale(center)

	if _reduced_effects:
		center.scale = target
		center.modulate.a = 1.0
	else:
		center.scale = target * 0.85
		center.modulate.a = 0.0

		var tween := create_tween().set_parallel(true)
		tween.tween_property(center, "scale", target, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(center, "modulate:a", 1.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_center_tweens[center] = tween

	_stagger_children(center.get_child(0) as Control)


## Elements of a screen pop in one after another.
func _stagger_children(box: Control) -> void:
	if box == null:
		return

	_kill_tween(_stagger_tweens.get(box))

	var children := box.get_children()

	if _reduced_effects:
		for child in children:
			if child is Control:
				(child as Control).modulate.a = 1.0
		return

	var tween := create_tween().set_parallel(true)
	var box_min := box.get_combined_minimum_size()
	var index := 0

	for child in children:
		var c := child as Control
		if c == null or not c.visible:
			continue

		var delay := index * STAGGER_STEP
		c.modulate.a = 0.0
		tween.tween_property(c, "modulate:a", 1.0, 0.22).set_delay(delay)

		# Elements that already pulse on their own only fade in.
		if not _is_pulse_node(c):
			if not c is Button:
				c.pivot_offset = c.size * 0.5
				if c.size.x <= 0.0:
					c.pivot_offset = Vector2(box_min.x * 0.5, c.get_combined_minimum_size().y * 0.5)
			c.scale = Vector2(0.8, 0.8)
			tween.tween_property(c, "scale", Vector2.ONE, 0.34) \
				.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		index += 1

	_stagger_tweens[box] = tween


func _is_pulse_node(c: Control) -> bool:
	return c == _menu_title or c == _play_button or c == _new_best_label or c == _revive_button


# ============================================================================
# POP / NUMBERS / BUTTON FEEDBACK
# ============================================================================

## Quick scale punch that settles back to normal size.
func _pop(node: Control, amount := 1.25, duration := 0.2, min_gap := 0.15) -> void:
	if _reduced_effects or not is_instance_valid(node):
		return

	var now := Time.get_ticks_msec()
	if now - int(node.get_meta("last_pop", -10000)) < int(min_gap * 1000.0):
		return
	node.set_meta("last_pop", now)

	var old: Tween = _pop_tweens.get(node)
	_kill_tween(old)

	node.scale = Vector2.ONE * amount
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tweens[node] = tween


## Counts a label's number up/down instead of snapping.
func _tween_number(label: Label, to_value: int, from_override := -1) -> void:
	if not is_instance_valid(label):
		return

	var from_value := int(label.get_meta("shown", to_value))
	if from_override >= 0:
		from_value = from_override
	label.set_meta("shown", to_value)

	var old: Tween = null
	if label.has_meta("count_tween"):
		old = label.get_meta("count_tween")
	_kill_tween(old)

	if _reduced_effects or from_value == to_value or not label.is_visible_in_tree():
		label.text = str(to_value)
		return

	var tween := create_tween()
	tween.tween_method(
		func(v: float) -> void:
			label.text = str(int(round(v))),
		float(from_value),
		float(to_value),
		0.7
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _pop(label, 1.2, 0.25))
	label.set_meta("count_tween", tween)


func _on_button_hover(b: Button, hovered: bool) -> void:
	if b.disabled or b.has_meta("no_hover_scale"):
		return
	_tween_button_scale(b, HOVER_SCALE if hovered else 1.0, 0.14)


func _on_button_down(b: Button) -> void:
	if b.disabled or b.has_meta("no_hover_scale"):
		return
	_tween_button_scale(b, PRESS_SCALE, 0.06)


func _on_button_up(b: Button) -> void:
	if b.disabled or b.has_meta("no_hover_scale"):
		return
	_tween_button_scale(b, HOVER_SCALE if b.is_hovered() else 1.0, 0.16)


func _tween_button_scale(b: Button, target: float, duration: float) -> void:
	var old: Tween = null

	if b.has_meta("scale_tween"):
		old = b.get_meta("scale_tween")

	_kill_tween(old)

	if _reduced_effects:
		b.scale = Vector2.ONE
		return

	var tween := b.create_tween()
	tween.tween_property(b, "scale", Vector2.ONE * target, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.set_meta("scale_tween", tween)
	
# ============================================================================
# PLAY TRANSITION
# ============================================================================

func play_transition() -> void:
	_background.kick()

	if _reduced_effects:
		return

	var flash := ColorRect.new()
	_full_rect(flash)
	flash.color = Color(0.9, 0.05, 0.12, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", 0.4, 0.12)
	tween.tween_property(flash, "color:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


# ============================================================================
# SCREEN / PANEL FACTORIES
# ============================================================================

func _make_panel(overlay_color := MENU_OVERLAY) -> Control:
	var p := Control.new()
	_full_rect(p)
	p.mouse_filter = Control.MOUSE_FILTER_STOP # still blocks clicks when the overlay is hidden
	p.visible = false

	var overlay := ColorRect.new()
	_full_rect(overlay)
	overlay.color = overlay_color
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	p.add_child(overlay)
	p.set_meta("overlay", overlay)

	return p


## Creates panel -> CenterContainer -> VBoxContainer and returns all three.
func _create_screen(separation := 22, overlay_color := MENU_OVERLAY) -> Dictionary:
	var panel := _make_panel(overlay_color)
	add_child(panel)

	var center := CenterContainer.new()
	_full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", separation)
	center.add_child(box)

	return {"panel": panel, "center": center, "box": box}


# ============================================================================
# RESPONSIVE LAYOUT
# ============================================================================

func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	_scale_factor = clampf(minf(viewport_size.x / 900.0, viewport_size.y / 620.0), 0.5, 1.0)
	_settings_scale = clampf(minf(viewport_size.x / 900.0, viewport_size.y / 700.0), 0.55, 1.0)

	for center in [_menu_center, _skin_center, _go_center, _shop_center, _pause_center, _revive_center]:
		if is_instance_valid(center):
			center.pivot_offset = viewport_size * 0.5
			center.scale = Vector2.ONE * _scale_factor

	if is_instance_valid(_settings_center):
		_settings_center.pivot_offset = viewport_size * 0.5
		_settings_center.scale = Vector2.ONE * _settings_scale

	if is_instance_valid(_settings_scroll):
		var h := clampf(viewport_size.y / _settings_scale - 220.0, 160.0, 420.0)
		_settings_scroll.custom_minimum_size = Vector2(
			clampf(viewport_size.x / _settings_scale - 32.0, 240.0, 360.0),
			h
		)

	if is_instance_valid(_skin_scroll):
		var skin_h := clampf(viewport_size.y / _scale_factor - 200.0, 150.0, 430.0)
		_skin_scroll.custom_minimum_size = Vector2(
			clampf(viewport_size.x / _scale_factor - 32.0, 280.0, 620.0),
			skin_h
		)

	# ------------------------------------------------------------------------
	# Responsive gameplay HUD
	# ------------------------------------------------------------------------
	if is_instance_valid(_hud_bar):
		var compact := viewport_size.x < 600.0 or viewport_size.y < 500.0
		var bar_h := 76.0 if compact else 92.0
		_set_rect(_hud_bar, Vector4(0, 0, 1, 0), Vector4(0, 0, 0, bar_h))

		if is_instance_valid(_hud_bar_accent):
			_set_rect(_hud_bar_accent, Vector4(0, 1, 1, 1), Vector4(0, -4, 0, 0))

		# Left score stack.
		var left_w := clampf(viewport_size.x * 0.28, 92.0, 190.0)
		var left_x := 12.0 if compact else 24.0
		_score_label.position = Vector2(left_x, 10.0 if compact else 18.0)
		_score_label.size = Vector2(left_w, 28.0)
		_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_score_label.add_theme_font_size_override("font_size", 19 if compact else 24)
		_score_label.pivot_offset = _score_label.size * 0.5

		_multiplier_label.position = Vector2(left_x, 35.0 if compact else 46.0)
		_multiplier_label.size = Vector2(72.0, 30.0)
		_multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_multiplier_label.add_theme_font_size_override("font_size", 23 if compact else 30)
		_multiplier_label.pivot_offset = _multiplier_label.size * 0.5

		_coins_label.position = Vector2(left_x + (78.0 if compact else 86.0), 40.0 if compact else 54.0)
		_coins_label.size = Vector2(maxf(80.0, left_w - 65.0), 24.0)
		_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_coins_label.add_theme_font_size_override("font_size", 16 if compact else 20)
		_coins_label.pivot_offset = _coins_label.size * 0.5

		# Timer occupies a bounded center region. It never crosses the score or
		# best-score zones, even at 320px-wide resolutions.
		var timer_w := clampf(viewport_size.x * (0.48 if compact else 0.38), 160.0, 300.0)
		var timer_h := 48.0 if compact else 56.0
		var timer_font := 30 if compact else 48
		_set_rect(hud_timer, Vector4(0.5, 0, 0.5, 0), Vector4(-timer_w * 0.5, 7.0, timer_w * 0.5, 7.0 + timer_h))
		hud_timer.add_theme_font_size_override("font_size", timer_font)
		hud_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hud_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hud_timer.pivot_offset = hud_timer.size * 0.5

		# Best score stays on the right with a fixed safe width.
		var best_w := clampf(viewport_size.x * 0.25, 92.0, 190.0)
		var best_x := viewport_size.x - best_w - (12.0 if compact else 24.0)
		_set_rect(hud_best, Vector4(0, 0, 0, 0), Vector4(best_x, 12.0 if compact else 20.0, viewport_size.x - (12.0 if compact else 24.0), 42.0 if compact else 58.0))
		hud_best.add_theme_font_size_override("font_size", 19 if compact else 30)
		hud_best.pivot_offset = hud_best.size * 0.5

		# Gem counter under the best score.
		if is_instance_valid(_gem_chip):
			var chip_margin := 12.0 if compact else 24.0
			var chip_y := 44.0 if compact else 62.0
			_set_rect(_gem_chip, Vector4(0, 0, 0, 0), Vector4(viewport_size.x - 130.0 - chip_margin, chip_y, viewport_size.x - chip_margin, chip_y + 28.0))
			_gem_label.add_theme_font_size_override("font_size", 20 if compact else 26)
			_gem_chip.pivot_offset = _gem_chip.size * 0.5

		# Stage + powerup panels. Both live on the LEFT so they do not fight
		# with the timer/best-score area. Stage is intentionally taller.
		var panel_w := clampf(viewport_size.x * 0.30, 190.0, 272.0)
		if compact:
			panel_w = minf(viewport_size.x - 24.0, 250.0)
			# Compact: stage starts below the pause button; powerups stay on the right.
			_set_rect(_stage_background, Vector4(0, 0, 0, 0), Vector4(12.0, 140.0, 12.0 + panel_w, 290.0))
			var effects_w := minf(viewport_size.x - 24.0, 250.0)
			_set_rect(_effects_bg, Vector4(1, 0, 1, 0), Vector4(-12.0 - effects_w, 140.0, -12.0, 262.0))
		else:
			# Desktop: stage is lower on the left, safely below the pause button.
			_set_rect(_stage_background, Vector4(0, 0, 0, 0), Vector4(24.0, 170.0, 24.0 + panel_w, 350.0))
			# Active powerups remain permanently positioned on the right.
			_set_rect(_effects_bg, Vector4(1, 0, 1, 0), Vector4(-18.0 - panel_w, 108.0, -18.0, 230.0))

		# Pause button moves under the score stack on compact screens.
		if is_instance_valid(_pause_button):
			if compact:
				_pause_button.position = Vector2(12.0, 86.0)
				_pause_button.custom_minimum_size = Vector2(104.0, 40.0)
				_pause_button.add_theme_font_size_override("font_size", 15)
			else:
				_pause_button.position = Vector2(24.0, 104.0)
				_pause_button.custom_minimum_size = Vector2(132.0, 48.0)
				_pause_button.add_theme_font_size_override("font_size", 18)

		# Bottom item bar. When touch controls are active, reserve a separate
		# left joystick zone so the two controls cannot overlap.
		var bottom_margin := 14.0
		var item_h := 52.0
		var joystick_zone := 0.0
		if _touch_controls:
			joystick_zone = minf(154.0, viewport_size.x * 0.44)

		if _touch_controls and viewport_size.x < 600.0:
			var item_w := clampf(viewport_size.x - joystick_zone - 30.0, 150.0, 300.0)
			var item_left := joystick_zone + 12.0
			_set_rect(_item_bar, Vector4(0, 1, 0, 1), Vector4(item_left, -bottom_margin - item_h, item_left + item_w, -bottom_margin))
			_item_bar.add_theme_constant_override("separation", 4)
			for b in _item_buttons:
				b.add_theme_font_size_override("font_size", 12)
				b.custom_minimum_size.y = item_h
		else:
			var bar_w := minf(540.0, viewport_size.x - 24.0)
			_set_rect(_item_bar, Vector4(0.5, 1, 0.5, 1), Vector4(-bar_w * 0.5, -bottom_margin - item_h, bar_w * 0.5, -bottom_margin))
			_item_bar.add_theme_constant_override("separation", 8)
			for b in _item_buttons:
				b.add_theme_font_size_override("font_size", 16)
				b.custom_minimum_size.y = item_h

		# Responsive joystick: smaller on narrow/short screens and always in its
		# own corner, above the item bar's reserved zone.
		if is_instance_valid(_touch_joystick):
			var joy_size := clampf(minf(viewport_size.x * 0.28, viewport_size.y * 0.28), 126.0, 180.0)
			if compact:
				joy_size = clampf(minf(viewport_size.x * 0.40, viewport_size.y * 0.28), 116.0, 146.0)
			_set_rect(_touch_joystick, Vector4(0, 1, 0, 1), Vector4(12.0, -joy_size - 14.0, 12.0 + joy_size, -14.0))

	# Loading bar must also respect narrow screens.
	if is_instance_valid(_loading_bar) and is_instance_valid(_loading_panel):
		var load_width := minf(420.0, maxf(180.0, viewport_size.x - 48.0))
		if _loading_panel.visible:
			_loading_bar.custom_minimum_size.x = load_width


# ============================================================================
# TOUCH JOYSTICK
# ============================================================================

func _build_touch_joystick() -> void:
	_touch_joystick = TouchJoystick.new()
	_touch_joystick.name = "TouchJoystick"
	_set_rect(_touch_joystick, Vector4(0, 1, 0, 1), Vector4(28, -208, 208, -28))
	_touch_joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_joystick.visible = false
	_touch_joystick.vector_changed.connect(
		func(value: Vector2) -> void:
			touch_vector_changed.emit(value)
	)
	add_child(_touch_joystick)


# ============================================================================
# LAYOUT HELPERS
# ============================================================================

func _full_rect(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## anchors = (left, top, right, bottom), offsets = (left, top, right, bottom)
func _set_rect(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w


## Keeps a control's pivot at its center so scale animations grow from the middle.
func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.resized.connect(
		func() -> void:
			c.pivot_offset = c.size * 0.5
	)


func _kill_tween(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()


# ============================================================================
# LABEL / BUTTON HELPERS
# ============================================================================

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(320, 64)

	var styles := _get_button_styles(bg)
	b.add_theme_stylebox_override("normal", styles["normal"])
	b.add_theme_stylebox_override("hover", styles["hover"])
	b.add_theme_stylebox_override("pressed", styles["pressed"])
	b.add_theme_stylebox_override("hover_pressed", styles["pressed"])
	b.add_theme_stylebox_override("disabled", styles["disabled"])
	b.add_theme_stylebox_override("focus", styles["focus"])

	b.add_theme_color_override("font_color", Color("#f5f5f7"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("#eeeeee"))
	b.add_theme_color_override("font_disabled_color", Color("#8a8a94"))

	# Hover grow / press squash, always from the button's center.
	b.resized.connect(
		func() -> void:
			b.pivot_offset = b.size * 0.5
	)
	b.mouse_entered.connect(_on_button_hover.bind(b, true))
	b.mouse_exited.connect(_on_button_hover.bind(b, false))
	b.button_down.connect(_on_button_down.bind(b))
	b.button_up.connect(_on_button_up.bind(b))

	return b


func _get_button_styles(bg: Color) -> Dictionary:
	if _style_cache.has(bg):
		return _style_cache[bg]

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 22.0
	normal.content_margin_right = 22.0
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	normal.set_border_width_all(1)
	normal.border_color = bg.lightened(0.28)
	normal.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	normal.shadow_size = 10
	normal.shadow_offset = Vector2(0.0, 5.0)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.14)
	hover.border_color = bg.lightened(0.42)
	hover.shadow_size = 14
	hover.shadow_offset = Vector2(0.0, 7.0)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg.darkened(0.20)
	pressed.shadow_size = 4
	pressed.shadow_offset = Vector2(0.0, 2.0)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = bg.darkened(0.5)
	disabled.border_color = bg.darkened(0.2)
	disabled.shadow_size = 2
	disabled.shadow_offset = Vector2(0.0, 1.0)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color("#ffd166")
	focus.set_border_width_all(2)

	if _lite_shadows:
		for s in [normal, hover, pressed, disabled, focus]:
			s.shadow_size = 0

	var styles := {
		"normal": normal,
		"hover": hover,
		"pressed": pressed,
		"disabled": disabled,
		"focus": focus,
	}
	_style_cache[bg] = styles
	return styles


# ============================================================================
# TIME FORMAT
# ============================================================================

func _fmt_time(v: int) -> String:
	var m := floori(v / 60.0)
	var s := v % 60
	return "%02d:%02d" % [m, s]
