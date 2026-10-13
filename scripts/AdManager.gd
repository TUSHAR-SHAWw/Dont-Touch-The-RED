extends Node

## Rewarded-ad placeholder. NO REAL ADS are shown.
##
## The rest of the game only talks to this node:
##     ads.request_rewarded_ad("revive")
## and listens for `ad_rewarded` / `ad_failed`.
##
## To plug in a real SDK later (e.g. CrazyGames), replace the body of
## _show_ad() and call _finish(true) from the SDK's "ad finished" callback and
## _finish(false, "reason") from its error callback. Nothing else changes.
## Set USE_PLACEHOLDER_UI to false if the SDK draws its own ad screen.

signal ad_started(placement: String)
signal ad_rewarded(placement: String)
signal ad_failed(placement: String, reason: String)

const USE_PLACEHOLDER_UI := true
const PLACEHOLDER_SECONDS := 2.0

var is_showing := false
var enabled := true
var _placement := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_available() -> bool:
	return enabled and not is_showing


func request_rewarded_ad(placement: String) -> void:
	if is_showing:
		return
	if not enabled:
		ad_failed.emit(placement, "disabled")
		return
	is_showing = true
	_placement = placement
	ad_started.emit(placement)
	_show_ad()


func _show_ad() -> void:
	# --- Placeholder: pretend an ad ran, then reward. Replace for real ads. ---
	await get_tree().create_timer(PLACEHOLDER_SECONDS, true, false, true).timeout
	_finish(true)


func _finish(rewarded: bool, reason := "") -> void:
	if not is_showing:
		return
	is_showing = false
	if rewarded:
		ad_rewarded.emit(_placement)
	else:
		ad_failed.emit(_placement, reason)
