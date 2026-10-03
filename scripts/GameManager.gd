extends Node

const DEATH_PENALTY: int = 50

var total_score: int = 0
var high_score: int = 0
var penalties_count: int = 0
var _penalty_applied_this_attempt: bool = false
var _final_penalties_applied: bool = false


func reset_run() -> void:
	total_score = 0
	penalties_count = 0
	_penalty_applied_this_attempt = false
	_final_penalties_applied = false


func begin_level_attempt() -> void:
	# A restarted/reloaded level is a new attempt and can incur its own penalty.
	_penalty_applied_this_attempt = false


func add_level_score(seconds_left: int) -> void:
	total_score += maxi(0, seconds_left)


func get_total_penalty_points() -> int:
	return penalties_count * DEATH_PENALTY


func check_and_update_high_score() -> bool:
	finalize_run_score()
	if total_score <= high_score:
		return false
	high_score = total_score
	return true


func apply_penalty() -> void:
	# Death and timeout can overlap in the same frame; charge only once for that
	# attempt, then re-arm the penalty when the next level attempt starts. Keep
	# the deduction pending until the final victory screen at the end of Level 4.
	if _penalty_applied_this_attempt:
		return
	_penalty_applied_this_attempt = true
	penalties_count += 1


func finalize_run_score() -> void:
	if _final_penalties_applied:
		return
	total_score -= get_total_penalty_points()
	_final_penalties_applied = true


func update_high_score() -> void:
	finalize_run_score()
	if total_score > high_score:
		high_score = total_score
