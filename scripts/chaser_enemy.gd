extends CharacterBody3D
class_name ChaserEnemy

@export_group("Movement")
@export var move_speed: float = 3.0
@export var acceleration: float = 8.0
@export var rotation_speed: float = 8.0

@export_group("Combat")
@export var max_health: float = 70.0  # 基础血量（已提升40%，原50）

@export_group("Visual")
@export var body_color: Color = Color(0.8, 0.2, 0.2, 1.0)
@export var hit_flash_color: Color = Color.WHITE

@export_group("Animation")
@export var anim_idle: String = "alistar_idle1_anm"
@export var anim_run: String = "alistar_run_anm"
@export var anim_attacks: Array[String] = ["alistar_attack1_anm", "alistar_attack2_anm"]

@export_group("Health Bar")
@export var show_health_bar: bool = true
@export var health_bar_width: float = 20.0
@export var health_bar_height: float = 1.5
@export var health_bar_offset: float = 5.0
@export var health_bar_background_color: Color = Color(0.15, 0.15, 0.15, 0.9)
@export var health_bar_fill_color: Color = Color(0.8, 0.15, 0.15, 1.0)
@export var health_bar_border_color: Color = Color(0.0, 0.0, 0.0, 1.0)

var navigation_agent: NavigationAgent3D = null

var current_health: float = max_health
var _target_player: CharacterBody3D = null
var _hit_flash_timer: float = 0.0
var _original_material: StandardMaterial3D = null
var _mesh_instance: MeshInstance3D = null
var _model_meshes: Array[MeshInstance3D] = []  # Visual 模型内的所有 mesh，用于受击闪白

var _health_bar: Control = null
var _health_bar_fill: ColorRect = null

var _airborne: bool = false
var _airborne_timer: float = 0.0
var _original_y: float = 0.0

var _animation_player: AnimationPlayer = null
var _animation_tree: AnimationTree = null
var _anim_playback: AnimationNodeStateMachinePlayback = null
var _attack_node: AnimationNodeAnimation = null
var _attack_index: int = 0
var _is_attacking: bool = false
var _is_dead: bool = false

var _skill_manager: Node = null


func _ready() -> void:
	add_to_group("enemy")
	current_health = max_health
	
	# 核心修复：延迟获取或使用 get_node_or_null
	navigation_agent = get_node_or_null("NavigationAgent3D")
	
	# 如果是动态创建的，可能需要等一帧
	if navigation_agent == null:
		await get_tree().process_frame
		navigation_agent = get_node_or_null("NavigationAgent3D")
	
	_skill_manager = get_node_or_null("ChaserEnemySkillManager")
	_find_player()
	_setup_navigation()
	_create_visual()
	_create_health_bar()
	_setup_animation()
	
	if navigation_agent:
		navigation_agent.velocity_computed.connect(_on_velocity_computed)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_update_hit_flash(delta)
	_update_airborne(delta)
	_update_chaser_animation()
	
	if _health_bar:
		_update_health_bar_display()
	
	if _airborne:
		return
	
	if _target_player == null or not is_instance_valid(_target_player):
		_find_player()
		if _target_player == null:
			return
	
	_update_attack(delta)
	
	if _is_attacking:
		velocity = Vector3.ZERO
		move_and_slide()
		_check_player_contact_after_slide()
		return
	
	_update_navigation_target()
	_move_towards_player(delta)


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target_player = players[0] as CharacterBody3D


func _setup_navigation() -> void:
	if navigation_agent == null:
		return
	
	navigation_agent.path_desired_distance = 0.5
	navigation_agent.target_desired_distance = 0.5
	navigation_agent.avoidance_enabled = true
	navigation_agent.radius = 0.4
	navigation_agent.height = 1.8


func _create_visual() -> void:
	if has_node("Visual"):
		_mesh_instance = null
		_original_material = StandardMaterial3D.new()
		_original_material.albedo_color = body_color
		_find_all_mesh_instances(get_node("Visual"), _model_meshes)
		return
	
	var body = CapsuleMesh.new()
	body.radius = 0.45
	body.height = 1.6
	
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = body
	
	_original_material = StandardMaterial3D.new()
	_original_material.albedo_color = body_color
	_mesh_instance.material_override = _original_material
	
	add_child(_mesh_instance)
	_mesh_instance.position.y = 0.8
	
	var head = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.3
	head_mesh.height = 0.6
	head.mesh = head_mesh
	head.material_override = _original_material
	add_child(head)
	head.position.y = 1.8


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


func _update_health_bar_display() -> void:
	if _health_bar_fill == null:
		return
	_health_bar_fill.custom_minimum_size.x = health_bar_width * get_health_percent()


func _update_navigation_target() -> void:
	if navigation_agent and _target_player:
		navigation_agent.set_target_position(_target_player.global_position)


func _move_towards_player(delta: float) -> void:
	if navigation_agent == null:
		return
	
	if navigation_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		_check_player_contact_after_slide()
		return
	
	var next_position = navigation_agent.get_next_path_position()
	var direction = (next_position - global_position).normalized()
	direction.y = 0
	
	var target_velocity = direction * move_speed
	velocity = velocity.lerp(target_velocity, acceleration * delta)
	
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0
	
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(velocity)
	else:
		_apply_movement_and_rotation(delta)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if _is_dead:
		return
	velocity = safe_velocity
	_apply_movement_and_rotation(get_physics_process_delta_time())


func _apply_movement_and_rotation(delta: float) -> void:
	move_and_slide()
	_check_player_contact_after_slide()
	
	var horizontal_velocity = Vector2(velocity.x, velocity.z)
	if horizontal_velocity.length() > 0.1:
		var target_rotation = atan2(velocity.x, velocity.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)


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


func take_damage(amount: float) -> void:
	current_health -= amount
	if current_health > 0:
		_trigger_hit_flash()
	_update_health_bar_display()
	
	print("[", name, "] took ", amount, " damage, remaining health: ", current_health)
	
	if current_health <= 0:
		die()


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


@export var exp_reward: float = 25.0

func die() -> void:
	if _is_dead:
		return
	_is_dead = true
	print("[", name, "] ChaserEnemy died!")
	Global.increment_kill_count()
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0].has_method("add_experience"):
		players[0].add_experience(exp_reward)
	
	remove_from_group("enemy")
	velocity = Vector3.ZERO
	move_and_slide()
	
	collision_layer = 0
	collision_mask = 0
	
	var hp_anchor = get_node_or_null("HealthBarAnchor")
	if hp_anchor:
		hp_anchor.visible = false
	
	if _animation_tree:
		_animation_tree.active = false
	if _animation_player:
		_animation_player.play("alistar_death_anm")
	
	await get_tree().create_timer(2.5).timeout
	if not is_instance_valid(self):
		return
	_fade_and_destroy()


func _fade_and_destroy() -> void:
	var meshes: Array[MeshInstance3D] = []
	_find_all_mesh_instances(self, meshes)
	
	var fade_materials: Array[StandardMaterial3D] = []
	for mesh in meshes:
		var mat: StandardMaterial3D
		var src = mesh.get_active_material(0)
		if src is StandardMaterial3D:
			mat = src.duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()
			mat.albedo_color = Color.WHITE
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat
		fade_materials.append(mat)
	
	var tween = create_tween()
	for mat in fade_materials:
		tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 1.5)
	tween.tween_callback(queue_free)


func _find_all_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_all_mesh_instances(child, result)


## CharacterBody3D 无 body_entered 信号，使用 slide 碰撞检测
func _check_player_contact_after_slide() -> void:
	if _skill_manager == null:
		return
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var body = col.get_collider()
		if body and body.is_in_group("player"):
			_skill_manager.on_contact_with_player(body)
			break


func get_health_percent() -> float:
	return clamp(current_health / max_health, 0.0, 1.0)


func set_max_health(value: float) -> void:
	max_health = value
	current_health = max_health


func set_contact_damage(value: float) -> void:
	if _skill_manager:
		_skill_manager.set_contact_damage(value)


func set_attack_damage(value: float) -> void:
	if _skill_manager:
		_skill_manager.set_attack_damage(value)


func is_airborne() -> bool:
	return _airborne


func set_airborne(value: bool, duration: float = 1.0) -> void:
	_airborne = value
	if value:
		_airborne_timer = duration
		_original_y = global_position.y
		velocity = Vector3.ZERO
	else:
		if global_position.y > _original_y:
			global_position.y = _original_y


func _update_airborne(delta: float) -> void:
	if _airborne:
		_airborne_timer -= delta
		
		var peak_height = _original_y + 2.0
		var progress = 1.0 - (_airborne_timer / 1.0)
		
		if progress < 0.3:
			var rise_progress = progress / 0.3
			global_position.y = lerp(_original_y, peak_height, rise_progress)
		else:
			var fall_progress = (progress - 0.3) / 0.7
			global_position.y = lerp(peak_height, _original_y, fall_progress)
		
		if _airborne_timer <= 0:
			_airborne = false
			global_position.y = _original_y


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
	print("ChaserEnemy: 可用动画: ", anim_list)
	
	_animation_tree = AnimationTree.new()
	_animation_tree.name = "ChaserAnimTree"
	add_child(_animation_tree)
	_animation_tree.anim_player = _animation_tree.get_path_to(_animation_player)
	
	var sm = AnimationNodeStateMachine.new()
	
	var node_idle = AnimationNodeAnimation.new()
	node_idle.animation = anim_idle
	
	var node_run = AnimationNodeAnimation.new()
	node_run.animation = anim_run
	
	_attack_node = AnimationNodeAnimation.new()
	_attack_node.animation = anim_attacks[0]
	
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
	for anim in anim_attacks:
		_set_animation_loop(anim, Animation.LOOP_NONE)


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


func _update_chaser_animation() -> void:
	if _anim_playback == null:
		return
	var cur = _anim_playback.get_current_node()
	if cur == "Attack":
		return
	var speed_2d = Vector2(velocity.x, velocity.z).length()
	var next_state = "Run" if speed_2d > 0.1 else "Idle"
	if cur != next_state:
		_anim_playback.travel(next_state)


func _update_attack(_delta: float) -> void:
	if _is_attacking or _skill_manager == null:
		return
	if _target_player == null or not is_instance_valid(_target_player):
		return
	
	var dist = Vector2(global_position.x - _target_player.global_position.x,
		global_position.z - _target_player.global_position.z).length()
	if dist > _skill_manager.attack_range:
		return
	
	var look_dir = _target_player.global_position - global_position
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		rotation.y = atan2(look_dir.x, look_dir.z)
	
	if _skill_manager.try_melee_attack(self, _target_player):
		_is_attacking = true
		_play_attack_animation()
		_schedule_melee_damage()


func _play_attack_animation() -> void:
	if _animation_player == null:
		return
	var anim_name = anim_attacks[_attack_index]
	_attack_index = (_attack_index + 1) % anim_attacks.size()
	var resolved = _resolve_animation_name(anim_name)
	if resolved.is_empty():
		push_warning("ChaserEnemy: 未找到攻击动画: " + anim_name)
		_is_attacking = false
		return
	if _animation_tree:
		_animation_tree.active = false
	if not _animation_player.animation_finished.is_connected(_on_attack_anim_finished):
		_animation_player.animation_finished.connect(_on_attack_anim_finished)
	_animation_player.play(resolved)


## 攻击动画开始 0.3s 后施加伤害，与 alistar_attack1/2 命中帧同步
func _schedule_melee_damage() -> void:
	if _skill_manager == null or _target_player == null:
		return
	var target = _target_player
	var timer = get_tree().create_timer(0.3)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self) and is_instance_valid(target) and _skill_manager != null:
			_skill_manager.apply_melee_damage(self, target)
	)


func _resolve_animation_name(anim_name: String) -> String:
	"""在 AnimationPlayer 的所有库里查找动画，返回完整路径（库/名）；兼容 _anm 与 .anm 两种格式"""
	if _animation_player == null:
		return ""
	var candidates = [anim_name]
	if anim_name.ends_with("_anm"):
		candidates.append(anim_name.replace("_anm", ".anm"))
	elif anim_name.ends_with(".anm"):
		candidates.append(anim_name.replace(".anm", "_anm"))
	for lib_name in _animation_player.get_animation_library_list():
		var lib = _animation_player.get_animation_library(lib_name)
		if lib:
			for cand in candidates:
				if lib.has_animation(cand):
					if str(lib_name).is_empty():
						return cand
					return str(lib_name) + "/" + cand
	return ""


func _on_attack_anim_finished(_anim_name: StringName) -> void:
	if _animation_player and _animation_player.animation_finished.is_connected(_on_attack_anim_finished):
		_animation_player.animation_finished.disconnect(_on_attack_anim_finished)
	if _is_dead:
		return
	if _animation_tree:
		_animation_tree.active = true
	if _anim_playback:
		_anim_playback.travel("Idle")
	_is_attacking = false


func _on_anim_finished(_anim_name: StringName) -> void:
	if _anim_playback == null:
		return
	var cur = _anim_playback.get_current_node()
	if cur == "Attack":
		_is_attacking = false
		_anim_playback.travel("Idle")
