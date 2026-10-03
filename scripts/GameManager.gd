extends Node

const DEATH_PENALTY: int = 50

var total_score: int = 0
var high_score: int = 0
var penalties_count: int = 0


func reset_run() -> void:
	total_score = 0
	penalties_count = 0


func add_level_score(seconds_left: int) -> void:
	total_score += maxi(0, seconds_left)


func check_and_update_high_score() -> bool:
	if total_score <= high_score:
		return false
	high_score = total_score
	return true


func apply_penalty() -> void:
	total_score = maxi(0, total_score - DEATH_PENALTY)
	penalties_count += 1


func update_high_score() -> void:
	if total_score > high_score:
		high_score = total_score
