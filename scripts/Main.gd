extends Node2D

## Game coordinator: owns the game state machine, survival timer/score, gems,
## revive flow and persistence. DangerManager, UI, FX and ads are driven from here.

## MENU -> PLAYING -> DYING (short slow-motion) -> REVIVE (gem prompt) or GAME_OVER
enum State { MENU, PLAYING, DYING, REVIVE, GAME_OVER }

const BEST_KEY := "best_score"
const COINS_KEY := "coins"
const GEMS_KEY := "gems"
const SKIN_KEY := "skin"
const UNLOCKED_SKINS_KEY := "unlocked_skins"
const MULTIPLIER_LEVEL_KEY := "multiplier_level"
const TOUCH_CONTROLS_KEY := "touch_controls"
const MUSIC_ENABLED_KEY := "music_enabled"
const SFX_ENABLED_KEY := "sfx_enabled"
const SHAKE_ENABLED_KEY := "shake_enabled"
const REDUCED_EFFECTS_KEY := "reduced_effects"
const ITEM_INVENTORY_KEY := "item_inventory"
const MUSIC_VOLUME_KEY := "music_volume"
const SFX_VOLUME_KEY := "sfx_volume"

const SaveData := preload("res://scripts/SaveData.gd")
const FX := preload("res://scripts/FX.gd")
const AdManager := preload("res://scripts/AdManager.gd")
const Coin := preload("res://scripts/Coin.gd")
const Powerup := preload("res://scripts/Powerup.gd")
const SkinCatalog := preload("res://scripts/SkinCatalog.gd")
const CoinScene := preload("res://scenes/Coin.tscn")
const PowerupScene := preload("res://scenes/Powerup.tscn")

## Item shop prices (shield, double score, magnet). Keep in sync with UIManager.SHOP_PRICES.
const SHOP_COSTS := [30, 60, 90]
const MULTIPLIER_MAX_LEVEL := 8

## Collected nodes are parked (invisible, no processing) and reused, so a run
## allocates no new collectible nodes after the first few spawns.
const COIN_POOL_LIMIT := 8
const POWERUP_POOL_LIMIT := 3

## Stage start times are scaled per mode: [Rush, Zen] factors for stages 1-4.
const RUSH_STAGE_FACTORS := [0.8, 0.85, 0.9, 0.95]
const ZEN_STAGE_FACTORS := [1.2, 1.25, 1.3, 1.35]

## Death feel: slow motion (real seconds, so it is not stretched by itself).
const DEATH_SLOWMO_SCALE := 0.25
const DEATH_SLOWMO_SECONDS := 0.55
## Ignore clicks / Space for this long when the revive prompt opens, so a
## panicked key-mash can never spend a gem by accident.
const REVIVE_INPUT_LOCK := 0.5
## Picking coins in quick succession raises the pickup pitch.
const COMBO_WINDOW := 1.2
const COMBO_MAX := 10

var state := State.MENU
var elapsed := 0.0
var best := 0
var coins := 0
var gems := 0
var selected_skin := 0
var unlocked_skins: Array = []
var _next_milestone := 10
var _current_stage := 0
var _stage_cache: Array = []
var _stage_cache_mode := -1
var selected_mode := 0
var score_progress := 0.0
var score_multiplier := 1.0
var run_coins := 0
var multiplier_level := 0
var coin_spawn_timer := 0.0
var powerup_spawn_timer := 0.0
var shield_active := false
var score_boost_time := 0.0
var magnet_time := 0.0
var damage_grace_time := 0.0
var touch_controls := false
var music_enabled := true
var sfx_enabled := true
var shake_enabled := true
var reduced_effects := false
var music_volume_db := -12.0
var sfx_volume_db := -6.0
var is_paused := false
var item_inventory: Array = [0, 0, 0]

var revives_used := 0
var _revive_time_left := 0.0
var _revive_lock := 0.0
var _death_token := 0
var _coin_combo := 0
var _combo_timer := 0.0

var _active_coins: Array = []
var _active_powerups: Array = []
var _coin_pool: Array = []
var _powerup_pool: Array = []
var _save_pending := false
var _danger_rects: Array[Rect2] = []
var _save: RefCounted
var _fx: Node2D
var _ads: Node

## True while the shop / skins / settings screen is open on top of the menu.
var _overlay_open := false
## True during the short loading delay in start_game().
var _starting := false
## Bumped when leaving to the menu so a pending start_game() can cancel itself.
var _start_token := 0
var _last_warning_frame := -1
var _last_activation_frame := -1

@onready var danger_manager := $DangerManager
@onready var player := $Player
@onready var ui := $UI
@onready var game_camera := $Camera2D
@onready var audio := $AudioManager
@onready var tuning := $GameTuning


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile"):
		Engine.max_fps = 60
		get_viewport().msaa_2d = Viewport.MSAA_DISABLED
	$Arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	$DangerManager.process_mode = Node.PROCESS_MODE_PAUSABLE
	$Player.process_mode = Node.PROCESS_MODE_PAUSABLE
	$Camera2D.process_mode = Node.PROCESS_MODE_PAUSABLE

	_save = SaveData.new()
	_save.load_file()

	# Effects layer (drawn above everything in the world) and ad hook.
	_fx = FX.new()
	_fx.name = "FX"
	_fx.z_index = 60
	add_child(_fx)
	_ads = AdManager.new()
	_ads.name = "AdManager"
	add_child(_ads)
	_ads.ad_started.connect(_on_ad_started)
	_ads.ad_rewarded.connect(_on_ad_rewarded)
	_ads.ad_failed.connect(_on_ad_failed)

	player.shield_handler = Callable(self, "_try_consume_shield")
	audio.play_background_music()

	best = _load_best()
	coins = _load_coins()
	gems = _load_gems()
	multiplier_level = clampi(_load_multiplier_level(), 0, MULTIPLIER_MAX_LEVEL)
	selected_skin = clampi(_load_skin(), 0, SkinCatalog.count() - 1)
	var saved_skins := _load_unlocked_skins()
	if saved_skins.size() == SkinCatalog.count():
		unlocked_skins = saved_skins
	else:
		unlocked_skins = _default_unlocked_skins()
	# A skin that is not unlocked can never be equipped (corrupt / edited save).
	if not unlocked_skins[selected_skin]:
		selected_skin = 0

	ui.play_pressed.connect(start_game)
	ui.try_again_pressed.connect(start_game)
	ui.menu_pressed.connect(_enter_menu)
	ui.mode_selected.connect(_on_mode_selected)
	ui.skin_selected.connect(_on_skin_selected)
	ui.skin_menu_pressed.connect(_open_skin_menu)
	ui.skin_menu_closed.connect(_close_skin_menu)
	ui.multiplier_upgrade_pressed.connect(_on_multiplier_upgrade)
	ui.control_mode_selected.connect(_on_control_mode_selected)
	ui.touch_vector_changed.connect(player.set_touch_vector)
	ui.settings_menu_pressed.connect(_open_settings)
	ui.settings_menu_closed.connect(_close_settings)
	ui.setting_changed.connect(_on_setting_changed)
	ui.reset_game_requested.connect(_reset_game_data)
	ui.quit_requested.connect(_quit_game)
	ui.pause_requested.connect(_pause_game)
	ui.resume_requested.connect(_resume_game)
	ui.pause_settings_requested.connect(_open_pause_settings)
	ui.pause_menu_requested.connect(_pause_to_menu)
	ui.shop_menu_pressed.connect(_open_shop)
	ui.shop_menu_closed.connect(_close_shop)
	ui.shop_action.connect(_on_shop_action)
	ui.item_use_requested.connect(_on_item_use_requested)
	ui.volume_changed.connect(_on_volume_changed)
	ui.revive_pressed.connect(_on_revive_pressed)
	ui.revive_ad_pressed.connect(_on_revive_ad_pressed)
	ui.revive_declined.connect(_on_revive_declined)
	ui.gem_ad_requested.connect(_on_gem_ad_requested)
	danger_manager.danger_spawned.connect(_on_danger_spawned)
	player.died.connect(_on_player_died)
	player.wall_hit.connect(_on_player_wall_hit)

	touch_controls = _load_touch_controls()
	# The third argument is the key older versions saved under (see _on_setting_changed).
	music_enabled = _load_setting(MUSIC_ENABLED_KEY, true, "music")
	sfx_enabled = _load_setting(SFX_ENABLED_KEY, true, "sfx")
	shake_enabled = _load_setting(SHAKE_ENABLED_KEY, true, "shake")
	reduced_effects = _load_setting(REDUCED_EFFECTS_KEY, false)
	music_volume_db = _load_volume(MUSIC_VOLUME_KEY, -12.0)
	sfx_volume_db = _load_volume(SFX_VOLUME_KEY, -6.0)
	item_inventory = _load_item_inventory()

	ui.set_selected_mode(selected_mode)
	_push_all_to_ui()
	_apply_settings_to_systems()
	_enter_menu()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Pauses automatically when the window / browser tab loses focus.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == State.PLAYING and not is_paused:
			_pause_game()


func _process(delta: float) -> void:
	if _save_pending:
		_save_pending = false
		_save_progress()

	match state:
		State.PLAYING:
			if not is_paused:
				_process_playing(delta)
		State.REVIVE:
			_process_revive(delta)


func _process_playing(delta: float) -> void:
	elapsed += delta
	coin_spawn_timer -= delta
	if coin_spawn_timer <= 0.0:
		_spawn_coin()
		coin_spawn_timer = maxf(tuning.coin_min_spawn_interval, tuning.coin_spawn_interval * _mode_collectible_multiplier() - elapsed * 0.02)
	powerup_spawn_timer -= delta
	if powerup_spawn_timer <= 0.0:
		_spawn_powerup()
		powerup_spawn_timer = tuning.powerup_spawn_interval * _mode_collectible_multiplier()
	score_boost_time = maxf(0.0, score_boost_time - delta)
	magnet_time = maxf(0.0, magnet_time - delta)
	damage_grace_time = maxf(0.0, damage_grace_time - delta)
	player.set_invulnerable(damage_grace_time > 0.0)
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_coin_combo = 0
	score_progress += delta * _active_multiplier()
	ui.update_timer(elapsed, int(score_progress), _active_multiplier(), coins + run_coins)
	ui.update_active_effects(shield_active, score_boost_time, magnet_time)
	_trigger_stage_progression()
	if elapsed >= _next_milestone:
		var milestone_bonus := 3 + int(score_multiplier * 2.0)
		ui.show_milestone(_next_milestone)
		ui.show_pickup("+%d" % milestone_bonus, Color("#ffe07a"), _world_to_screen(player.global_position))
		game_camera.shake(4.5, 0.14)
		_fx.ring(player.global_position, Color("#ffe07a"), 20.0, 120.0, 0.5, 5.0)
		run_coins += milestone_bonus
		score_multiplier = minf(5.0, score_multiplier + 0.5)
		score_boost_time = maxf(score_boost_time, 2.5)
		_next_milestone += int(tuning.milestone_interval)


func _process_revive(delta: float) -> void:
	if _revive_lock > 0.0:
		_revive_lock = maxf(0.0, _revive_lock - delta)
	# The countdown waits while an ad is being shown.
	if _ads.is_showing:
		return
	_revive_time_left -= delta
	ui.update_revive_timer(_revive_time_left, tuning.revive_prompt_seconds)
	if _revive_time_left <= 0.0:
		_on_revive_declined()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		if state == State.PLAYING and not is_paused and not _overlay_open:
			_pause_game()
		elif is_paused and not _overlay_open:
			_resume_game()
		return
	if state == State.PLAYING and not is_paused and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_on_item_use_requested(0)
			KEY_2:
				_on_item_use_requested(1)
			KEY_3:
				_on_item_use_requested(2)
	# Enter / Space: start or restart instantly (buttons handle their own input,
	# so this won't double-trigger while a button has focus). Ignored while a
	# shop / skins / settings screen is open or a run is already loading.
	if event.is_action_pressed("ui_accept"):
		if (state == State.MENU or state == State.GAME_OVER) and not _overlay_open and not _starting and not _ads.is_showing:
			start_game()
		elif state == State.REVIVE and gems >= tuning.gem_revive_cost:
			_on_revive_pressed()


# ---------------------------------------------------------------------------
# Run flow
# ---------------------------------------------------------------------------

func start_game() -> void:
	if _starting:
		return
	_starting = true
	_overlay_open = false
	var token := _start_token
	audio.play_gameplay_music()
	audio.pause_background_music()
	ui.show_loading("LOADING RUN")
	await get_tree().create_timer(0.28).timeout
	# Cancelled (e.g. back to the menu) while loading.
	if token != _start_token:
		return
	_starting = false
	Engine.time_scale = 1.0
	_death_token += 1
	elapsed = 0.0
	score_progress = 0.0
	score_multiplier = _base_multiplier()
	run_coins = 0
	revives_used = 0
	_coin_combo = 0
	_combo_timer = 0.0
	coin_spawn_timer = tuning.coin_first_spawn_delay
	powerup_spawn_timer = tuning.powerup_first_spawn_delay
	shield_active = false
	player.set_shield_visible(false)
	score_boost_time = 0.0
	magnet_time = 0.0
	damage_grace_time = 0.0
	is_paused = false
	get_tree().paused = false
	_next_milestone = int(tuning.milestone_interval)
	_current_stage = 0
	state = State.PLAYING
	_fx.clear()
	player.reset()
	player.set_skin(selected_skin)
	danger_manager.start(player, selected_mode)
	ui.show_hud(best, coins, score_multiplier)
	ui.update_active_effects(false, 0.0, 0.0)
	ui.set_shop(coins, item_inventory)
	ui.set_item_inventory(item_inventory)
	ui.set_gems(gems)
	ui.show_stage("STAGE 1", "COLD START")
	_clear_coins()
	_clear_powerups()


func _enter_menu() -> void:
	_start_token += 1
	_death_token += 1
	_starting = false
	_overlay_open = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	is_paused = false
	danger_manager.stop()
	_clear_coins()
	_clear_powerups()
	_fx.clear()
	state = State.MENU
	audio.play_background_music()
	player.set_shield_visible(false)
	ui.hide_revive()
	ui.hide_ad_placeholder()
	ui.show_menu(best)


func _on_player_died() -> void:
	if state != State.PLAYING:
		return
	state = State.DYING
	_death_token += 1
	var token := _death_token
	audio.play_death()
	# Freeze the hazards in place: the player can see what killed them, and a
	# revive can then clear them.
	danger_manager.suspend()
	_clear_coins()
	_clear_powerups()
	player.set_invulnerable(false)

	var pos: Vector2 = player.global_position
	var color := SkinCatalog.get_body_color(selected_skin)
	game_camera.shake(14.0, 0.4)
	game_camera.punch(0.07, 0.4)
	ui.flash_danger()
	_fx.burst(pos, color, 40, 460.0, 0.9, 5.0)
	_fx.burst(pos, Color("#ff4d4d"), 22, 300.0, 0.7, 4.0)
	_fx.ring(pos, Color("#ff5b5b"), 20.0, 180.0, 0.55, 6.0)

	# Short slow-motion so the death is readable. The timer ignores time scale.
	Engine.time_scale = DEATH_SLOWMO_SCALE
	await get_tree().create_timer(DEATH_SLOWMO_SECONDS, true, false, true).timeout
	Engine.time_scale = 1.0
	if token != _death_token or state != State.DYING:
		return

	if _can_offer_revive():
		_begin_revive_prompt()
	else:
		_finish_run()


func _can_offer_revive() -> bool:
	if revives_used >= tuning.max_revives_per_run:
		return false
	return gems >= tuning.gem_revive_cost or _ads.enabled


func _begin_revive_prompt() -> void:
	state = State.REVIVE
	_revive_time_left = tuning.revive_prompt_seconds
	_revive_lock = REVIVE_INPUT_LOCK
	ui.show_revive(gems, tuning.revive_prompt_seconds, tuning.max_revives_per_run - revives_used)


func _on_revive_pressed() -> void:
	if state != State.REVIVE or _revive_lock > 0.0 or _ads.is_showing:
		return
	if gems < tuning.gem_revive_cost:
		audio.play_error()
		return
	_spend_gems_and_revive()


func _on_revive_ad_pressed() -> void:
	if state != State.REVIVE or _revive_lock > 0.0:
		return
	_on_gem_ad_requested("revive")


func _on_revive_declined() -> void:
	if state != State.REVIVE or _ads.is_showing:
		return
	ui.hide_revive()
	_finish_run()


func _spend_gems_and_revive() -> void:
	gems = maxi(0, gems - int(tuning.gem_revive_cost))
	_request_save()
	ui.set_gems(gems)
	_do_revive()


func _do_revive() -> void:
	revives_used += 1
	state = State.PLAYING
	ui.hide_revive()
	danger_manager.resume(tuning.revive_pattern_delay)
	player.revive()
	damage_grace_time = tuning.revive_grace_duration
	coin_spawn_timer = 0.8
	var pos: Vector2 = player.global_position
	audio.play_revive()
	game_camera.shake(6.0, 0.2)
	game_camera.punch(0.04, 0.3)
	_fx.ring(pos, Color("#3ddcff"), 20.0, 260.0, 0.6, 6.0)
	_fx.ring(pos, Color.WHITE, 10.0, 160.0, 0.4, 3.0)
	_fx.burst(pos, Color("#3ddcff"), 30, 380.0, 0.8, 4.5)
	var left: int = tuning.max_revives_per_run - revives_used
	ui.show_powerup("REVIVED!  %d LEFT THIS RUN" % left)
	ui.show_pickup("-%d GEM" % int(tuning.gem_revive_cost), Color("#7be9ff"), _world_to_screen(pos))


## Banks the coins of the current run and ends it (also used by quit-to-menu).
func _bank_run() -> int:
	var score := _score()
	run_coins += int(score / 25.0)
	coins += run_coins
	if score > best:
		best = score
	_save_progress()  # saves best, coins, gems and everything else in one write
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)
	return score


func _finish_run() -> void:
	state = State.GAME_OVER
	danger_manager.stop()
	var score := _bank_run()
	var earned := run_coins
	run_coins = 0
	audio.play_background_music()
	ui.set_gems(gems)
	ui.show_game_over(score, best, earned, score_multiplier)


# ---------------------------------------------------------------------------
# Ads / gems
# ---------------------------------------------------------------------------

func _on_gem_ad_requested(placement: String) -> void:
	if _ads.is_showing:
		return
	_ads.request_rewarded_ad(placement)


func _on_ad_started(_placement: String) -> void:
	if AdManager.USE_PLACEHOLDER_UI:
		ui.show_ad_placeholder(AdManager.PLACEHOLDER_SECONDS)


func _on_ad_rewarded(placement: String) -> void:
	ui.hide_ad_placeholder()
	gems += int(tuning.ad_gem_reward)
	_request_save()
	audio.play_gem()
	ui.set_gems(gems, true)
	ui.show_powerup("+%d GEM" % int(tuning.ad_gem_reward))
	# During the revive prompt the ad's gem is used straight away.
	if placement == "revive" and state == State.REVIVE and gems >= tuning.gem_revive_cost:
		_spend_gems_and_revive()


func _on_ad_failed(_placement: String, _reason: String) -> void:
	ui.hide_ad_placeholder()
	audio.play_error()
	ui.show_powerup("AD NOT AVAILABLE")


# ---------------------------------------------------------------------------
# Menus / settings
# ---------------------------------------------------------------------------

func _on_mode_selected(new_mode: int) -> void:
	selected_mode = new_mode
	ui.set_selected_mode(selected_mode)


func _on_control_mode_selected(enabled: bool) -> void:
	touch_controls = enabled
	player.set_touch_enabled(enabled)
	ui.set_touch_controls(enabled)
	_save_touch_controls()


func _open_settings() -> void:
	_overlay_open = true
	ui.show_settings()


func _close_settings() -> void:
	_overlay_open = false
	if is_paused:
		ui.show_pause()
	else:
		ui.show_menu(best)


func _pause_game() -> void:
	if state != State.PLAYING or is_paused:
		return
	is_paused = true
	get_tree().paused = true
	audio.play_background_music()
	audio.pause_gameplay_music()
	ui.show_pause()


func _resume_game() -> void:
	if not is_paused:
		return
	is_paused = false
	get_tree().paused = false
	audio.play_gameplay_music()
	audio.pause_background_music()
	ui.hide_pause()


func _open_pause_settings() -> void:
	_overlay_open = true
	ui.show_settings()


func _pause_to_menu() -> void:
	get_tree().paused = false
	is_paused = false
	# Coins collected so far were shown in the HUD, so they are kept.
	if state == State.PLAYING:
		_bank_run()
		run_coins = 0
	_enter_menu()


func _open_shop() -> void:
	_overlay_open = true
	ui.show_shop()


func _close_shop() -> void:
	_overlay_open = false
	ui.show_menu(best)


func _on_shop_action(item: int, action: String) -> void:
	if item < 0 or item >= SHOP_COSTS.size() or action != "buy":
		return
	if coins < SHOP_COSTS[item]:
		audio.play_error()
		ui.shop_denied(item)
		return
	coins -= SHOP_COSTS[item]
	item_inventory[item] += 1
	audio.play_purchase()
	_request_save()
	ui.set_shop(coins, item_inventory)
	ui.play_shop_purchase(item)


func _request_save() -> void:
	_save_pending = true


func _on_item_use_requested(item: int) -> void:
	if state != State.PLAYING or is_paused or item < 0 or item >= item_inventory.size() or item_inventory[item] <= 0:
		return
	item_inventory[item] -= 1
	audio.play_powerup(item)
	match item:
		0:
			shield_active = true
			player.set_shield_visible(true)
			ui.show_powerup("SHIELD ACTIVE")
		1:
			score_boost_time = tuning.score_boost_duration
			ui.show_powerup("DOUBLE SCORE ACTIVE")
		2:
			magnet_time = tuning.magnet_duration
			ui.show_powerup("COIN MAGNET ACTIVE")
	_fx.ring(player.global_position, Color("#ffd166"), 16.0, 90.0, 0.35, 4.0)
	_request_save()
	ui.set_item_inventory(item_inventory)


func _quit_game() -> void:
	get_tree().quit()


func _reset_game_data() -> void:
	best = 0
	coins = 0
	gems = 0
	multiplier_level = 0
	selected_skin = 0
	unlocked_skins = _default_unlocked_skins()
	touch_controls = false
	music_enabled = true
	sfx_enabled = true
	shake_enabled = true
	reduced_effects = false
	music_volume_db = -12.0
	sfx_volume_db = -6.0
	item_inventory = [0, 0, 0]
	_overlay_open = false
	_save_touch_controls()
	_save_setting(MUSIC_ENABLED_KEY, music_enabled)
	_save_setting(SFX_ENABLED_KEY, sfx_enabled)
	_save_setting(SHAKE_ENABLED_KEY, shake_enabled)
	_save_setting(REDUCED_EFFECTS_KEY, reduced_effects)
	_save_progress()
	player.set_skin(selected_skin)
	_push_all_to_ui()
	_apply_settings_to_systems()
	ui.show_menu(best)


## Pushes every saved value to the UI in one place.
func _push_all_to_ui() -> void:
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)
	ui.set_gems(gems)
	ui.set_shop(coins, item_inventory)
	ui.set_item_inventory(item_inventory)
	ui.set_settings(music_enabled, sfx_enabled, shake_enabled, reduced_effects, touch_controls, music_volume_db, sfx_volume_db)
	ui.set_touch_controls(touch_controls)
	ui.set_reduced_effects(reduced_effects)


## Pushes every setting to the systems that use it (audio, camera, player, FX).
func _apply_settings_to_systems() -> void:
	player.set_touch_enabled(touch_controls)
	player.set_reduced_effects(reduced_effects)
	_fx.set_reduced(reduced_effects)
	audio.set_music_enabled(music_enabled)
	audio.set_sfx_enabled(sfx_enabled)
	audio.set_music_volume_db(music_volume_db)
	audio.set_sfx_volume_db(sfx_volume_db)
	game_camera.shake_enabled = shake_enabled


## `setting` is the UI's short name; each one is saved under its own constant,
## the same key _ready() loads it from.
func _on_setting_changed(setting: String, value: bool) -> void:
	match setting:
		"music":
			music_enabled = value
			audio.set_music_enabled(value)
			_save_setting(MUSIC_ENABLED_KEY, value)
		"sfx":
			sfx_enabled = value
			audio.set_sfx_enabled(value)
			_save_setting(SFX_ENABLED_KEY, value)
		"shake":
			shake_enabled = value
			game_camera.shake_enabled = value
			_save_setting(SHAKE_ENABLED_KEY, value)
		"reduced_effects":
			reduced_effects = value
			ui.set_reduced_effects(value)
			player.set_reduced_effects(value)
			_fx.set_reduced(value)
			_save_setting(REDUCED_EFFECTS_KEY, value)
		"touch_controls":
			touch_controls = value
			player.set_touch_enabled(value)
			ui.set_touch_controls(value)
			_save_touch_controls()
	ui.set_settings(music_enabled, sfx_enabled, shake_enabled, reduced_effects, touch_controls, music_volume_db, sfx_volume_db)


func _on_volume_changed(volume_name: String, value: float) -> void:
	match volume_name:
		"music_volume":
			music_volume_db = value
			audio.set_music_volume_db(value)
		"sfx_volume":
			sfx_volume_db = value
			audio.set_sfx_volume_db(value)
	# Sliders fire on every drag step: save once, on the next frame.
	_request_save()


func _open_skin_menu() -> void:
	_overlay_open = true
	ui.show_skin_menu()


func _close_skin_menu() -> void:
	_overlay_open = false
	ui.show_menu(best)


func _on_skin_selected(skin: int) -> void:
	if skin < 0 or skin >= SkinCatalog.count() or skin >= unlocked_skins.size():
		return
	var skin_data := SkinCatalog.get_skin(skin)
	var unlocked_now := false
	if not unlocked_skins[skin]:
		if coins < int(skin_data.cost):
			audio.play_error()
			ui.skin_denied(skin)
			return
		coins -= int(skin_data.cost)
		unlocked_skins[skin] = true
		unlocked_now = true
		audio.play_purchase()
	selected_skin = skin
	_request_save()
	player.set_skin(selected_skin)
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)
	ui.play_skin_effect(skin, unlocked_now)


func _on_multiplier_upgrade() -> void:
	if multiplier_level >= MULTIPLIER_MAX_LEVEL:
		return
	var cost := _multiplier_upgrade_cost()
	if coins < cost:
		audio.play_error()
		ui.shop_denied(3)
		return
	coins -= cost
	multiplier_level += 1
	audio.play_purchase()
	_request_save()
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)
	ui.play_upgrade_effect()


func _base_multiplier() -> float:
	var mode_bonus := 1.0
	if selected_mode == 1:
		mode_bonus = tuning.rush_score_multiplier
	elif selected_mode == 2:
		mode_bonus = tuning.zen_score_multiplier
	return minf(5.0, (1.0 + multiplier_level * 0.5) * mode_bonus)


## Stage start times (seconds) for a mode. The DangerManager reads this too,
## so the stage banners and the pattern unlocks always happen together.
func get_stage_times(for_mode: int) -> Array:
	var factors := [1.0, 1.0, 1.0, 1.0]
	if for_mode == 1:
		factors = RUSH_STAGE_FACTORS
	elif for_mode == 2:
		factors = ZEN_STAGE_FACTORS
	return [
		float(tuning.stage_1_threshold) * factors[0],
		float(tuning.stage_2_threshold) * factors[1],
		float(tuning.stage_3_threshold) * factors[2],
		float(tuning.stage_4_threshold) * factors[3],
	]


func _trigger_stage_progression() -> void:
	if _stage_cache_mode != selected_mode or _stage_cache.is_empty():
		_stage_cache = get_stage_times(selected_mode)
		_stage_cache_mode = selected_mode
	var stages := _stage_cache
	if _current_stage >= stages.size():
		return
	if elapsed < stages[_current_stage]:
		return
	var title := "STAGE %d" % (_current_stage + 1)
	var label := "COLD START"
	match _current_stage:
		0:
			label = "COLD START"
		1:
			label = "RUSH"
		2:
			label = "CHAOS"
		3:
			label = "VOID"
	var reward := int(tuning.stage_reward_coins + _current_stage * 2)
	ui.show_stage(title + "\n" + label, "+%d COINS" % reward)
	ui.show_pickup("+%d" % reward, Color("#ffd166"), _world_to_screen(player.global_position))
	game_camera.shake(5.5 + _current_stage * 1.5, 0.16)
	game_camera.punch(0.03, 0.25)
	_fx.ring(Vector2.ZERO, Color("#f3d17b"), 30.0, 420.0, 0.7, 6.0)
	run_coins += reward
	score_multiplier = minf(5.0, score_multiplier + tuning.stage_reward_score_bonus)
	score_boost_time = maxf(score_boost_time, 4.0 + _current_stage)
	ui.show_powerup("SURVIVAL BOOST +%ds" % int(4.0 + _current_stage))
	_current_stage += 1


func _mode_collectible_multiplier() -> float:
	if selected_mode == 1:
		return 0.72
	if selected_mode == 2:
		return 1.25
	return 1.0


func _multiplier_upgrade_cost() -> int:
	return 50 + multiplier_level * 75


func _on_danger_spawned(zone: Node) -> void:
	if zone.has_signal("warning_started"):
		zone.warning_started.connect(_on_danger_warning)
	if zone.has_signal("activated"):
		zone.activated.connect(_on_danger_activated)


## A pattern spawns several zones at once; react to the whole pattern only once.
func _on_danger_warning() -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_warning_frame:
		return
	_last_warning_frame = frame
	audio.play_warning()


func _on_danger_activated() -> void:
	if state != State.PLAYING:
		return
	var frame := Engine.get_physics_frames()
	if frame == _last_activation_frame:
		return
	_last_activation_frame = frame
	game_camera.shake(4.0, 0.16)
	ui.pulse_danger()
	audio.play_danger()


func _on_player_wall_hit(world_pos: Vector2, strength: float) -> void:
	if state != State.PLAYING:
		return
	_fx.burst(world_pos, Color(0.45, 0.5, 0.6), 4 + int(strength * 4.0), 140.0 * strength + 40.0, 0.35, 2.6)
	game_camera.shake(0.8 + strength * 1.2, 0.06)


func _try_consume_shield() -> bool:
	if damage_grace_time > 0.0:
		return true
	if not shield_active:
		return false
	shield_active = false
	player.set_shield_visible(false)
	damage_grace_time = tuning.shield_grace_duration
	ui.show_powerup("SHIELD SAVED YOU")
	_fx.ring(player.global_position, Color("#ffd166"), 20.0, 130.0, 0.4, 5.0)
	_fx.burst(player.global_position, Color("#ffd166"), 16, 280.0, 0.5, 3.5)
	game_camera.shake(6.0, 0.18)
	return true


func _active_multiplier() -> float:
	return score_multiplier * (2.0 if score_boost_time > 0.0 else 1.0)


func is_magnet_active() -> bool:
	return magnet_time > 0.0


## World position -> UI (screen) position, so floating text appears on the object.
func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


# ---------------------------------------------------------------------------
# Collectibles
# ---------------------------------------------------------------------------

## Collects the bounds of every danger that is warning or active, so pickups
## never appear in something about to turn lethal.
func _refresh_danger_rects() -> void:
	_danger_rects.clear()
	for child in danger_manager.get_children():
		if not child.has_method("get_danger_rect"):
			continue
		var alive := false
		if child.has_method("is_alive"):
			alive = child.is_alive()
		elif child.has_method("is_active"):
			alive = child.is_active()
		if alive:
			_danger_rects.append(child.get_danger_rect())


func _spawn_coin() -> void:
	if _active_coins.size() >= tuning.max_active_coins:
		return
	_refresh_danger_rects()
	for attempt in range(48):
		var spawn_pos := Vector2(randf_range(-360.0, 360.0), randf_range(-260.0, 260.0))
		if _coin_position_is_safe(spawn_pos):
			var coin: Coin = _obtain_coin()
			var roll := randf()
			var kind := Coin.Kind.COMMON
			if roll > 0.94:
				kind = Coin.Kind.EPIC
			elif roll > 0.72:
				kind = Coin.Kind.RARE
			coin.z_index = 10
			coin.position = spawn_pos
			coin.activate(kind, tuning.common_coin_lifetime, tuning.rare_coin_lifetime, tuning.epic_coin_lifetime)
			_active_coins.append(coin)
			return


func _spawn_powerup() -> void:
	if _active_powerups.size() >= 1:
		return
	_refresh_danger_rects()
	for attempt in range(12):
		var spawn_pos := Vector2(randf_range(-340.0, 340.0), randf_range(-240.0, 240.0))
		if _coin_position_is_safe(spawn_pos):
			var powerup: Powerup = _obtain_powerup()
			powerup.z_index = 10
			powerup.position = spawn_pos
			powerup.activate(randi_range(0, 2), tuning.powerup_lifetime)
			_active_powerups.append(powerup)
			return


func _on_powerup_collected(kind: int, world_pos: Vector2) -> void:
	if state != State.PLAYING:
		return
	game_camera.shake(3.0, 0.12)
	audio.play_powerup(kind)
	var color := Color("#72d99a")
	match kind:
		Powerup.Kind.SHIELD:
			shield_active = true
			player.set_shield_visible(true)
			ui.show_powerup("SHIELD READY")
		Powerup.Kind.DOUBLE_SCORE:
			color = Color("#ffcc58")
			score_boost_time = tuning.score_boost_duration
			ui.show_powerup("DOUBLE SCORE - %ds" % int(tuning.score_boost_duration))
		Powerup.Kind.MAGNET:
			color = Color("#70c8ff")
			magnet_time = tuning.magnet_duration
			ui.show_powerup("COIN MAGNET - %ds" % int(tuning.magnet_duration))
	_fx.burst(world_pos, color, 18, 300.0, 0.6, 4.0)
	_fx.ring(world_pos, color, 14.0, 100.0, 0.4, 4.0)


func _clear_powerups() -> void:
	for powerup in _active_powerups.duplicate():
		powerup.release()
	_active_powerups.clear()


func _coin_position_is_safe(world_position: Vector2) -> bool:
	if is_instance_valid(player) and world_position.distance_to(player.position) < 36.0:
		return false
	for rect in _danger_rects:
		if rect.grow(20.0).has_point(world_position):
			return false
	return true


func _coin_color(value: int) -> Color:
	if value >= 8:
		return Color("#d28bff")
	if value >= 3:
		return Color("#6ec6ff")
	return Color("#ffdc65")


func _on_coin_collected(value: int, world_pos: Vector2) -> void:
	if state != State.PLAYING:
		return
	_coin_combo = mini(_coin_combo + 1, COMBO_MAX)
	_combo_timer = COMBO_WINDOW
	run_coins += value
	audio.play_coin(value, 1.0 + 0.05 * float(_coin_combo - 1))
	score_progress += value * tuning.coin_score_value * _active_multiplier()
	game_camera.shake(1.5, 0.06)
	var color := _coin_color(value)
	_fx.burst(world_pos, color, 6 + value, 200.0, 0.45, 3.0)
	if value >= 3:
		_fx.ring(world_pos, color, 10.0, 60.0, 0.3, 3.0)
	ui.show_pickup("+%d" % value, color, _world_to_screen(world_pos))
	ui.update_timer(elapsed, int(score_progress), _active_multiplier(), coins + run_coins)


func _clear_coins() -> void:
	for coin in _active_coins.duplicate():
		coin.release()
	_active_coins.clear()


func _obtain_coin() -> Coin:
	while not _coin_pool.is_empty():
		var pooled: Coin = _coin_pool.pop_back()
		if is_instance_valid(pooled):
			return pooled
	var coin: Coin = CoinScene.instantiate()
	coin.add_to_group("run_coins")
	coin.collected.connect(_on_coin_collected)
	coin.removed.connect(_on_coin_removed)
	coin.recycled.connect(_on_coin_recycled)
	add_child(coin)
	return coin


func _on_coin_removed(coin: Coin) -> void:
	if coin in _active_coins:
		_active_coins.erase(coin)


func _on_powerup_removed(powerup: Powerup) -> void:
	if powerup in _active_powerups:
		_active_powerups.erase(powerup)


func _on_coin_recycled(coin: Coin) -> void:
	if coin in _active_coins:
		_active_coins.erase(coin)
	if coin in _coin_pool:
		return
	if _coin_pool.size() >= COIN_POOL_LIMIT:
		coin.queue_free()
		return
	_coin_pool.append(coin)


func _on_powerup_recycled(powerup: Powerup) -> void:
	if powerup in _active_powerups:
		_active_powerups.erase(powerup)
	if powerup in _powerup_pool:
		return
	if _powerup_pool.size() >= POWERUP_POOL_LIMIT:
		powerup.queue_free()
		return
	_powerup_pool.append(powerup)


func _obtain_powerup() -> Powerup:
	while not _powerup_pool.is_empty():
		var pooled: Powerup = _powerup_pool.pop_back()
		if is_instance_valid(pooled):
			return pooled
	var powerup: Powerup = PowerupScene.instantiate()
	powerup.add_to_group("run_powerups")
	powerup.collected.connect(_on_powerup_collected)
	powerup.removed.connect(_on_powerup_removed)
	powerup.recycled.connect(_on_powerup_recycled)
	add_child(powerup)
	return powerup


func _score() -> int:
	return int(score_progress)


# ---------------------------------------------------------------------------
# Persistence (one cached ConfigFile, written at most once per frame)
# ---------------------------------------------------------------------------

func _load_best() -> int:
	return maxi(0, int(_save.get_value("meta", BEST_KEY, 0)))


func _load_coins() -> int:
	return maxi(0, int(_save.get_value("meta", COINS_KEY, 0)))


func _load_gems() -> int:
	return maxi(0, int(_save.get_value("meta", GEMS_KEY, 0)))


func _load_skin() -> int:
	return int(_save.get_value("meta", SKIN_KEY, 0))


func _load_multiplier_level() -> int:
	return maxi(0, int(_save.get_value("meta", MULTIPLIER_LEVEL_KEY, 0)))


func _load_unlocked_skins() -> Array:
	var saved_value: Variant = _save.get_value("meta", UNLOCKED_SKINS_KEY, null)
	if saved_value is Array:
		var skins: Array = []
		for i in range(SkinCatalog.count()):
			skins.append(i < saved_value.size() and bool(saved_value[i]))
		skins[0] = true
		return skins
	return _default_unlocked_skins()


func _load_touch_controls() -> bool:
	return bool(_save.get_value("meta", TOUCH_CONTROLS_KEY, _touch_device_detected()))


func _touch_device_detected() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


## `legacy_key` is an older name this setting may have been saved under.
func _load_setting(key: String, fallback: bool, legacy_key := "") -> bool:
	var value: Variant = _save.get_value("settings", key, null)
	if value == null and legacy_key != "":
		value = _save.get_value("settings", legacy_key, null)
	if value == null:
		return fallback
	return bool(value)


func _save_setting(key: String, value: bool) -> void:
	_save.set_value("settings", key, value)
	_request_save()


func _save_touch_controls() -> void:
	_save.set_value("meta", TOUCH_CONTROLS_KEY, touch_controls)
	_request_save()


func _load_volume(key: String, fallback: float) -> float:
	var value: Variant = _save.get_value("settings", key, null)
	if value == null:
		return fallback
	return float(value)


func _load_item_inventory() -> Array:
	var saved: Variant = _save.get_value("meta", ITEM_INVENTORY_KEY, [0, 0, 0])
	if saved is Array and saved.size() == 3:
		return [maxi(0, int(saved[0])), maxi(0, int(saved[1])), maxi(0, int(saved[2]))]
	return [0, 0, 0]


func _default_unlocked_skins() -> Array:
	var skins: Array = []
	for i in range(SkinCatalog.count()):
		skins.append(i == 0)
	return skins


func _save_progress() -> void:
	_save.set_value("meta", BEST_KEY, best)
	_save.set_value("meta", COINS_KEY, coins)
	_save.set_value("meta", GEMS_KEY, gems)
	_save.set_value("meta", SKIN_KEY, selected_skin)
	_save.set_value("meta", UNLOCKED_SKINS_KEY, unlocked_skins)
	_save.set_value("meta", MULTIPLIER_LEVEL_KEY, multiplier_level)
	_save.set_value("meta", ITEM_INVENTORY_KEY, item_inventory)
	_save.set_value("settings", MUSIC_VOLUME_KEY, music_volume_db)
	_save.set_value("settings", SFX_VOLUME_KEY, sfx_volume_db)
	_save.save()
