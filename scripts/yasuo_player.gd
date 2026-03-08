extends CharacterBody3D
class_name YasuoPlayer

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

@onready var skill_manager: YasuoSkillManager = $YasuoSkillManager

@export var move_speed: float = 6.0
@export var rotation_speed: float = 12.0

@export_group("Health")
@export var max_health: float = 500.0
@export var hero_hp_bar_offset: float = 6.0

@export_group("Animation")
@export var anim_death: String = "yasuo_death_anm"

var attack_range: float:
	get:
		if skill_manager:
			return skill_manager.aa_range
		return 3.0

var camera: Camera3D
var ground_y: float = 0.0
var ray_length: float = 1000.0
var is_moving: bool = false
var current_health: float = 500.0
var _hero_hp_fill: ColorRect = null
const HERO_BAR_WIDTH: float = 30.0
const HERO_BAR_HEIGHT: float = 2.0

var level: int = 1
var experience: float = 0.0
var exp_base: float = 100.0
var exp_growth: float = 50.0
var _pending_levelups: int = 0

var _airborne: bool = false
var _airborne_timer: float = 0.0

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
	
	_create_range_indicator()
	_create_hero_health_bar()


func get_mouse_direction() -> Vector3:
	var mouse_world_pos = get_mouse_world_position()
	if mouse_world_pos == Vector3.INF:
		return -global_transform.basis.z # 如果没点到地面，默认朝前
	
	var direction = mouse_world_pos - global_position
	direction.y = 0
	return direction.normalized()


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
	if is_dead:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event.position)
	
	if event is InputEventKey:
		if event.keycode == KEY_A:
			if event.pressed:
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


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_update_airborne(delta)
	_update_range_indicator_scale()
	
	if navigation_agent == null:
		return
	
	if navigation_agent.is_navigation_finished():
		is_moving = false
		velocity = Vector3.ZERO
		move_and_slide()
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
	
	var distance_to_final = global_position.distance_to(navigation_agent.target_position)
	var current_speed = Vector2(velocity.x, velocity.z).length()
	
	if distance_to_final > 0.5 and current_speed > 0.1:
		var target_rotation: float = atan2(move_direction.x, move_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)


func _update_airborne(delta: float) -> void:
	if _airborne:
		_airborne_timer -= delta
		if _airborne_timer <= 0:
			_airborne = false


func _handle_right_click(screen_position: Vector2) -> void:
	if camera == null:
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
	
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self.get_rid()]
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(query)
	
	if result:
		var target_position: Vector3 = result.position
		target_position.y = ground_y
		return target_position
	else:
		return _get_plane_intersection(ray_origin, ray_normal)


func _get_plane_intersection(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	if abs(ray_direction.y) < 0.0001:
		return Vector3.INF
	
	var t: float = (ground_y - ray_origin.y) / ray_direction.y
	
	if t < 0:
		return Vector3.INF
	
	return ray_origin + t * ray_direction


func _set_navigation_target(target_position: Vector3) -> void:
	if navigation_agent == null:
		return
	
	navigation_agent.set_target_position(target_position)
	is_moving = true


func _cast_q_skill() -> void:
	if skill_manager == null:
		return
	
	# 获取鼠标指向的方向
	var direction = get_mouse_direction()
	# 传入方向给技能管理器
	skill_manager.cast_q(direction)


func _cast_w_skill() -> void:
	if skill_manager == null:
		return
	
	skill_manager.cast_w()


func _cast_e_skill() -> void:
	if skill_manager == null:
		return
	
	var mouse_world_pos = get_mouse_world_position()
	if mouse_world_pos == Vector3.INF:
		return
	
	skill_manager.cast_e(mouse_world_pos)


func _cast_r_skill() -> void:
	if skill_manager == null:
		return
	
	skill_manager.cast_r()


func is_airborne() -> bool:
	return _airborne


func set_airborne(value: bool, duration: float = 1.0) -> void:
	_airborne = value
	if value:
		_airborne_timer = duration


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
	
	var anim_player = _find_animation_player_recursive(self)
	if anim_player:
		for lib_name in anim_player.get_animation_library_list():
			var lib = anim_player.get_animation_library(lib_name)
			if lib and lib.has_animation(anim_death):
				anim_player.play(anim_death)
				break
	
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(_on_death_timer_timeout)


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result = _find_animation_player_recursive(child)
		if result:
			return result
	return null


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
	current_health = min(current_health + 50.0, max_health)
	_update_hero_health_bar()
	_pending_levelups += 1
	print("Yasuo 升级到 Lv.", level, " 最大生命值: ", max_health)


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
