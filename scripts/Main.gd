extends Node2D

## Game coordinator: owns the game state machine, survival timer/score, and the
## best-score persistence. The DangerManager and UI are driven from here.

enum State { MENU, PLAYING, GAME_OVER }

const SAVE_PATH := "user://dttr_config.cfg"
const BEST_KEY := "best_score"
const COINS_KEY := "coins"
const SKIN_KEY := "skin"
const UNLOCKED_SKINS_KEY := "unlocked_skins"
const MULTIPLIER_LEVEL_KEY := "multiplier_level"
const TOUCH_CONTROLS_KEY := "touch_controls"
const MUSIC_ENABLED_KEY := "music_enabled"
const SFX_ENABLED_KEY := "sfx_enabled"
const SHAKE_ENABLED_KEY := "shake_enabled"
const REDUCED_EFFECTS_KEY := "reduced_effects"
const ITEM_INVENTORY_KEY := "item_inventory"
const Coin := preload("res://scripts/Coin.gd")
const Powerup := preload("res://scripts/Powerup.gd")
const SkinCatalog := preload("res://scripts/SkinCatalog.gd")
const CoinScene := preload("res://scenes/Coin.tscn")
const PowerupScene := preload("res://scenes/Powerup.tscn")

## Collected nodes are parked (invisible, no processing) and reused, so a run
## allocates no new collectible nodes after the first few spawns.
const COIN_POOL_LIMIT := 8
const POWERUP_POOL_LIMIT := 3

var state := State.MENU
var elapsed := 0.0
var best := 0
var coins := 0
var selected_skin := 0
var unlocked_skins: Array = []
var _next_milestone := 10
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
var is_paused := false
var item_inventory: Array = [0, 0, 0]

var _active_coins: Array = []
var _active_powerups: Array = []
var _coin_pool: Array = []
var _powerup_pool: Array = []
var _current_scene: Node = null
var _save_pending := false
var _danger_rects: Array[Rect2] = []

@onready var danger_manager := $DangerManager
@onready var player := $Player
@onready var ui := $UI
@onready var game_camera := $Camera2D
@onready var audio := $AudioManager
@onready var tuning := $GameTuning


func _ready() -> void:
	audio.play_background_music()
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	$DangerManager.process_mode = Node.PROCESS_MODE_PAUSABLE
	$Player.process_mode = Node.PROCESS_MODE_PAUSABLE
	$Camera2D.process_mode = Node.PROCESS_MODE_PAUSABLE
	_current_scene = get_tree().current_scene
	best = _load_best()
	coins = _load_coins()
	multiplier_level = clampi(_load_multiplier_level(), 0, 8)
	selected_skin = _load_skin()
	selected_skin = clampi(selected_skin, 0, SkinCatalog.count() - 1)
	var saved_skins = _load_unlocked_skins()
	if saved_skins.size() == SkinCatalog.count():
		unlocked_skins = saved_skins
	else:
		unlocked_skins = _default_unlocked_skins()
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
	danger_manager.danger_spawned.connect(_on_danger_spawned)
	ui.set_selected_mode(selected_mode)
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)
	touch_controls = _load_touch_controls()
	music_enabled = _load_setting(MUSIC_ENABLED_KEY, true)
	sfx_enabled = _load_setting(SFX_ENABLED_KEY, true)
	shake_enabled = _load_setting(SHAKE_ENABLED_KEY, true)
	reduced_effects = _load_setting(REDUCED_EFFECTS_KEY, false)
	item_inventory = _load_item_inventory()
	player.set_touch_enabled(touch_controls)
	ui.set_touch_controls(touch_controls)
	ui.set_settings(music_enabled, sfx_enabled, shake_enabled, reduced_effects, touch_controls)
	ui.set_shop(coins, item_inventory)
	ui.set_item_inventory(item_inventory)
	ui.set_reduced_effects(reduced_effects)
	audio.set_music_enabled(music_enabled)
	audio.set_sfx_enabled(sfx_enabled)
	game_camera.shake_enabled = shake_enabled
	_enter_menu()

func _process(delta: float) -> void:
	if _save_pending:
		_save_pending = false
		_save_progress()
	if state == State.PLAYING and not is_paused:
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
		score_progress += delta * _active_multiplier()
		ui.update_timer(elapsed, int(score_progress), _active_multiplier(), coins + run_coins)
		ui.update_active_effects(shield_active, score_boost_time, magnet_time)
		if elapsed >= _next_milestone:
			ui.show_milestone(_next_milestone)
			game_camera.shake(2.5, 0.12)
			run_coins += 5 + int(score_multiplier)
			score_multiplier = minf(5.0, score_multiplier + 0.5)
			_next_milestone += int(tuning.milestone_interval)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		if state == State.PLAYING and not is_paused:
			_pause_game()
		elif is_paused:
			_resume_game()
		return
	if state == State.PLAYING and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_on_item_use_requested(0)
			KEY_2:
				_on_item_use_requested(1)
			KEY_3:
				_on_item_use_requested(2)
	# Enter / Space start or restart instantly (buttons handle their own input,
	# so this won't double-trigger while a button has focus).
	if event.is_action_pressed("ui_accept"):
		if state == State.MENU or state == State.GAME_OVER:
			start_game()

func start_game() -> void:
	audio.play_gameplay_music()
	audio.pause_background_music()
	ui.show_loading("LOADING RUN")
	await get_tree().create_timer(0.28).timeout
	elapsed = 0.0
	score_progress = 0.0
	score_multiplier = _base_multiplier()
	run_coins = 0
	coin_spawn_timer = tuning.coin_first_spawn_delay
	powerup_spawn_timer = tuning.powerup_first_spawn_delay
	shield_active = false
	score_boost_time = 0.0
	magnet_time = 0.0
	damage_grace_time = 0.0
	is_paused = false
	get_tree().paused = false
	_next_milestone = int(tuning.milestone_interval)
	state = State.PLAYING
	player.reset()
	player.set_skin(selected_skin)
	danger_manager.start(player, selected_mode)
	ui.show_hud(best, coins, score_multiplier)
	ui.update_active_effects(false, 0.0, 0.0)
	ui.set_shop(coins, item_inventory)
	ui.set_item_inventory(item_inventory)
	_current_scene = get_tree().current_scene
	_clear_coins()
	_clear_powerups()

func _enter_menu() -> void:
	get_tree().paused = false
	is_paused = false
	danger_manager.stop()
	_clear_coins()
	_clear_powerups()
	state = State.MENU
	audio.play_background_music()
	ui.show_menu(best)

func _on_mode_selected(new_mode: int) -> void:
	selected_mode = new_mode
	ui.set_selected_mode(selected_mode)

func _on_control_mode_selected(enabled: bool) -> void:
	touch_controls = enabled
	player.set_touch_enabled(enabled)
	ui.set_touch_controls(enabled)
	_save_touch_controls()

func _open_settings() -> void:
	ui.show_settings()

func _close_settings() -> void:
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
	ui.show_settings()

func _pause_to_menu() -> void:
	get_tree().paused = false
	is_paused = false
	_enter_menu()

func _open_shop() -> void:
	ui.show_shop()

func _close_shop() -> void:
	ui.show_menu(best)

func _on_shop_action(item: int, action: String) -> void:
	var costs := [30, 60, 90]
	if item < 0 or item > 2:
		return
	if action == "buy" and coins >= costs[item]:
		coins -= costs[item]
		item_inventory[item] += 1
		audio.play_ui()
	else:
		return
	_request_save()
	ui.set_shop(coins, item_inventory)

func _request_save() -> void:
	_save_pending = true

func _on_item_use_requested(item: int) -> void:
	if state != State.PLAYING or item < 0 or item >= item_inventory.size() or item_inventory[item] <= 0:
		return
	item_inventory[item] -= 1
	audio.play_powerup(item)
	match item:
		0:
			shield_active = true
			ui.show_powerup("SHIELD ACTIVE")
		1:
			score_boost_time = tuning.score_boost_duration
			ui.show_powerup("DOUBLE SCORE ACTIVE")
		2:
			magnet_time = tuning.magnet_duration
			ui.show_powerup("COIN MAGNET ACTIVE")
	_request_save()
	ui.set_item_inventory(item_inventory)

func _quit_game() -> void:
	get_tree().quit()

func _reset_game_data() -> void:
	best = 0
	coins = 0
	multiplier_level = 0
	selected_skin = 0
	unlocked_skins = _default_unlocked_skins()
	touch_controls = false
	music_enabled = true
	sfx_enabled = true
	shake_enabled = true
	reduced_effects = false
	item_inventory = [0, 0, 0]
	_save_progress()
	_save_touch_controls()
	_save_setting(MUSIC_ENABLED_KEY, music_enabled)
	_save_setting(SFX_ENABLED_KEY, sfx_enabled)
	_save_setting(SHAKE_ENABLED_KEY, shake_enabled)
	_save_setting(REDUCED_EFFECTS_KEY, reduced_effects)
	player.set_skin(selected_skin)
	player.set_touch_enabled(touch_controls)
	audio.set_music_enabled(music_enabled)
	audio.set_sfx_enabled(sfx_enabled)
	game_camera.shake_enabled = shake_enabled
	ui.set_touch_controls(touch_controls)
	ui.set_reduced_effects(reduced_effects)
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)
	ui.set_shop(coins, item_inventory)
	ui.set_item_inventory(item_inventory)
	ui.set_settings(music_enabled, sfx_enabled, shake_enabled, reduced_effects, touch_controls)
	ui.show_menu(best)

func _on_setting_changed(name: String, value: bool) -> void:
	match name:
		"music":
			music_enabled = value
			audio.set_music_enabled(value)
		"sfx":
			sfx_enabled = value
			audio.set_sfx_enabled(value)
		"shake":
			shake_enabled = value
			game_camera.shake_enabled = value
		"reduced_effects":
			reduced_effects = value
			ui.set_reduced_effects(value)
		"touch_controls":
			touch_controls = value
			player.set_touch_enabled(value)
			ui.set_touch_controls(value)
	_save_setting(name, value)
	ui.set_settings(music_enabled, sfx_enabled, shake_enabled, reduced_effects, touch_controls)

func _open_skin_menu() -> void:
	ui.show_skin_menu()

func _close_skin_menu() -> void:
	ui.show_menu(best)

func _on_skin_selected(skin: int) -> void:
	if skin < 0 or skin >= SkinCatalog.count() or skin >= unlocked_skins.size():
		return
	var skin_data := SkinCatalog.get_skin(skin)
	if not unlocked_skins[skin] and coins >= int(skin_data.cost):
		coins -= int(skin_data.cost)
		unlocked_skins[skin] = true
	if unlocked_skins[skin]:
		selected_skin = skin
		_request_save()
		player.set_skin(selected_skin)
		ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)

func _on_multiplier_upgrade() -> void:
	if multiplier_level >= 8:
		return
	var cost := _multiplier_upgrade_cost()
	if coins < cost:
		return
	coins -= cost
	multiplier_level += 1
	_request_save()
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)

func _base_multiplier() -> float:
	var mode_bonus := 1.0
	if selected_mode == 1:
		mode_bonus = tuning.rush_score_multiplier
	elif selected_mode == 2:
		mode_bonus = tuning.zen_score_multiplier
	return minf(5.0, (1.0 + multiplier_level * 0.5) * mode_bonus)

func _mode_collectible_multiplier() -> float:
	if selected_mode == 1:
		return 0.72
	if selected_mode == 2:
		return 1.25
	return 1.0

func _multiplier_upgrade_cost() -> int:
	return 50 + multiplier_level * 75

func _on_player_died() -> void:
	if state != State.PLAYING:
		return
	audio.play_death()
	state = State.GAME_OVER
	
	if elapsed >= _next_milestone:
		ui.show_milestone(_next_milestone)
		_next_milestone += 10
	game_camera.shake(12.0, 0.35)
	ui.flash_danger()
	danger_manager.stop()
	_clear_coins()
	_clear_powerups()
	var score := _score()
	run_coins += int(score / 10.0)
	coins += run_coins
	_save_progress()
	ui.set_progression(coins, selected_skin, unlocked_skins, multiplier_level)
	if score > best:
		best = score
		_save_best()
	audio.play_background_music()
	ui.show_game_over(score, best, run_coins, score_multiplier)

func _on_danger_spawned(zone: Node) -> void:
	if zone.has_signal("warning_started"):
		zone.warning_started.connect(audio.play_warning)
	if zone.has_signal("activated"):
		zone.activated.connect(_on_danger_activated)

func _on_danger_activated() -> void:
	if state == State.PLAYING:
		game_camera.shake(4.0, 0.16)
		ui.pulse_danger()
		audio.play_danger()

func _try_consume_shield() -> bool:
	if damage_grace_time > 0.0:
		return true
	if not shield_active:
		return false
	shield_active = false
	damage_grace_time = tuning.shield_grace_duration
	ui.show_powerup("SHIELD SAVED YOU")
	return true

func _active_multiplier() -> float:
	return score_multiplier * (2.0 if score_boost_time > 0.0 else 1.0)

func is_magnet_active() -> bool:
	return magnet_time > 0.0

func _spawn_coin() -> void:
	if _active_coins.size() >= tuning.max_active_coins:
		return
	_danger_rects.clear()
	for child in danger_manager.get_children():
		if child.has_method("is_active") and child.is_active() and child.has_method("get_danger_rect"):
			_danger_rects.append(child.get_danger_rect())
	for attempt in range(48):
		var position := Vector2(randf_range(-360.0, 360.0), randf_range(-260.0, 260.0))
		if _coin_position_is_safe(position):
			var coin: Coin = _obtain_coin()
			var roll := randf()
			var kind := Coin.Kind.COMMON
			if roll > 0.94:
				kind = Coin.Kind.EPIC
			elif roll > 0.72:
				kind = Coin.Kind.RARE
			coin.z_index = 10
			coin.position = position
			coin.activate(kind, tuning.common_coin_lifetime, tuning.rare_coin_lifetime, tuning.epic_coin_lifetime)
			_active_coins.append(coin)
			return

func _spawn_powerup() -> void:
	if _active_powerups.size() >= 1:
		return
	for attempt in range(12):
		var position := Vector2(randf_range(-340.0, 340.0), randf_range(-240.0, 240.0))
		if _coin_position_is_safe(position):
			var powerup: Powerup = _obtain_powerup()
			powerup.z_index = 10
			powerup.position = position
			powerup.activate(randi_range(0, 2), tuning.powerup_lifetime)
			_active_powerups.append(powerup)
			return

func _on_powerup_collected(kind: int) -> void:
	game_camera.shake(3.0, 0.12)
	audio.play_powerup(kind)
	match kind:
		Powerup.Kind.SHIELD:
			shield_active = true
			ui.show_powerup("SHIELD READY")
		Powerup.Kind.DOUBLE_SCORE:
			score_boost_time = tuning.score_boost_duration
			ui.show_powerup("DOUBLE SCORE - 8s")
		Powerup.Kind.MAGNET:
			magnet_time = tuning.magnet_duration
			ui.show_powerup("COIN MAGNET - 8s")

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

func _on_coin_collected(value: int) -> void:
	if state != State.PLAYING:
		return
	run_coins += value
	audio.play_coin(value)
	score_progress += value * 5.0 * _active_multiplier()
	game_camera.shake(1.5, 0.06)
	ui.show_pickup("+%d" % value, Color("#ffdc65"))
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

func _load_best() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return maxi(0, int(cfg.get_value("meta", BEST_KEY, 0)))
	return 0

func _load_coins() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return maxi(0, int(cfg.get_value("meta", COINS_KEY, 0)))
	return 0

func _load_skin() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return int(cfg.get_value("meta", SKIN_KEY, 0))
	return 0

func _load_unlocked_skins() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved_value: Variant = cfg.get_value("meta", UNLOCKED_SKINS_KEY, null)
		if saved_value is Array:
			var skins: Array = []
			for i in range(SkinCatalog.count()):
				skins.append(i < saved_value.size() and bool(saved_value[i]))
			skins[0] = true
			return skins
	return _default_unlocked_skins()

func _load_touch_controls() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return bool(cfg.get_value("meta", TOUCH_CONTROLS_KEY, _touch_device_detected()))
	return _touch_device_detected()

func _touch_device_detected() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

func _load_setting(key: String, fallback: bool) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return bool(cfg.get_value("settings", key, fallback))
	return fallback

func _save_setting(key: String, value: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("settings", key, value)
	cfg.save(SAVE_PATH)

func _save_touch_controls() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("meta", TOUCH_CONTROLS_KEY, touch_controls)
	cfg.save(SAVE_PATH)

func _load_multiplier_level() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return maxi(0, int(cfg.get_value("meta", MULTIPLIER_LEVEL_KEY, 0)))
	return 0

func _load_item_inventory() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved: Variant = cfg.get_value("meta", ITEM_INVENTORY_KEY, [0, 0, 0])
		if saved is Array and saved.size() == 3:
			return [maxi(0, int(saved[0])), maxi(0, int(saved[1])), maxi(0, int(saved[2]))]
	return [0, 0, 0]

func _default_unlocked_skins() -> Array:
	var skins: Array = []
	for i in range(SkinCatalog.count()):
		skins.append(i == 0)
	return skins

func _skin_costs() -> Array:
	var costs: Array = []
	for skin in SkinCatalog.SKINS:
		costs.append(int(skin.cost))
	return costs

func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("meta", BEST_KEY, best)
	cfg.set_value("meta", COINS_KEY, coins)
	cfg.set_value("meta", SKIN_KEY, selected_skin)
	cfg.set_value("meta", UNLOCKED_SKINS_KEY, unlocked_skins)
	cfg.set_value("meta", MULTIPLIER_LEVEL_KEY, multiplier_level)
	cfg.set_value("meta", ITEM_INVENTORY_KEY, item_inventory)
	cfg.save(SAVE_PATH)

func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("meta", BEST_KEY, best)
	cfg.save(SAVE_PATH)
