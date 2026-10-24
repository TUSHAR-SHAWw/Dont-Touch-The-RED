extends RefCounted

## Single cached ConfigFile. The old code re-read the save file for every
## single value; this loads once and writes only when asked.

const PATH := "user://dttr_config.cfg"

var _cfg := ConfigFile.new()


func load_file() -> void:
	_cfg = ConfigFile.new()
	_cfg.load(PATH) # a missing file is fine: defaults are used


func get_value(section: String, key: String, fallback: Variant) -> Variant:
	# Check first: Godot logs an error when get_value() gets a null default for a
	# missing key (which is what a brand-new player's empty save looks like).
	if not _cfg.has_section_key(section, key):
		return fallback
	return _cfg.get_value(section, key, fallback)


func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)


func save() -> void:
	_cfg.save(PATH)
