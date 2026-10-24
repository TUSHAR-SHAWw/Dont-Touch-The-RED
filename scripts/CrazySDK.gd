extends Node
## Thin wrapper around the CrazyGames HTML5 SDK (v3) for the Godot web export.
##
## The SDK <script> and the first init() call live in the export preset's
## "Head Include" (see export_presets.cfg); that script sets window.__cg to
## {ready, failed}. This autoload polls that flag, then forwards the events
## CrazyGames needs. Everything is a safe no-op when:
##   * the game is not running in a browser (editor, desktop builds), or
##   * the SDK failed to load or initialise (offline, blocked, local testing).
##
## Events sent:
##   loadingStart  - by the head script, as soon as init() succeeds
##   loadingStop   - loading_stop(), when the main menu is ready
##   gameplayStart / gameplayStop - set_gameplay(), on every run start,
##     resume, revive, death, pause and return to the menu.

signal sdk_ready

const INIT_TIMEOUT := 8.0
const POLL_INTERVAL := 0.1

var is_ready := false

var _failed := false
var _waited := 0.0
var _poll := 0.0
var _want_playing := false
var _sent_playing := false
var _loading_stop_requested := false
var _loading_stop_sent := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		set_process(false)


func _process(delta: float) -> void:
	_waited += delta
	_poll += delta
	if _poll < POLL_INTERVAL:
		return
	_poll = 0.0
	var status := int(JavaScriptBridge.eval(
			"(window.__cg && window.__cg.ready) ? 1 : ((window.__cg && window.__cg.failed) ? 2 : 0)", true))
	if status == 1:
		is_ready = true
		set_process(false)
		sdk_ready.emit()
		_flush()
	elif status == 2 or _waited > INIT_TIMEOUT:
		_failed = true
		set_process(false)


## Call once, when the game has finished loading and the menu is showing.
func loading_stop() -> void:
	_loading_stop_requested = true
	_flush()


## True while the player is actually playing; false in menus, paused, dead
## or on any other break. Repeated calls with the same value are ignored.
func set_gameplay(active: bool) -> void:
	_want_playing = active
	_flush()


func _flush() -> void:
	if not is_ready or _failed:
		return
	if _loading_stop_requested and not _loading_stop_sent:
		_loading_stop_sent = true
		_call("game.loadingStop")
	if _want_playing != _sent_playing:
		_sent_playing = _want_playing
		_call("game.gameplayStart" if _want_playing else "game.gameplayStop")


func _call(method: String) -> void:
	JavaScriptBridge.eval("try { window.CrazyGames.SDK.%s(); } catch (e) {}" % method, true)
