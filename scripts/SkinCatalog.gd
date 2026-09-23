extends RefCounted

const SKIN_PATH := "res://assets/f_skins/"

const DEFAULT_SKIN := {
	"name": "Red",
	"cost": 0,
	"texture": "res://assets/f_skins/red.png",
	"body": Color("#e02323"),
	"highlight": Color("#ffb3a7"),
}

# Explicit texture references.
# These are intentionally preloaded so Godot includes them
# in Web exports.
const SKIN_TEXTURES := [
	preload("res://assets/f_skins/red.png"),
	preload("res://assets/f_skins/blue.png"),
	preload("res://assets/f_skins/clock.png"),
	preload("res://assets/f_skins/compus.png"),
	preload("res://assets/f_skins/atom.png"),
	preload("res://assets/f_skins/forest.png"),
	preload("res://assets/f_skins/galaxy.png"),
	preload("res://assets/f_skins/gear.png"),
	preload("res://assets/f_skins/lock.png"),
	preload("res://assets/f_skins/dragon.png"),
	preload("res://assets/f_skins/molten.png"),
	preload("res://assets/f_skins/robot.png"),
	preload("res://assets/f_skins/rune.png"),
	preload("res://assets/f_skins/magma.png"),
	preload("res://assets/f_skins/sunray.png"),
	preload("res://assets/f_skins/plasma.png"),
	preload("res://assets/f_skins/void.png"),
	preload("res://assets/f_skins/diamond.png"),
]

# Costs are kept separately.
# The index must match the skin index.
const COSTS := [
	0,      # red
	50,     # Blue
	75,     # Clock
	100,    # Compus
	150,    # Atom
	300,    # Forest
	350,    # Galaxy
	450,    # Gear
	500,    # Lock
	550,    # Dragon
	550,    # Molten
	650,    # Robot
	700,    # Rune
	750,    # Magma
	800,    # Sunray
	900,    # Plasma
	1000,   # Void
	2000,   # Diamond
]

# Skin names.
# The index must match COSTS and SKIN_TEXTURES.
const SKIN_NAMES := [
	"RED",
	"BLUE",
	"CLOCK",
	"COMPUS",
	"ATOM",
	"FOREST",
	"GALAXY",
	"GEAR",
	"LOCK",
	"DRAGON",
	"MOLTEN",
	"ROBOT",
	"RUNE",
	"MAGMA",
	"SUNRAY",
	"PLASMA",
	"VOID",
	"DIAMOND",
]

# Placeholder body colors.
const BODIES := [
	Color("#ff0000"), # red
	Color("#ffffff"), # Blue
	Color("#0080ff"), # Clock
	Color("#808080"), # Compus
	Color("#00ff00"), # Atom
	Color("#00ffff"), # Forest
	Color("#ff8000"), # Galaxy
	Color("#228b22"), # Gear
	Color("#8000ff"), # Lock
	Color("#ffd900"), # Dragon
	Color("#555555"), # Molten
	Color("#ff4500"), # Robot
	Color("#ee00ff"), # Rune
	Color("#aaaaaa"), # Magma
	Color("#0796a3"), # Sunray
	Color("#ffffff"), # Plasma
	Color("#ffff00"), # Void
	Color("#111111"), # Diamond
]

# Placeholder highlight colors.
const HIGHLIGHTS := [
	Color("#ff5555"), # red
	Color("#eeeeee"), # Blue
	Color("#55aaff"), # Clock
	Color("#cccccc"), # Compus
	Color("#55ff55"), # Atom
	Color("#55ffff"), # Forest
	Color("#ffaa55"), # Galaxy
	Color("#55cc55"), # Gear
	Color("#cc55ff"), # Lock
	Color("#f6ff00"), # Dragon
	Color("#888888"), # Molten
	Color("#ff7755"), # Robot
	Color("#ff00dd"), # Rune
	Color("#dddddd"), # Magma
	Color("#05e1f5"), # Sunray
	Color("#ffffff"), # Plasma
	Color("#ffff88"), # Void
	Color("#555555"), # Diamond
]

# This is what your UIManager uses.
# It contains DICTIONARIES, not strings.
static var SKINS: Array[Dictionary] = []


static func _static_init() -> void:
	_build_skins()


static func _build_skins() -> void:
	SKINS.clear()

	var skin_count := SKIN_NAMES.size()

	for i in range(skin_count):

		var skin_name := str(SKIN_NAMES[i]).strip_edges()

		if skin_name.is_empty():
			push_warning(
				"SkinCatalog: Empty skin name at index %d."
				% i
			)
			continue

		var cost := 0

		if i < COSTS.size():
			cost = maxi(
				0,
				int(COSTS[i])
			)

		var body := Color.WHITE

		if i < BODIES.size():
			body = BODIES[i]

		var highlight := Color.WHITE

		if i < HIGHLIGHTS.size():
			highlight = HIGHLIGHTS[i]

		var file_name := skin_name.to_lower() + ".png"

		var texture_path := SKIN_PATH + file_name

		SKINS.append({
			"name": skin_name,
			"cost": cost,
			"texture": texture_path,
			"body": body,
			"highlight": highlight,
		})

	_validate_catalog()


static func _validate_catalog() -> void:

	if SKINS.is_empty():
		push_warning(
			"SkinCatalog: No skins loaded."
		)
		return

	for i in range(SKINS.size()):

		var skin: Dictionary = SKINS[i]

		if not skin.has("name"):
			push_error(
				"SkinCatalog: Skin %d has no name."
				% i
			)

		if not skin.has("cost"):
			push_error(
				"SkinCatalog: Skin %d has no cost."
				% i
			)

		if not skin.has("texture"):
			push_error(
				"SkinCatalog: Skin %d has no texture."
				% i
			)


static func count() -> int:
	return SKINS.size()


static func get_skin(index: int) -> Dictionary:

	if SKINS.is_empty():
		return DEFAULT_SKIN.duplicate()

	index = clampi(
		index,
		0,
		SKINS.size() - 1
	)

	return SKINS[index].duplicate()


static func get_texture(index: int) -> Texture2D:

	if SKIN_TEXTURES.is_empty():
		return null

	index = clampi(
		index,
		0,
		SKIN_TEXTURES.size() - 1
	)

	return SKIN_TEXTURES[index]


static func get_cost(index: int) -> int:

	var skin := get_skin(index)

	return maxi(
		0,
		int(skin.get("cost", 0))
	)


static func get_name(index: int) -> String:

	var skin := get_skin(index)

	return str(
		skin.get(
			"name",
			DEFAULT_SKIN["name"]
		)
	)


static func get_body_color(index: int) -> Color:

	var skin := get_skin(index)

	return skin.get(
		"body",
		DEFAULT_SKIN["body"]
	)


static func get_highlight_color(index: int) -> Color:

	var skin := get_skin(index)

	return skin.get(
		"highlight",
		DEFAULT_SKIN["highlight"]
	)


static func is_free(index: int) -> bool:
	return get_cost(index) <= 0
