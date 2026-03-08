extends Node3D

@export_group("Spawn Settings")
@export var spawn_interval: float = 1.5
@export var spawn_radius_min: float = 30.0
@export var spawn_radius_max: float = 50.0
@export var map_half_size: float = 148.0
@export var max_enemies: int = 50
@export var enemies_per_spawn: int = 1

@export_group("Enemy Settings")
@export var enemy_health: float = 70.0  # 基础血量（已提升40%，原50）
@export var enemy_damage: float = 10.0
@export var enemy_speed: float = 3.0

@export_group("Time Scaling")
@export var health_per_minute: float = 0.15
@export var damage_per_minute: float = 0.12

@export_group("Ranged Enemy")
@export var ranged_spawn_chance: float = 0.15

@export_group("Wave Settings")
@export var wave_duration: float = 60.0
@export var enemies_per_wave_increase: int = 5

var _spawn_timer: float = 0.0
var _player: CharacterBody3D = null
var _chaser_scene: PackedScene = null
var _ranged_scene: PackedScene = null
var _active_enemies: Array = []
var _wave_timer: float = 0.0


func _ready() -> void:
	if Global.is_practice_mode():
		print("EnemyManager: Practice mode - no enemies will spawn, keeping dummy enemies")
		set_process(false)
		return
	
	print("EnemyManager: Singleplayer mode - starting enemy spawns")
	_cleanup_dummy_enemies()
	_find_player()
	_load_enemy_scenes()
	_spawn_timer = spawn_interval
	_wave_timer = wave_duration


func _process(delta: float) -> void:
	if Global.is_practice_mode():
		return
	
	Global.total_play_time += delta
	_update_wave(delta)
	_update_spawn_timer(delta)
	_cleanup_dead_enemies()


func _cleanup_dummy_enemies() -> void:
	var enemies_node = get_tree().root.find_child("Enemies", true, false)
	if enemies_node == null:
		enemies_node = get_parent().get_node_or_null("Enemies")
	
	if enemies_node == null:
		print("EnemyManager: No 'Enemies' node found, skipping dummy cleanup")
		return
	
	var enemies_to_remove = []
	for child in enemies_node.get_children():
		if child.is_in_group("enemy"):
			enemies_to_remove.append(child)
	
	for enemy in enemies_to_remove:
		print("EnemyManager: Removing dummy enemy: ", enemy.name)
		enemy.queue_free()
	
	print("EnemyManager: Cleaned up ", enemies_to_remove.size(), " dummy enemies")


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as CharacterBody3D
		print("EnemyManager: Found player at ", str(_player.global_position) if _player else "null")


func _load_enemy_scenes() -> void:
	_chaser_scene = load("res://scenes/chaser_enemy.tscn") as PackedScene
	_ranged_scene = load("res://scenes/ranged_enemy.tscn") as PackedScene
	if _chaser_scene:
		print("EnemyManager: Loaded chaser_enemy.tscn")
	if _ranged_scene:
		print("EnemyManager: Loaded ranged_enemy.tscn")


func _update_wave(delta: float) -> void:
	_wave_timer -= delta
	
	if _wave_timer <= 0:
		Global.wave_number += 1
		_wave_timer = wave_duration
		max_enemies += enemies_per_wave_increase
		print("EnemyManager: Wave ", Global.wave_number, " started! Max enemies: ", max_enemies)


func _update_spawn_timer(delta: float) -> void:
	_spawn_timer -= delta
	
	if _spawn_timer <= 0:
		_spawn_timer = spawn_interval
		_spawn_enemies()


func _spawn_enemies() -> void:
	if _player == null:
		_find_player()
		if _player == null:
			return
	
	var current_enemy_count = _get_active_enemy_count()
	if current_enemy_count >= max_enemies:
		return
	
	for i in range(enemies_per_spawn):
		if _get_active_enemy_count() >= max_enemies:
			break
		_spawn_single_enemy()


func _get_time_scale_multipliers() -> Dictionary:
	var minutes = Global.total_play_time / 60.0
	var health_mult = 1.0 + minutes * health_per_minute
	var damage_mult = 1.0 + minutes * damage_per_minute
	return {"health": health_mult, "damage": damage_mult}


func _spawn_single_enemy() -> void:
	var spawn_position = _get_spawn_position()
	var mults = _get_time_scale_multipliers()
	var scaled_health = enemy_health * mults.health
	var scaled_damage = enemy_damage * mults.damage
	
	var enemy: CharacterBody3D
	var is_ranged = _ranged_scene != null and randf() < ranged_spawn_chance
	
	if is_ranged and _ranged_scene:
		enemy = _ranged_scene.instantiate() as CharacterBody3D
	else:
		if _chaser_scene:
			enemy = _chaser_scene.instantiate() as CharacterBody3D
		else:
			enemy = _create_enemy_direct()
	
	if enemy == null:
		print("EnemyManager: Failed to create enemy!")
		return
	
	add_child(enemy)
	enemy.global_position = spawn_position
	
	if enemy.has_method("set_max_health"):
		enemy.set_max_health(scaled_health)
	
	if enemy.has_method("set_contact_damage") and enemy.has_method("set_attack_damage"):
		enemy.set_contact_damage(scaled_damage)
		enemy.set_attack_damage(scaled_damage * 0.8)
	elif enemy.has_method("set_beam_damage"):
		enemy.set_beam_damage(scaled_damage * 1.2)
	
	_active_enemies.append(enemy)
	var type_str = "Ranged" if is_ranged else "Chaser"
	print("EnemyManager: Spawned ", type_str, " (HP:", int(scaled_health), " DMG:", snapped(scaled_damage, 0.1), ") at ", spawn_position)


func _create_enemy_direct() -> CharacterBody3D:
	var enemy = CharacterBody3D.new()
	enemy.name = "ChaserEnemy"
	enemy.collision_layer = 2
	enemy.collision_mask = 1 | 4
	
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	enemy.add_child(collision)
	
	var nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	enemy.add_child(nav_agent)
	
	var detection = Area3D.new()
	detection.name = "DetectionArea"
	detection.collision_layer = 0
	detection.collision_mask = 4
	var detection_collision = CollisionShape3D.new()
	var detection_sphere = SphereShape3D.new()
	detection_sphere.radius = 1.0
	detection_collision.shape = detection_sphere
	detection.add_child(detection_collision)
	enemy.add_child(detection)
	
	var skill_mgr_script = load("res://scripts/chaser_enemy_skill_manager.gd")
	if skill_mgr_script:
		var skill_mgr = Node3D.new()
		skill_mgr.name = "ChaserEnemySkillManager"
		skill_mgr.set_script(skill_mgr_script)
		enemy.add_child(skill_mgr)
	
	var script = load("res://scripts/chaser_enemy.gd")
	if script:
		enemy.set_script(script)
	
	return enemy


func _get_spawn_position() -> Vector3:
	if _player == null:
		return Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
	
	var angle = randf() * TAU
	var radius = randf_range(spawn_radius_min, spawn_radius_max)
	
	var offset = Vector3(cos(angle), 0, sin(angle)) * radius
	var spawn_pos = _player.global_position + offset
	
	spawn_pos.x = clamp(spawn_pos.x, -map_half_size, map_half_size)
	spawn_pos.z = clamp(spawn_pos.z, -map_half_size, map_half_size)
	spawn_pos.y = 0
	
	return spawn_pos


func _get_active_enemy_count() -> int:
	var count = 0
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			count += 1
	return count


func _cleanup_dead_enemies() -> void:
	var valid_enemies = []
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			valid_enemies.append(enemy)
	_active_enemies = valid_enemies


func get_enemy_count() -> int:
	return _get_active_enemy_count()


func clear_all_enemies() -> void:
	for enemy in _active_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active_enemies.clear()
