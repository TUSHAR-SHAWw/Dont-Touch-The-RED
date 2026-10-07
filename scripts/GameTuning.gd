extends Node

## Master gameplay tuning.
## Adjust these exported values in Main/GameTuning.
##
## The game is ENDLESS.
## Stage 4 is the final difficulty stage and continues forever.
## Continuous difficulty after Stage 4 is handled by the danger spawner.

# ============================================================
# DANGER TIMING
# ============================================================

@export_group("Danger Timing")

## Starting interval between danger patterns.
@export var danger_spawn_interval: float = 2.2

## How long the warning phase lasts before a danger becomes active.
@export var danger_warning_time: float = 1.2

## How long a danger remains active.
@export var danger_active_time: float = 2.0

## Absolute minimum interval between danger patterns.
## Prevents the endless game from becoming infinitely fast.
@export var danger_min_spawn_interval: float = 0.85

## How quickly the spawn interval decreases as the run continues.
@export var danger_spawn_acceleration: float = 0.025


# ============================================================
# IDLE / ANTI-CAMPING PRESSURE
# ============================================================

## Idle pressure does not begin immediately.
## This gives the player time to start moving naturally.
@export var idle_pressure_start: float = 20.0

## Size of the anti-camping danger zone.
@export var idle_pressure_size: float = 92.0


# ============================================================
# MODE IDENTITY
# ============================================================

@export_group("Mode Identity")

## Rush mode
@export var rush_spawn_multiplier: float = 0.62
@export var rush_warning_multiplier: float = 0.82
@export var rush_active_multiplier: float = 1.10
@export var rush_score_multiplier: float = 1.25

## Zen mode
@export var zen_spawn_multiplier: float = 1.55
@export var zen_warning_multiplier: float = 1.45
@export var zen_active_multiplier: float = 0.90
@export var zen_score_multiplier: float = 0.85


# ============================================================
# COLLECTIBLE TIMING
# ============================================================

@export_group("Collectible Timing")

@export var coin_first_spawn_delay: float = 0.35
@export var coin_spawn_interval: float = 6.0
@export var coin_min_spawn_interval: float = 1.4

@export var powerup_first_spawn_delay: float = 4.0
@export var powerup_spawn_interval: float = 7

## Maximum number of active coins at one time.
@export var max_active_coins: int = 3


# ============================================================
# COLLECTIBLE LIFETIMES
# ============================================================

@export_group("Collectible Lifetimes")

@export var common_coin_lifetime: float = 5.0
@export var rare_coin_lifetime: float = 9.0
@export var epic_coin_lifetime: float = 10.0
@export var powerup_lifetime: float = 10.0


# ============================================================
# SCORING
# ============================================================

@export_group("Scoring")

@export var milestone_interval: float = 10.0
@export var coin_score_value: float = 5.0

@export var score_boost_duration: float = 8.0
@export var magnet_duration: float = 8.0

## Temporary protection after receiving shield protection.
@export var shield_grace_duration: float = 1.0


# ============================================================
# ENDLESS PROGRESSION
# ============================================================

@export_group("Progression")

## Stage 1: 0 seconds onward until threshold.
@export var stage_1_threshold: float = 10.0

## Stage 2 begins here.
@export var stage_2_threshold: float = 30.0

## Stage 3 begins here.
@export var stage_3_threshold: float = 45.0

## Stage 4 begins here and continues FOREVER.
@export var stage_4_threshold: float = 60.0

@export var stage_reward_coins: int = 12
@export var stage_reward_score_bonus: float = 0.5
