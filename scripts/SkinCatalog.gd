extends RefCounted

## Skin catalog. To add or reorder a skin, edit ENTRIES only: every other list
## (SKINS, SKIN_NAMES, COSTS, ...) is built from it, so they can never drift apart.
##
## Textures are preloaded on purpose so Godot includes them in Web exports.
## The returned skin dictionaries are shared, so treat them as read-only.

## Used when the catalog is empty or an entry is broken.
const DEFAULT_SKIN := {
	"name": "RED",
	"cost": 0,
	"texture": "res://assets/skins/red.png",
	"body": Color("#e02323"),
	"highlight": Color("#ff8b7a"),
}


## One entry per skin; the array index is the skin id used everywhere else.
## `body` tints the motion trail, `highlight` tints the pulse ring. Both are
## chosen to match what the skin's name suggests.
const ENTRIES := [
	{"name": "RED", "cost": 0, "texture": preload("res://assets/skins/red.png"),
		"body": Color("#e02323"), "highlight": Color("#ff8b7a")},

	{"name": "BASEBALL", "cost": 50, "texture": preload("res://assets/skins/base-ball.png"),
		"body": Color("#f5f0df"), "highlight": Color("#ffffff")},

	{"name": "BASKETBALL", "cost": 75, "texture": preload("res://assets/skins/basket-old.png"),
		"body": Color("#d97706"), "highlight": Color("#fed7aa")},

	{"name": "BASKETBALL PRO", "cost": 100, "texture": preload("res://assets/skins/basketball.png"),
		"body": Color("#ea580c"), "highlight": Color("#fdba74")},

	{"name": "FOOTBALL", "cost": 150, "texture": preload("res://assets/skins/footbaall.png"),
		"body": Color("#78350f"), "highlight": Color("#d6a77a")},

	{"name": "VOLLEYBALL", "cost": 200, "texture": preload("res://assets/skins/volley-ball.png"),
		"body": Color("#f8fafc"), "highlight": Color("#dbeafe")},

	{"name": "TENNIS BALL", "cost": 250, "texture": preload("res://assets/skins/tennis-ball.png"),
		"body": Color("#bef264"), "highlight": Color("#ecfccb")},

	{"name": "PX FOOTBALL", "cost": 350, "texture": preload("res://assets/skins/PXfootball.png"),
		"body": Color("#16a34a"), "highlight": Color("#86efac")},

	{"name": "EMOJI", "cost": 500, "texture": preload("res://assets/skins/emoji.png"),
		"body": Color("#facc15"), "highlight": Color("#fef08a")},

	{"name": "DONUT", "cost": 650, "texture": preload("res://assets/skins/dounut.png"),
		"body": Color("#ec4899"), "highlight": Color("#fbcfe8")},

	{"name": "PUMPKIN", "cost": 800, "texture": preload("res://assets/skins/pumpkin.png"),
		"body": Color("#f97316"), "highlight": Color("#fdba74")},

	{"name": "8 BALL", "cost": 1000, "texture": preload("res://assets/skins/8ball.png"),
		"body": Color("#171717"), "highlight": Color("#737373")},

	{"name": "BOMB", "cost": 1250, "texture": preload("res://assets/skins/bomb.png"),
		"body": Color("#292524"), "highlight": Color("#a8a29e")},

	{"name": "GHOST", "cost": 1500, "texture": preload("res://assets/skins/ghost.png"),
		"body": Color("#cbd5e1"), "highlight": Color("#ffffff")},

	{"name": "MAGMA", "cost": 2000, "texture": preload("res://assets/skins/magma.png"),
		"body": Color("#7f1d1d"), "highlight": Color("#ff7a3d")},

	{"name": "DEATH STAR", "cost": 3000, "texture": preload("res://assets/skins/DeathStar.png"),
		"body": Color("#334155"), "highlight": Color("#94a3b8")}
]

## Used by the UI. Each entry is a Dictionary with: name, cost, texture (the
## resource path), body and highlight.
static var SKINS: Array[Dictionary] = []

# Lists derived from ENTRIES, same index as SKINS.
static var SKIN_NAMES: Array[String] = []
static var COSTS: Array[int] = []
static var SKIN_TEXTURES: Array[Texture2D] = []


static func _static_init() -> void:
	_build_skins()


static func _build_skins() -> void:
	SKINS.clear()
	SKIN_NAMES.clear()
	COSTS.clear()
	SKIN_TEXTURES.clear()

	for i in range(ENTRIES.size()):
		var entry: Dictionary = ENTRIES[i]

		# Broken entries keep their slot, so later skins never shift index.
		var skin_name := str(entry.get("name", "")).strip_edges()
		if skin_name.is_empty():
			push_error("SkinCatalog: Skin %d has no name." % i)
			skin_name = "SKIN %d" % i

		var texture := entry.get("texture") as Texture2D
		if texture == null:
			push_error("SkinCatalog: Skin %d (%s) has no texture." % [i, skin_name])

		var cost := maxi(0, int(entry.get("cost", 0)))
		var body: Color = entry.get("body", DEFAULT_SKIN["body"])
		var highlight: Color = entry.get("highlight", DEFAULT_SKIN["highlight"])

		SKINS.append({
			"name": skin_name,
			"cost": cost,
			"texture": texture.resource_path if texture else DEFAULT_SKIN["texture"],
			"body": body,
			"highlight": highlight,
		})
		SKIN_NAMES.append(skin_name)
		COSTS.append(cost)
		SKIN_TEXTURES.append(texture)

	_validate_catalog()


static func _validate_catalog() -> void:
	if SKINS.is_empty():
		push_warning("SkinCatalog: No skins loaded.")
		return
	if SKINS[0]["cost"] != 0:
		push_warning("SkinCatalog: The first skin should be free, it is the starting skin.")
	var seen := {}
	for skin in SKINS:
		var skin_name: String = skin["name"]
		if seen.has(skin_name):
			push_warning("SkinCatalog: Duplicate skin name '%s'." % skin_name)
		seen[skin_name] = true


static func count() -> int:
	return SKINS.size()


static func _clamp_index(index: int) -> int:
	return clampi(index, 0, maxi(0, SKINS.size() - 1))


## Shared dictionary, not a copy: do not modify it.
static func get_skin(index: int) -> Dictionary:
	if SKINS.is_empty():
		return DEFAULT_SKIN
	return SKINS[_clamp_index(index)]


static func get_texture(index: int) -> Texture2D:
	if SKIN_TEXTURES.is_empty():
		return null
	return SKIN_TEXTURES[_clamp_index(index)]


static func get_cost(index: int) -> int:
	return int(get_skin(index).get("cost", 0))


static func get_name(index: int) -> String:
	return str(get_skin(index).get("name", DEFAULT_SKIN["name"]))


static func get_body_color(index: int) -> Color:
	return get_skin(index).get("body", DEFAULT_SKIN["body"])


static func get_highlight_color(index: int) -> Color:
	return get_skin(index).get("highlight", DEFAULT_SKIN["highlight"])


static func is_free(index: int) -> bool:
	return get_cost(index) <= 0
