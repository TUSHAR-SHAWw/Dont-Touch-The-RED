extends RefCounted

## Single cached ConfigFile. The old code re-read the save file for every
## single value; this loads once and writes only when asked.

const PATH := "user://dttr_config.cfg"

var _cfg := ConfigFile.new()


func load_file() -> void:
	_cfg = ConfigFile.new()
	_cfg.load(PATH) # a missing file is fine: defaults are used


func get_value(section: String, key: String, fallback: Variant) -> Variant:
	return _cfg.get_value(section, key, fallback)


func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)


func save() -> void:
	_cfg.save(PATH)
