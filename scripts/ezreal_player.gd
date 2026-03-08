extends CharacterBody3D
class_name EzrealPlayer

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

@onready var skill_manager: EzrealSkillManager = $EzrealSkillManager

@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0

@export_group("Health")
@export var max_health: float = 500.0
@export var hero_hp_bar_offset: float = 6.0

@export_group("Animation")
@export var anim_death: String = "ezreal_death_anm"
@export var anim_idle: String = "ezreal_idle_anm"
@export var anim_idle_stop: Array[String] = ["ezreal_idle2_anm", "ezreal_idle_anm"]  # 停下时随机衔接
@export var anim_run: String = "ezreal_run_anm"
@export var anim_attacks: Array[String] = [
	"ezreal_attack1_anm", "ezreal_attack2_anm", "ezreal_attack3_anm", "ezreal_attack4_anm"
]

var _animation_player: AnimationPlayer = null
var _animation_tree: AnimationTree = null
var _anim_playback: AnimationNodeStateMachinePlayback = null
var _attack_node: AnimationNodeAnimation = null
var _skill_node: AnimationNodeAnimation = null
var _idle_node: AnimationNodeAnimation = null
var _skill_anim_queue: Array[String] = []
var _playing_skill_anim: bool = false
var _skill_trans_to_idle: String = ""
var _skill_trans_to_run: String = ""
const BLEND_TIME: float = 0.12

var attack_range: float:
	get:
		if skill_manager:
			return skill_manager.aa_range
		return 10.0

var camera: Camera3D
var ground_y: float = 0.0
var ray_length: float = 1000.0
var is_moving: bool = false
var is_casting: bool = false
var current_health: float = 500.0
var _hero_hp_fill: ColorRect = null
const HERO_BAR_WIDTH: float = 30.0
const HERO_BAR_HEIGHT: float = 2.0

var level: int = 1
var experience: float = 0.0
var exp_base: float = 100.0
var exp_growth: float = 50.0
var _pending_levelups: int = 0

var _range_indicator: MeshInstance3D = null
var is_dead: bool = false


func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	
	camera = get_viewport().get_camera_3d()
	
	if navigation_agent:
		navigation_agent.path_desired_distance = 0.5
		navigation_agent.target_desired_distance = 0.5
		navigation_agent.avoidance_enabled = true
	
	_find_animation_player()
	_setup_animation_tree()
	_create_range_indicator()
	_create_hero_health_bar()


func _find_animation_player() -> void:
	## 在 instanced GLB 模型下查找 AnimationPlayer
	_animation_player = get_node_or_null("Visuals/SkinnedMesh/AnimationPlayer")
	if _animation_player == null:
		_animation_player = _find_animation_player_recursive($Visuals)
	if _animation_player:
		var anim_list: PackedStringArray = []
		for lib_name in _animation_player.get_animation_library_list():
			var lib = _animation_player.get_animation_library(lib_name)
			if lib:
				for anim_name in lib.get_animation_list():
					var full = str(anim_name) if str(lib_name) == "" else str(lib_name) + "/" + str(anim_name)
					anim_list.append(full)
		print("Ezreal: 已找到 AnimationPlayer，可用动画: ", anim_list)
	else:
		push_warning("Ezreal: 未找到 AnimationPlayer，请确认 GLB 模型包含动画")


func _setup_animation_tree() -> void:
	if _animation_player == null:
		return
	_animation_tree = AnimationTree.new()
	_animation_tree.name = "EzrealAnimationTree"
	add_child(_animation_tree)
	_animation_tree.anim_player = _animation_tree.get_path_to(_animation_player)

	var state_machine = AnimationNodeStateMachine.new()

	var node_idle = AnimationNodeAnimation.new()
	node_idle.animation = anim_idle
	_idle_node = node_idle

	var run_tree = AnimationNodeBlendTree.new()
	var node_run = AnimationNodeAnimation.new()
	node_run.animation = anim_run
	var run_time_scale = AnimationNodeTimeScale.new()
	run_tree.add_node("RunAnim", node_run, Vector2(-200, 0))
	run_tree.add_node("TimeScale", run_time_scale, Vector2(0, 0))
	run_tree.connect_node("TimeScale", 0, "RunAnim")
	run_tree.connect_node("output", 0, "TimeScale")

	var attack_tree = AnimationNodeBlendTree.new()
	var node_attack = AnimationNodeAnimation.new()
	node_attack.animation = anim_attacks[0]
	_attack_node = node_attack
	var atk_time_scale = AnimationNodeTimeScale.new()
	attack_tree.add_node("AttackAnim", node_attack, Vector2(-200, 0))
	attack_tree.add_node("TimeScale", atk_time_scale, Vector2(0, 0))
	attack_tree.connect_node("TimeScale", 0, "AttackAnim")
	attack_tree.connect_node("output", 0, "TimeScale")

	var node_skill = AnimationNodeAnimation.new()
	node_skill.animation = anim_idle
	_skill_node = node_skill

	state_machine.add_node("Idle", node_idle, Vector2(100, 0))
	state_machine.add_node("Run", run_tree, Vector2(100, 80))
	state_machine.add_node("Attack", attack_tree, Vector2(100, 160))
	state_machine.add_node("Skill", node_skill, Vector2(100, 240))
	state_machine.set_graph_offset(Vector2(-50, 0))

	var make_transition = func(xfade: float) -> AnimationNodeStateMachineTransition:
		var t = AnimationNodeStateMachineTransition.new()
		t.xfade_time = xfade
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		return t
	var states = ["Idle", "Run", "Attack", "Skill"]
	for from_s in states:
		for to_s in states:
			if from_s != to_s:
				var xfade = BLEND_TIME
				if (from_s == "Attack" or from_s == "Skill") and (to_s == "Run" or to_s == "Idle"):
					xfade = 0.2
				state_machine.add_transition(from_s, to_s, make_transition.call(xfade))

	_animation_tree.tree_root = state_machine
	_animation_tree.active = true
	_anim_playback = _animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _anim_playback:
		_anim_playback.travel("Idle")
	if not _animation_tree.animation_finished.is_connected(_on_anim_tree_finished):
		_animation_tree.animation_finished.connect(_on_anim_tree_finished)

	_set_animation_loop(anim_idle, Animation.LOOP_LINEAR)
	_set_animation_loop(anim_run, Animation.LOOP_LINEAR)
	print("Ezreal: AnimationTree 已创建，含 Idle/Run/Attack/Skill 状态")


func _on_anim_tree_finished(_anim_name: StringName) -> void:
	if _anim_playback == null:
		return
	var cur = _anim_playback.get_current_node()
	var speed_2d = Vector2(velocity.x, velocity.z).length()
	var next = "Run" if speed_2d > 0.1 else "Idle"

	if cur == "Skill":
		if not _skill_anim_queue.is_empty():
			var next_anim = _skill_anim_queue.pop_front()
			_skill_node.animation = next_anim
			_anim_playback.start("Skill")
			return
		if _skill_trans_to_idle != "" or _skill_trans_to_run != "":
			var trans_anim = _skill_trans_to_run if speed_2d > 0.1 else _skill_trans_to_idle
			_skill_trans_to_idle = ""
			_skill_trans_to_run = ""
			_skill_node.animation = trans_anim
			_anim_playback.start("Skill")
			return
		_playing_skill_anim = false
		is_casting = false
		if next == "Idle" and _idle_node != null and not anim_idle_stop.is_empty():
			_idle_node.animation = anim_idle_stop[randi() % anim_idle_stop.size()]
			_set_animation_loop(_idle_node.animation, Animation.LOOP_LINEAR)
		_anim_playback.travel(next)
		return

	if cur == "Attack":
		if next == "Idle" and _idle_node != null and not anim_idle_stop.is_empty():
			_idle_node.animation = anim_idle_stop[randi() % anim_idle_stop.size()]
			_set_animation_loop(_idle_node.animation, Animation.LOOP_LINEAR)
		_anim_playback.travel(next)


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


func _create_range_indicator() -> void:
	_range_indicator = MeshInstance3D.new()
	_range_indicator.name = "RangeIndicator"
	
	var torus = TorusMesh.new()
	# 【修改点 1】设置基础半径为 1.0，inner_radius 稍微小一点（如 0.98）可以让线看起来很细
	torus.inner_radius = 0.98 
	torus.outer_radius = 1.0
	torus.rings = 64          # 增加圆环平滑度
	torus.ring_segments = 16  # 截面细分
	_range_indicator.mesh = torus
	
	var material = StandardMaterial3D.new()
	# 颜色建议稍微亮一点，透明度调低
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.3) 
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	_range_indicator.material_override = material
	
	# 【修改点 2】位置微调，确保在地面上方一点点防止闪烁
	_range_indicator.position = Vector3(0, 0.1, 0)
	
	# 【修改点 3】重置旋转。TorusMesh 默认就是水平的，不需要旋转 90 度
	_range_indicator.rotation_degrees = Vector3(0, 0, 0)
	
	# 【修改点 4】由于基础半径是 1.0，直接按攻击距离缩放 X 和 Z 轴
	# Y 轴保持 1.0 即可（圆环厚度不随距离增加）
	_range_indicator.scale = Vector3(attack_range, 1.0, attack_range)
	
	_range_indicator.visible = false
	_range_indicator.top_level = false # 设为 false 让它跟着英雄走
	
	add_child(_range_indicator)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead or is_casting:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event.position)
	
	if event is InputEventKey:
		if event.keycode == KEY_A:
			if event.pressed:
				if skill_manager and skill_manager.has_method("can_cast_auto_attack") and skill_manager.can_cast_auto_attack():
					stop_moving()
					skill_manager.try_cast_auto_attack()
				_show_attack_range()
			else:
				_hide_attack_range()
		
		if event.keycode == KEY_Q and event.pressed:
			_cast_q_skill()
		
		if event.keycode == KEY_W and event.pressed:
			_cast_w_skill()
		
		if event.keycode == KEY_E and event.pressed:
			_cast_e_skill()
		
		if event.keycode == KEY_R and event.pressed:
			_cast_r_skill()


func _show_attack_range() -> void:
	if _range_indicator:
		# 同样修改缩放轴为 X 和 Z
		_range_indicator.scale = Vector3(attack_range, 1.0, attack_range)
		_range_indicator.visible = true


func _hide_attack_range() -> void:
	if _range_indicator:
		_range_indicator.visible = false


func _update_range_indicator_scale() -> void:
	if _range_indicator and _range_indicator.visible:
		_range_indicator.scale = Vector3(attack_range, 1.0, attack_range)


func _handle_right_click(screen_position: Vector2) -> void:
	if camera == null:
		push_warning("Camera not found!")
		return
	
	var target_position = get_mouse_world_position(screen_position)
	if target_position != Vector3.INF:
		_set_navigation_target(target_position)
		_spawn_click_indicator(target_position)


func get_mouse_world_position(screen_position: Vector2 = Vector2.INF) -> Vector3:
	if camera == null:
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return Vector3.INF
	
	if screen_position == Vector2.INF:
		screen_position = get_viewport().get_mouse_position()
	
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_position)
	var ray_end: Vector3 = ray_origin + ray_normal * ray_length
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end
	)
	query.exclude = [self.get_rid()]
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(query)
	
	if result:
		var target_position: Vector3 = result.position
		target_position.y = ground_y
		return target_position
	else:
		return _get_plane_intersection(ray_origin, ray_normal)


func get_mouse_direction() -> Vector3:
	var mouse_world_pos = get_mouse_world_position()
	if mouse_world_pos == Vector3.INF:
		return Vector3.FORWARD
	
	var direction = mouse_world_pos - global_position
	direction.y = 0
	return direction.normalized()


func _get_plane_intersection(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	if abs(ray_direction.y) < 0.0001:
		return Vector3.INF
	
	var t: float = (ground_y - ray_origin.y) / ray_direction.y
	
	if t < 0:
		return Vector3.INF
	
	return ray_origin + t * ray_direction


func _set_navigation_target(target_position: Vector3) -> void:
	if navigation_agent == null:
		push_warning("NavigationAgent3D not found!")
		return
	
	navigation_agent.set_target_position(target_position)
	is_moving = true
	print("Ezreal moving to: ", target_position)


func _cast_q_skill() -> void:
	if skill_manager == null:
		return
	var direction = get_mouse_direction()
	skill_manager.cast_q_direction(direction)


func _cast_w_skill() -> void:
	if skill_manager == null:
		return
	var direction = get_mouse_direction()
	skill_manager.cast_w_direction(direction)


func _cast_e_skill() -> void:
	if skill_manager == null:
		push_warning("EzrealSkillManager not found!")
		return
	
	var mouse_world_pos = get_mouse_world_position()
	if mouse_world_pos == Vector3.INF:
		print("Cannot cast E: Invalid mouse position")
		return
	
	skill_manager.cast_e(mouse_world_pos)


func _cast_r_skill() -> void:
	if skill_manager == null:
		push_warning("EzrealSkillManager not found!")
		return
	
	var direction = get_mouse_direction()
	skill_manager.cast_r(direction)


func _update_animation() -> void:
	if _anim_playback == null:
		return
	if _playing_skill_anim:
		var can_interrupt = not is_casting and _skill_trans_to_idle == "" and _skill_trans_to_run == ""
		if can_interrupt:
			var spd = Vector2(velocity.x, velocity.z).length()
			if spd > 0.5:
				_playing_skill_anim = false
				_skill_anim_queue.clear()
				_anim_playback.travel("Run")
				var rs = clamp(spd / move_speed, 0.3, 1.5)
				_animation_tree.set("parameters/Run/TimeScale/scale", rs)
		return
	var cur = _anim_playback.get_current_node()
	var speed_2d = Vector2(velocity.x, velocity.z).length()
	if cur == "Attack":
		if speed_2d > 0.5:
			_anim_playback.travel("Run")
			var run_scale = clamp(speed_2d / move_speed, 0.3, 1.5)
			_animation_tree.set("parameters/Run/TimeScale/scale", run_scale)
		return
	if cur == "Skill":
		_skill_anim_queue.clear()
	var want_moving = speed_2d > 0.1
	var next_state = "Run" if want_moving else "Idle"
	if cur != next_state:
		if next_state == "Idle" and _idle_node != null and not anim_idle_stop.is_empty():
			_idle_node.animation = anim_idle_stop[randi() % anim_idle_stop.size()]
			_set_animation_loop(_idle_node.animation, Animation.LOOP_LINEAR)
		_anim_playback.travel(next_state)
	if next_state == "Run":
		var run_scale = clamp(speed_2d / move_speed, 0.3, 1.5)
		_animation_tree.set("parameters/Run/TimeScale/scale", run_scale)


func play_attack_animation() -> void:
	"""平 A 时由技能管理器调用，随机播放四个普攻动画之一，播放速度与攻速挂钩"""
	if _anim_playback == null or _attack_node == null or anim_attacks.is_empty():
		return
	var idx = randi() % anim_attacks.size()
	var chosen_anim = anim_attacks[idx]
	_attack_node.animation = chosen_anim

	var anim_length = _get_animation_length(chosen_anim)
	var aa_cd = skill_manager.aa_cooldown if skill_manager else 1.0
	var speed_ratio = anim_length / aa_cd if aa_cd > 0.01 else 1.0
	_animation_tree.set("parameters/Attack/TimeScale/scale", speed_ratio)

	# 用 start() 强制从头播放，确保每次平 A 都能触发攻击动画
	_anim_playback.start("Attack")


func play_skill_animation(anim_name: String) -> void:
	if _anim_playback == null or _skill_node == null:
		return
	_skill_anim_queue.clear()
	_playing_skill_anim = true
	_skill_trans_to_idle = ""
	_skill_trans_to_run = ""
	_skill_node.animation = anim_name
	_anim_playback.start("Skill")


func play_skill_animation_sequence(anims: Array) -> void:
	if anims.is_empty() or _anim_playback == null or _skill_node == null:
		return
	_playing_skill_anim = true
	_skill_trans_to_idle = ""
	_skill_trans_to_run = ""
	_skill_node.animation = anims[0]
	_skill_anim_queue.clear()
	for i in range(1, anims.size()):
		_skill_anim_queue.append(anims[i])
	_anim_playback.start("Skill")


func play_skill_animation_with_transitions(anim: String, to_idle: String, to_run: String) -> void:
	if _anim_playback == null or _skill_node == null:
		return
	_skill_anim_queue.clear()
	_playing_skill_anim = true
	_skill_trans_to_idle = to_idle
	_skill_trans_to_run = to_run
	_skill_node.animation = anim
	_anim_playback.start("Skill")


func _get_animation_length(anim_name: String) -> float:
	if _animation_player == null:
		return 1.0
	for lib_name in _animation_player.get_animation_library_list():
		var lib = _animation_player.get_animation_library(lib_name)
		if lib and lib.has_animation(anim_name):
			return lib.get_animation(anim_name).length
	return 1.0


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_update_range_indicator_scale()
	_update_animation()
	
	if is_casting:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	if navigation_agent == null:
		return
	
	if navigation_agent.is_navigation_finished():
		is_moving = false
		velocity = Vector3.ZERO
		move_and_slide()
		return
	
	var final_target = navigation_agent.target_position
	var dist_to_final = Vector2(global_position.x - final_target.x, global_position.z - final_target.z).length()
	
	if dist_to_final < 0.3:
		is_moving = false
		velocity = Vector3.ZERO
		move_and_slide()
		navigation_agent.set_target_position(global_position)
		return
	
	var next_position: Vector3 = navigation_agent.get_next_path_position()
	var target_pos_2d: Vector3 = Vector3(next_position.x, global_position.y, next_position.z)
	var move_direction: Vector3 = Vector3.ZERO
	
	if global_position.distance_to(target_pos_2d) > 0.05:
		move_direction = (target_pos_2d - global_position).normalized()
	
	var target_velocity: Vector3 = move_direction * move_speed
	velocity = velocity.lerp(target_velocity, 10.0 * delta)
	
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0
	
	move_and_slide()
	
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.3 and move_direction.length_squared() > 0.01 and dist_to_final > 1.0:
		var target_rotation: float = atan2(move_direction.x, move_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)


func get_is_moving() -> bool:
	return is_moving


func stop_moving() -> void:
	if navigation_agent:
		navigation_agent.set_target_position(global_position)
	is_moving = false
	velocity = Vector3.ZERO


func take_damage(amount: float) -> void:
	if is_dead:
		return
	current_health -= amount
	current_health = max(current_health, 0)
	_update_hero_health_bar()
	if current_health <= 0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	stop_moving()
	set_process_input(false)
	set_process_unhandled_input(false)
	
	var hp_bar = get_node_or_null("HeroHealthBarAnchor")
	if hp_bar:
		hp_bar.visible = false
	
	if _animation_tree:
		_animation_tree.active = false
	if _animation_player:
		for lib_name in _animation_player.get_animation_library_list():
			var lib = _animation_player.get_animation_library(lib_name)
			if lib and lib.has_animation(anim_death):
				_animation_player.play(anim_death)
				break
	
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(_on_death_timer_timeout)


func _on_death_timer_timeout() -> void:
	var main = get_tree().current_scene
	var hud = main.get_node_or_null("HUD") if main else null
	if hud and hud.has_method("show_game_over"):
		hud.show_game_over()


func get_exp_to_next_level() -> float:
	return exp_base + (level - 1) * exp_growth


func get_exp_progress() -> float:
	return clamp(experience / get_exp_to_next_level(), 0.0, 1.0)


func add_experience(amount: float) -> void:
	experience += amount
	while experience >= get_exp_to_next_level():
		experience -= get_exp_to_next_level()
		_level_up()


func _level_up() -> void:
	level += 1
	max_health += 50.0
	var effective_max = max_health + PlayerInventory.get_bonus_max_health()
	current_health = min(current_health + 50.0, effective_max)
	_update_hero_health_bar()
	_pending_levelups += 1
	print("Ezreal 升级到 Lv.", level, " 最大生命值: ", max_health)


func _create_hero_health_bar() -> void:
	var billboard = Node3D.new()
	billboard.name = "HeroHealthBarAnchor"
	billboard.position = Vector3(0, hero_hp_bar_offset, 0)
	add_child(billboard)
	
	var sprite = Sprite3D.new()
	sprite.name = "HeroHealthBarSprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.fixed_size = true
	sprite.pixel_size = 0.008
	sprite.render_priority = 10
	sprite.texture = await _create_hero_health_bar_texture()
	billboard.add_child(sprite)


func _create_hero_health_bar_texture() -> Texture2D:
	var border_size = 1
	var vp_w = int(HERO_BAR_WIDTH) + border_size * 2
	var vp_h = int(HERO_BAR_HEIGHT) + border_size * 2
	
	var viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(vp_w, vp_h)
	
	var container = Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(container)
	
	var border_rect = ColorRect.new()
	border_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	border_rect.custom_minimum_size = Vector2(vp_w, vp_h)
	border_rect.position = Vector2(0, 0)
	container.add_child(border_rect)
	
	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.15, 0.9)
	bg.custom_minimum_size = Vector2(HERO_BAR_WIDTH, HERO_BAR_HEIGHT)
	bg.position = Vector2(border_size, border_size)
	border_rect.add_child(bg)
	
	_hero_hp_fill = ColorRect.new()
	_hero_hp_fill.color = Color(0.15, 0.75, 0.25, 1.0)
	_hero_hp_fill.custom_minimum_size = Vector2(HERO_BAR_WIDTH, HERO_BAR_HEIGHT)
	_hero_hp_fill.position = Vector2(0, 0)
	bg.add_child(_hero_hp_fill)
	
	add_child(viewport)
	await get_tree().process_frame
	return viewport.get_texture()


func _update_hero_health_bar() -> void:
	if _hero_hp_fill == null:
		return
	_hero_hp_fill.custom_minimum_size.x = HERO_BAR_WIDTH * clamp(current_health / max_health, 0.0, 1.0)


func _spawn_click_indicator(pos: Vector3) -> void:
	var root = Node3D.new()
	root.name = "ClickIndicator"
	get_tree().root.add_child(root)
	root.global_position = pos + Vector3(0, 0.05, 0)

	var indicator_color = Color(0.15, 0.85, 0.3, 0.9)

	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = indicator_color
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.no_depth_test = true

	var arrow_mat = StandardMaterial3D.new()
	arrow_mat.albedo_color = indicator_color
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arrow_mat.no_depth_test = true

	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.7
	torus.outer_radius = 0.85
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = ring_mat
	root.add_child(ring)

	var arrow_root = Node3D.new()
	arrow_root.position = Vector3(0, 2.0, 0)
	root.add_child(arrow_root)

	var head = MeshInstance3D.new()
	var head_mesh = CylinderMesh.new()
	head_mesh.top_radius = 0.18
	head_mesh.bottom_radius = 0.0
	head_mesh.height = 0.35
	head.mesh = head_mesh
	head.material_override = arrow_mat
	arrow_root.add_child(head)

	var stem = MeshInstance3D.new()
	var stem_mesh = CylinderMesh.new()
	stem_mesh.top_radius = 0.05
	stem_mesh.bottom_radius = 0.05
	stem_mesh.height = 0.45
	stem.mesh = stem_mesh
	stem.position = Vector3(0, 0.4, 0)
	stem.material_override = arrow_mat
	arrow_root.add_child(stem)

	var dur = 0.35
	var tween = get_tree().create_tween()
	tween.bind_node(root)

	tween.tween_property(ring, "scale", Vector3(0.05, 0.05, 0.05), dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(arrow_root, "position", Vector3(0, 0.1, 0), dur * 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, dur)
	tween.parallel().tween_property(arrow_mat, "albedo_color:a", 0.0, dur)

	tween.tween_callback(root.queue_free)
