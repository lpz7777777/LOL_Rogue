extends CharacterBody3D
class_name RangedEnemy

## 远程射线敌人：保持距离并向玩家发射射线攻击

@export_group("Movement")
@export var move_speed: float = 2.0
@export var preferred_range: float = 24.0  # 移动目标距离，需小于攻击射程（由 SkillManager 管理）
@export var rotation_speed: float = 6.0

@export_group("Combat")
@export var max_health: float = 56.0  # 基础血量（已提升40%，原40）

@export_group("Visual")
@export var body_color: Color = Color(0.4, 0.2, 0.9, 1.0)
@export var hit_flash_color: Color = Color.WHITE

@export_group("Health Bar")
@export var show_health_bar: bool = true
@export var health_bar_width: float = 20.0
@export var health_bar_height: float = 1.5
@export var health_bar_offset: float = 5.0
@export var health_bar_background_color: Color = Color(0.15, 0.15, 0.15, 0.9)
@export var health_bar_fill_color: Color = Color(0.5, 0.2, 0.9, 1.0)
@export var health_bar_border_color: Color = Color(0.0, 0.0, 0.0, 1.0)

@export var exp_reward: float = 30.0
@export var gold_reward: int = 25  # 击杀奖励金币

@export_group("Animation")
@export var anim_idle: String = "jhin_run01_anm"
@export var anim_run: String = "jhin_run01_anm"
@export var anim_attacks: Array[String] = ["jhin_attack1_anm", "jhin_attack2_anm", "jhin_attack3_anm", "jhin_attack4_anm"]
@export var anim_death: String = "jhin_death_anm"

var current_health: float = max_health
var _target_player: CharacterBody3D = null
var _is_dead: bool = false
var _hit_flash_timer: float = 0.0
var _original_material: StandardMaterial3D = null
var _mesh_instance: MeshInstance3D = null
var _model_meshes: Array[MeshInstance3D] = []  # Caitlyn 模型内的所有 mesh，用于受击闪白

var navigation_agent: NavigationAgent3D = null
var _skill_manager: Node = null
var _health_bar: Control = null
var _health_bar_fill: ColorRect = null

var _animation_player: AnimationPlayer = null
var _animation_tree: AnimationTree = null
var _anim_playback: AnimationNodeStateMachinePlayback = null
var _attack_node: AnimationNodeAnimation = null
var _attack_index: int = 0
var _is_attacking: bool = false


func _ready() -> void:
	add_to_group("enemy")
	current_health = max_health
	
	navigation_agent = get_node_or_null("NavigationAgent3D")
	if navigation_agent == null:
		await get_tree().process_frame
		navigation_agent = get_node_or_null("NavigationAgent3D")
	
	_skill_manager = get_node_or_null("RangedEnemySkillManager")
	_find_player()
	_setup_navigation()
	_create_visual()
	_create_health_bar()
	_setup_animation()


func _setup_navigation() -> void:
	if navigation_agent:
		navigation_agent.path_desired_distance = 1.0
		navigation_agent.target_desired_distance = 1.5  # 需接近目标点（攻击距离处）才算到达
		navigation_agent.avoidance_enabled = true
		navigation_agent.radius = 0.4
		navigation_agent.height = 1.6


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target_player = players[0] as CharacterBody3D


func _create_visual() -> void:
	if has_node("Visual"):
		_mesh_instance = null
		_original_material = StandardMaterial3D.new()
		_original_material.albedo_color = body_color
		_find_all_mesh_instances(get_node("Visual"), _model_meshes)
		return
	
	# 回退：无模型时用简易胶囊
	var body = CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.4
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = body
	_original_material = StandardMaterial3D.new()
	_original_material.albedo_color = body_color
	_mesh_instance.material_override = _original_material
	add_child(_mesh_instance)
	_mesh_instance.position.y = 0.7
	
	var head = MeshInstance3D.new()
	var head_mesh = CylinderMesh.new()
	head_mesh.top_radius = 0.2
	head_mesh.bottom_radius = 0.2
	head_mesh.height = 0.4
	head.mesh = head_mesh
	head.material_override = _original_material
	head.rotation.x = PI / 2
	add_child(head)
	head.position = Vector3(0, 1.2, -0.3)


func _create_health_bar() -> void:
	if not show_health_bar:
		return
	
	var billboard = Node3D.new()
	billboard.name = "HealthBarAnchor"
	billboard.position = Vector3(0, health_bar_offset, 0)
	add_child(billboard)
	
	var sprite = Sprite3D.new()
	sprite.name = "HealthBarSprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.fixed_size = true
	sprite.pixel_size = 0.01
	sprite.render_priority = 10
	sprite.texture = await _create_health_bar_texture()
	billboard.add_child(sprite)


func _create_health_bar_texture() -> Texture2D:
	var border_size = 1
	var vp_w = int(health_bar_width) + border_size * 2
	var vp_h = int(health_bar_height) + border_size * 2
	
	var viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(vp_w, vp_h)
	
	var container = Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(container)
	
	var border_rect = ColorRect.new()
	border_rect.color = health_bar_border_color
	border_rect.custom_minimum_size = Vector2(vp_w, vp_h)
	border_rect.position = Vector2(0, 0)
	container.add_child(border_rect)
	
	var background = ColorRect.new()
	background.color = health_bar_background_color
	background.custom_minimum_size = Vector2(health_bar_width, health_bar_height)
	background.position = Vector2(border_size, border_size)
	border_rect.add_child(background)
	
	_health_bar_fill = ColorRect.new()
	_health_bar_fill.color = health_bar_fill_color
	_health_bar_fill.custom_minimum_size = Vector2(health_bar_width, health_bar_height)
	_health_bar_fill.position = Vector2(0, 0)
	background.add_child(_health_bar_fill)
	
	_health_bar = container
	
	add_child(viewport)
	await get_tree().process_frame
	
	return viewport.get_texture()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	
	_update_hit_flash(delta)
	_update_ranged_animation()
	
	if _health_bar and _health_bar_fill:
		_health_bar_fill.custom_minimum_size.x = health_bar_width * get_health_percent()
	
	if _target_player == null or not is_instance_valid(_target_player):
		_find_player()
		if _target_player == null:
			return
	
	if not _is_attacking and _skill_manager and not _skill_manager.is_on_cooldown():
		_try_fire_beam()
	
	if _is_attacking:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	_update_movement(delta)


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_timer > 0:
		_hit_flash_timer -= delta
		var progress = 1.0 - (_hit_flash_timer / 0.15)
		if _mesh_instance and _original_material:
			_original_material.albedo_color = body_color.lerp(hit_flash_color, 0.5 * (1.0 - progress))
		elif _model_meshes.size() > 0:
			var mat = _model_meshes[0].material_override
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color = body_color.lerp(hit_flash_color, 0.5 * (1.0 - progress))
		if _hit_flash_timer <= 0:
			if _original_material:
				_original_material.albedo_color = body_color
			for mesh in _model_meshes:
				mesh.material_override = null


func _get_attack_range() -> float:
	"""从 SkillManager 获取攻击射程"""
	if _skill_manager != null and _skill_manager is RangedEnemySkillManager:
		return _skill_manager.projectile_range
	return 16.0  # 默认射程（SkillManager 同默认值）


func _try_fire_beam() -> void:
	if _skill_manager == null or _target_player == null or not is_instance_valid(_target_player):
		return
	
	var to_player = _target_player.global_position - global_position
	to_player.y = 0
	var dist_2d = to_player.length()
	
	if dist_2d > _get_attack_range():
		_update_movement_only()
		return
	
	# 转向玩家
	var look_dir = to_player.normalized()
	rotation.y = atan2(look_dir.x, look_dir.z)
	
	if _skill_manager.try_fire_beam(self, _target_player):
		_is_attacking = true
		_play_attack_animation()


func _update_movement(delta: float) -> void:
	if _target_player == null or not is_instance_valid(_target_player):
		return
	
	var to_player = _target_player.global_position - global_position
	to_player.y = 0
	var dist = to_player.length()
	
	# 在攻击范围内时停止移动，直接站定攻击
	var attack_range = _get_attack_range()
	if dist <= attack_range:
		velocity = Vector3.ZERO
		velocity.y = -5.0 if not is_on_floor() else 0.0
		move_and_slide()
		# 转向玩家
		if to_player.length_squared() > 0.001:
			rotation.y = atan2(to_player.x, to_player.z)
		return
	
	# 直接朝目标点移动（不用导航，避免路径绕到玩家脚下）
	# 目标点 = 玩家与敌人连线上、距玩家 attack_range 的点
	var flat_to_player = to_player.normalized()  # 敌人->玩家
	var target_pos = _target_player.global_position - flat_to_player * attack_range
	target_pos.y = 0
	
	var move_dir = (target_pos - global_position)
	move_dir.y = 0
	move_dir = move_dir.normalized()
	
	# 若已接近目标点则减速避免 overshoot
	var dist_to_target = (target_pos - global_position).length()
	if dist_to_target < 2.0:
		velocity = move_dir * move_speed * (dist_to_target / 2.0)
	else:
		velocity = move_dir * move_speed
	
	velocity.y = -5.0 if not is_on_floor() else 0.0
	move_and_slide()
	
	if Vector2(velocity.x, velocity.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(move_dir.x, move_dir.z), rotation_speed * delta)


func _update_movement_only() -> void:
	_update_movement(get_physics_process_delta_time())


func _setup_animation() -> void:
	_animation_player = _find_animation_player_recursive(self)
	if _animation_player == null:
		return
	
	var anim_list: PackedStringArray = []
	for lib_name in _animation_player.get_animation_library_list():
		var lib = _animation_player.get_animation_library(lib_name)
		if lib:
			for a in lib.get_animation_list():
				var full = str(a) if str(lib_name) == "" else str(lib_name) + "/" + str(a)
				anim_list.append(full)
	
	_animation_tree = AnimationTree.new()
	_animation_tree.name = "RangedAnimTree"
	add_child(_animation_tree)
	_animation_tree.anim_player = _animation_tree.get_path_to(_animation_player)
	
	var sm = AnimationNodeStateMachine.new()
	var node_idle = AnimationNodeAnimation.new()
	node_idle.animation = anim_idle
	var node_run = AnimationNodeAnimation.new()
	node_run.animation = anim_run
	_attack_node = AnimationNodeAnimation.new()
	_attack_node.animation = anim_attacks[0] if anim_attacks.size() > 0 else anim_idle
	
	sm.add_node("Idle", node_idle, Vector2(100, 0))
	sm.add_node("Run", node_run, Vector2(100, 80))
	sm.add_node("Attack", _attack_node, Vector2(100, 160))
	
	var make_t = func(xfade: float) -> AnimationNodeStateMachineTransition:
		var t = AnimationNodeStateMachineTransition.new()
		t.xfade_time = xfade
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		return t
	for from_s in ["Idle", "Run", "Attack"]:
		for to_s in ["Idle", "Run", "Attack"]:
			if from_s != to_s:
				sm.add_transition(from_s, to_s, make_t.call(0.15))
	
	_animation_tree.tree_root = sm
	_animation_tree.active = true
	_anim_playback = _animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _anim_playback:
		_anim_playback.travel("Idle")
	_animation_tree.animation_finished.connect(_on_anim_finished)
	
	_set_animation_loop(anim_idle, Animation.LOOP_LINEAR)
	_set_animation_loop(anim_run, Animation.LOOP_LINEAR)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found = _find_animation_player_recursive(child)
		if found:
			return found
	return null


func _set_animation_loop(anim_name: String, loop_mode: Animation.LoopMode) -> void:
	if _animation_player == null:
		return
	for lib_name in _animation_player.get_animation_library_list():
		var lib = _animation_player.get_animation_library(lib_name)
		if lib and lib.has_animation(anim_name):
			lib.get_animation(anim_name).loop_mode = loop_mode
			return


func _update_ranged_animation() -> void:
	if _anim_playback == null:
		return
	var cur = _anim_playback.get_current_node()
	if cur == "Attack":
		return
	var speed_2d = Vector2(velocity.x, velocity.z).length()
	var next_state = "Run" if speed_2d > 0.1 else "Idle"
	if cur != next_state:
		_anim_playback.travel(next_state)


func _play_attack_animation() -> void:
	if _anim_playback == null or _attack_node == null or anim_attacks.is_empty():
		_is_attacking = false
		return
	_attack_node.animation = anim_attacks[_attack_index]
	_attack_index = (_attack_index + 1) % anim_attacks.size()
	_anim_playback.start("Attack")


func _on_anim_finished(_anim_name: StringName) -> void:
	if _anim_playback == null:
		return
	var cur = _anim_playback.get_current_node()
	if cur == "Attack":
		_is_attacking = false
		_anim_playback.travel("Idle")


func _trigger_hit_flash() -> void:
	_hit_flash_timer = 0.15
	if _mesh_instance and _original_material:
		_original_material.albedo_color = hit_flash_color
	elif _model_meshes.size() > 0:
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = hit_flash_color
		flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for mesh in _model_meshes:
			mesh.material_override = flash_mat


func _find_all_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_all_mesh_instances(child, result)


func take_damage(amount: float) -> void:
	current_health -= amount
	if current_health > 0:
		_trigger_hit_flash()
	if _health_bar_fill:
		_health_bar_fill.custom_minimum_size.x = health_bar_width * get_health_percent()
	
	if current_health <= 0:
		die()


func get_health_percent() -> float:
	return clamp(current_health / max_health, 0.0, 1.0)


func set_max_health(value: float) -> void:
	max_health = value
	current_health = max_health


func set_beam_damage(value: float) -> void:
	if _skill_manager:
		_skill_manager.set_beam_damage(value)


func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	Global.increment_kill_count()
	PlayerInventory.add_gold(gold_reward)
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0].has_method("add_experience"):
		players[0].add_experience(exp_reward)
	
	remove_from_group("enemy")
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	
	var hp_anchor = get_node_or_null("HealthBarAnchor")
	if hp_anchor:
		hp_anchor.visible = false
	
	if _animation_tree:
		_animation_tree.active = false
	if _animation_player and _animation_player.has_animation(anim_death):
		_animation_player.play(anim_death)
		await get_tree().create_timer(2.5).timeout
	if is_instance_valid(self):
		queue_free()
