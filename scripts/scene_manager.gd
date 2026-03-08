extends Node

var _current_hero: String = ""

const MAIN_MENU_SCENE: String = "res://scenes/MainMenu.tscn"
const HERO_SELECT_SCENE: String = "res://scenes/HeroSelect.tscn"
const GAME_SCENE: String = "res://scenes/main.tscn"

const HERO_SCENES: Dictionary = {
	"Ezreal": "res://scenes/Ezreal.tscn",
	"Yasuo": "res://scenes/Yasuo.tscn"
}


func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func go_to_hero_select() -> void:
	get_tree().change_scene_to_file(HERO_SELECT_SCENE)


func go_to_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func go_to_game_with_hero(hero_name: String) -> void:
	_current_hero = hero_name
	Global.current_hero = hero_name
	get_tree().change_scene_to_file(GAME_SCENE)


func get_current_hero() -> String:
	return _current_hero


func set_current_hero(hero_name: String) -> void:
	_current_hero = hero_name


func get_hero_scene_path(hero_name: String) -> String:
	if HERO_SCENES.has(hero_name):
		return HERO_SCENES[hero_name]
	return HERO_SCENES["Ezreal"]


func restart_game() -> void:
	_current_hero = ""
	go_to_main_menu()
