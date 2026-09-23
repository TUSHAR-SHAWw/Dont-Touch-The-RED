extends Node

## Master gameplay tuning. Adjust these exported values in Main/GameTuning.

@export_group("Danger Timing")
@export var danger_spawn_interval := 2.2
@export var danger_warning_time := 1
@export var danger_active_time := 2.0
@export var danger_min_spawn_interval := 0.85
@export var danger_spawn_acceleration := 0.030
@export var idle_pressure_start := 14.0
@export var idle_pressure_size := 100.0

@export_group("Mode Identity")
@export var rush_spawn_multiplier := 0.62
@export var rush_warning_multiplier := 0.82
@export var rush_active_multiplier := 1.1
@export var zen_spawn_multiplier := 1.55
@export var zen_warning_multiplier := 1.45
@export var zen_active_multiplier := 0.9
@export var rush_score_multiplier := 1.25
@export var zen_score_multiplier := 0.85

@export_group("Collectible Timing")
@export var coin_first_spawn_delay := 0.35
@export var coin_spawn_interval := 3.6
@export var coin_min_spawn_interval := 1.4
@export var powerup_first_spawn_delay := 8.0
@export var powerup_spawn_interval := 12.0
@export var max_active_coins := 3

@export_group("Collectible Lifetimes")
@export var common_coin_lifetime := 9.0
@export var rare_coin_lifetime := 12.0
@export var epic_coin_lifetime := 15.0
@export var powerup_lifetime := 12.0

@export_group("Scoring")
@export var milestone_interval := 10.0
@export var coin_score_value := 5.0
@export var score_boost_duration := 8.0
@export var magnet_duration := 8.0
@export var shield_grace_duration := 0.6
