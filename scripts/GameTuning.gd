extends Node

## Master gameplay tuning.
## Adjust these exported values in Main/GameTuning.
##
## The game is ENDLESS.
## Difficulty rises slowly: the first minute is gentle (few, easy patterns with
## long warnings), new patterns unlock one at a time, and everything reaches full
## strength around `difficulty_ramp_time`. Stage 4 continues forever, and warnings
## keep getting a little shorter after the ramp (see `late_warning_floor`).

# ============================================================
# DANGER TIMING
# ============================================================

@export_group("Danger Timing")

## Interval between danger patterns at the very start of a run.
@export var danger_spawn_interval: float = 3.4

## Warning time once the ramp is finished (seconds before a danger turns lethal).
@export var danger_warning_time: float = 1.2

## How long a danger stays active once the ramp is finished.
@export var danger_active_time: float = 2.0

## Absolute minimum interval between danger patterns.
## Prevents the endless game from becoming infinitely fast.
@export var danger_min_spawn_interval: float = 0.85

## Seconds shaved off the spawn interval per second survived.
## 3.4s -> 0.85s takes (3.4 - 0.85) / 0.014 = about 180 seconds.
@export var danger_spawn_acceleration: float = 0.014


# ============================================================
# DIFFICULTY RAMP
# ============================================================

@export_group("Difficulty Ramp")

## Seconds until warnings and active times reach their normal values.
@export var difficulty_ramp_time: float = 180.0

## Extra warning seconds at the start of a run; fades to 0 over the ramp.
@export var start_warning_bonus: float = 0.7

## Danger active time at the start of a run, as a fraction of normal (rises to 1.0).
@export_range(0.3, 1.0, 0.05) var start_active_scale: float = 0.7

## After the ramp, warnings keep shrinking towards this fraction of normal
## over another `difficulty_ramp_time` seconds, then stay there (endless pressure).
@export_range(0.4, 1.0, 0.05) var late_warning_floor: float = 0.8


# ============================================================
# IDLE / ANTI-CAMPING PRESSURE
# ============================================================

@export_group("Idle Pressure")

## Idle pressure does not begin immediately.
## This gives the player time to start moving naturally.
@export var idle_pressure_start: float = 40.0

## Size of the anti-camping danger zone.
@export var idle_pressure_size: float = 80.0


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

@export var coin_first_spawn_delay: float = 4
@export var coin_spawn_interval: float = 10.0
@export var coin_min_spawn_interval: float = 1.4

@export var powerup_first_spawn_delay: float = 6.0
@export var powerup_spawn_interval: float = 15.0

## Maximum number of active coins at one time.
@export var max_active_coins: int = 3


# ============================================================
# COLLECTIBLE LIFETIMES
# ============================================================

@export_group("Collectible Lifetimes")

@export var common_coin_lifetime: float = 5.0
@export var rare_coin_lifetime: float = 7.0
@export var epic_coin_lifetime: float = 10.0
@export var powerup_lifetime: float = 5.0


# ============================================================
# SCORING
# ============================================================

@export_group("Scoring")

@export var milestone_interval: float = 30.0
@export var coin_score_value: float = 5.0

@export var score_boost_duration: float = 8.0
@export var magnet_duration: float = 8.0

## Temporary protection after receiving shield protection.
@export var shield_grace_duration: float = 1.0


# ============================================================
# ENDLESS PROGRESSION
# ============================================================

@export_group("Progression")

## Stage banners and rewards. New danger patterns unlock on their own schedule
## (PATTERN_UNLOCKS in DangerManager.gd), spread between these times.

## Stage 1: from 0 seconds until this time.
@export var stage_1_threshold: float = 45.0

## Stage 2 begins here.
@export var stage_2_threshold: float = 90.0

## Stage 3 begins here.
@export var stage_3_threshold: float = 140.0

## Stage 4 begins here and continues FOREVER.
@export var stage_4_threshold: float = 200.0

@export var stage_reward_coins: int = 3
@export var stage_reward_score_bonus: float = 0.5


# ============================================================
# GEMS & REVIVE
# ============================================================

@export_group("Gems & Revive")

## Gems spent per revive.
@export var gem_revive_cost: int = 1

## Maximum revives in a single run (stops endless gem/ad farming).
@export var max_revives_per_run: int = 2

## Seconds the player has to decide on the revive prompt.
@export var revive_prompt_seconds: float = 6.0

## Invulnerability after a revive (seconds).
@export var revive_grace_duration: float = 2.5

## Pause before the next danger pattern after a revive.
@export var revive_pattern_delay: float = 1.6

## Gems granted per completed rewarded ad.
@export var ad_gem_reward: int = 1
