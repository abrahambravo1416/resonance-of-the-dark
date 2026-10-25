extends Node

const DEATH_PENALTY: int = 50

var skip_next_intro: bool = false

var total_score: int = 0
var high_score: int = 0
var penalties_count: int = 0
var active_save_slot: int = -1
var current_campaign_level: int = 1
var is_guest_run: bool = true
var current_level_progress: Dictionary = {}
var _progress_level_number: int = 1
var _penalty_applied_this_attempt: bool = false
var _final_penalties_applied: bool = false


func reset_run() -> void:
	total_score = 0
	penalties_count = 0
	active_save_slot = -1
	current_campaign_level = 1
	is_guest_run = true
	current_level_progress.clear()
	_progress_level_number = 1
	_penalty_applied_this_attempt = false
	_final_penalties_applied = false
	skip_next_intro = false


func start_new_campaign(save_slot: int = -1, guest: bool = true) -> void:
	reset_run()
	active_save_slot = clampi(save_slot, -1, 3)
	is_guest_run = guest
	current_campaign_level = 1
	current_level_progress.clear()
	_progress_level_number = 1


func restore_campaign(save: Dictionary, save_slot: int) -> void:
	reset_run()
	var save_data: Variant = save.get("save_data", {})
	if not save_data is Dictionary:
		return
	current_campaign_level = clampi(int(save_data.get("level", save.get("level", 1))), 1, 4)
	total_score = int(save_data.get("score", save.get("score", 0)))
	penalties_count = maxi(0, int(save_data.get("penalties_count", 0)))
	var saved_progress: Variant = save_data.get("level_progress", {})
	if saved_progress is Dictionary:
		current_level_progress = saved_progress.duplicate(true)
	else:
		current_level_progress.clear()
	_progress_level_number = current_campaign_level
	active_save_slot = clampi(save_slot, 1, 3)
	is_guest_run = false
	_penalty_applied_this_attempt = false
	_final_penalties_applied = false


func make_campaign_snapshot(next_level: int, campaign_completed: bool = false) -> Dictionary:
	var safe_level := clampi(next_level, 1, 4)
	if _progress_level_number != safe_level:
		current_level_progress.clear()
		_progress_level_number = safe_level
	current_campaign_level = safe_level
	return {
		"level": current_campaign_level,
		"score": total_score,
		"penalties_count": penalties_count,
		"campaign_completed": campaign_completed,
		"level_progress": current_level_progress.duplicate(true),
	}


func set_level_progress(level_number: int, progress: Dictionary) -> void:
	var safe_level := clampi(level_number, 1, 4)
	current_campaign_level = safe_level
	_progress_level_number = safe_level
	current_level_progress = progress.duplicate(true)


func get_level_progress(level_number: int) -> Dictionary:
	if clampi(level_number, 1, 4) != _progress_level_number:
		return {}
	return current_level_progress.duplicate(true)


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
