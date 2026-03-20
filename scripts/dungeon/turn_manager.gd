extends Node
## Central turn orchestrator (Autoload singleton).
##
## Turn phases run in order each time the player consumes a turn:
##   1. PLAYER_ACTION  — player has already moved/attacked (action_speed passed in).
##   2. ENEMY_PHASE    — all enemies react (listeners run simultaneously).
##   3. TURN_END       — status ticks, traps trigger, hunger, etc.
##
## Any system that needs to participate in turns just connects to the
## appropriate signal — no references to other systems required.

signal player_turn_ended(action_speed: float)
signal enemy_phase_started(action_speed: float)
signal enemy_phase_finished
signal turn_ended(turn_number: int)

var turn_count: int = 0

func end_player_turn(action_speed: float) -> void:
	turn_count += 1
	player_turn_ended.emit(action_speed)
	enemy_phase_started.emit(action_speed)

func finish_enemy_phase() -> void:
	enemy_phase_finished.emit()
	turn_ended.emit(turn_count)

func reset() -> void:
	turn_count = 0
