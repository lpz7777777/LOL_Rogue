extends Node

var game_mode: String = "practice"

var current_hero: String = "EZ"

var wave_number: int = 1
var enemies_killed: int = 0
var total_play_time: float = 0.0

const GAME_MODE_PRACTICE: String = "practice"
const GAME_MODE_SINGLEPLAYER: String = "singleplayer"


func is_practice_mode() -> bool:
	return game_mode == GAME_MODE_PRACTICE


func is_singleplayer_mode() -> bool:
	return game_mode == GAME_MODE_SINGLEPLAYER


func set_practice_mode() -> void:
	game_mode = GAME_MODE_PRACTICE


func set_singleplayer_mode() -> void:
	game_mode = GAME_MODE_SINGLEPLAYER


func reset_game_stats() -> void:
	wave_number = 1
	enemies_killed = 0
	total_play_time = 0.0


func increment_kill_count() -> void:
	enemies_killed += 1
