extends Node3D
class_name YasuoSkillManager

@export var player: CharacterBody3D

@export var detection_zone: Area3D

@export_group("Auto Attack - Steel Tempest Basic")
@export var aa_damage: float = 15.0
@export var aa_range: float = 3.0
@export var aa_cooldown: float = 0.8
@export var aa_cone_angle: float = 90.0

@export_group("Q Skill - Steel Tempest")
@export var q_damage: float = 20.0
@export var q_range: float = 4.0
@export var q_cooldown: float = 1.5
@export var q_cone_angle: float = 120.0
@export var tornado_damage: float = 35.0
@export var tornado_speed: float = 15.0
@export var tornado_range: float = 12.0
@export var knockup_duration: float = 1.0

@export_group("W Skill - Wind Wall")
@export var w_cooldown: float = 20.0
@export var w_duration: float = 4.0
@export var w_width: float = 6.0
@export var w_height: float = 3.0
@export var w_distance: float = 3.0

@export_group("E Skill - Sweeping Blade")
@export var e_damage: float = 25.0
@export var e_cooldown: float = 0.5
@export var e_dash_speed: float = 15.0
@export var e_dash_distance: float = 6.0

@export_group("R Skill - Last Breath")
@export var r_damage: float = 100.0
@export var r_cooldown: float = 12.0
@export var r_range: float = 15.0

## 技能极速：冷却时间 = 基础冷却 / (1 + 极速%)，100% 时冷却减半
var ability_haste: float = 0.0  # 全局， percent
var q_ability_haste: float = 0.0
var w_ability_haste: float = 0.0
var e_ability_haste: float = 0.0
var r_ability_haste: float = 0.0

func _get_effective_ad() -> float:
	return aa_damage + PlayerInventory.get_bonus_ad()

func _get_effective_cooldown(base: float, skill_haste: float) -> float:
	var total_haste = ability_haste + PlayerInventory.get_bonus_ability_haste()
	return base / (1.0 + (skill_haste + total_haste) / 100.0)

var _aa_timer: float = 0.0
var _q_timer: float = 0.0
var _w_timer: float = 0.0
var _e_timer: float = 0.0
var _r_timer: float = 0.0

var _q_stacks: int = 0
var _max_q_stacks: int = 3

var _enemies_in_range: Array[Node3D] = []
var _airborne_enemies: Array[Node3D] = []

var _wind_wall: Area3D = null
var _wind_wall_timer: float = 0.0


func _ready() -> void:
	if player == null:
		player = get_parent() as CharacterBody3D
	
	if detection_zone == null:
		detection_zone = get_node_or_null("DetectionZone")
	
	if detection_zone:
		detection_zone.body_entered.connect(_on_detection_zone_body_entered)
		detection_zone.body_exited.connect(_on_detection_zone_body_exited)


func _process(delta: float) -> void:
	_update_cooldowns(delta)
	_update_wind_wall(delta)
	_auto_cast_skills(delta)


func _update_cooldowns(delta: float) -> void:
	if _aa_timer > 0:
		_aa_timer -= delta
	if _q_timer > 0:
		_q_timer -= delta
	if _w_timer > 0:
		_w_timer -= delta
	if _e_timer > 0:
		_e_timer -= delta
	if _r_timer > 0:
		_r_timer -= delta


func _update_wind_wall(delta: float) -> void:
	if _wind_wall != null and is_instance_valid(_wind_wall):
		_wind_wall_timer -= delta
		if _wind_wall_timer <= 0:
			_wind_wall.queue_free()
			_wind_wall = null


func _auto_cast_skills(_delta: float) -> void:
	if player.get("is_dead"):
		return
	var nearest_enemy = _get_nearest_enemy()
	
	if nearest_enemy == null:
		return
	
	if _aa_timer <= 0:
		_cast_auto_attack()
		_aa_timer = aa_cooldown


func _get_nearest_enemy() -> Node3D:
	if _enemies_in_range.is_empty():
		return null
	
	var nearest: Node3D = null
	var nearest_distance: float = INF
	
	for enemy in _enemies_in_range:
		if not is_instance_valid(enemy):
			continue
		var distance = global_position.distance_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	
	return nearest


func _cast_auto_attack() -> void:
	var facing_direction = -player.global_transform.basis.z
	var hit_enemies = _get_enemies_in_cone(player.global_position, facing_direction, aa_range, aa_cone_angle)
	
	for enemy in hit_enemies:
		if enemy.has_method("take_damage"):
			enemy.take_damage(_get_effective_ad())
	
	_create_slash_effect(player.global_position, facing_direction, aa_range, Color(0.8, 0.8, 0.8, 0.6))
	print("Yasuo AA slash hit ", hit_enemies.size(), " enemies")


# 修改 scripts/yasuo_skill_manager.gd
func cast_q(target_direction: Vector3) -> bool:
	if _q_timer > 0:
		return false
	
	# 使用传入的鼠标方向，而不是原来的面向方向
	var direction = target_direction.normalized()
	
	_q_stacks += 1
	
	if _q_stacks >= _max_q_stacks:
		_cast_tornado(direction) # 向鼠标方向发风
		_q_stacks = 0
	else:
		# 普通刺击也建议改为朝向鼠标方向，提升手感
		var hit_enemies = _get_enemies_in_cone(player.global_position, direction, q_range, q_cone_angle)
		var q_dmg = q_damage + PlayerInventory.get_bonus_ad() * 0.5  # Q 混合加成
		for enemy in hit_enemies:
			if enemy.has_method("take_damage"):
				enemy.take_damage(q_dmg)
		_create_slash_effect(player.global_position, direction, q_range, Color(0.7, 0.9, 1.0, 0.8))
	
	_q_timer = _get_effective_cooldown(q_cooldown, q_ability_haste)
	return true


func _cast_tornado(direction: Vector3) -> void:
	# 1. 仅创建实例，不要在内部执行 setup
	var tornado = _create_tornado_projectile()
	
	# 2. 先把节点加入到场景树（解决报错的关键）
	get_tree().root.add_child(tornado)
	
	# 3. 设置好位置后，最后执行 setup
	tornado.global_position = player.global_position + Vector3(0, 1, 0)
	var torn_dmg = tornado_damage + PlayerInventory.get_bonus_ad() * 0.6
	tornado.setup(direction, torn_dmg, tornado_speed, tornado_range, knockup_duration, player)
	
	_create_slash_effect(player.global_position, direction, q_range, Color(0.5, 0.8, 1.0, 1.0))


func _create_tornado_projectile() -> Area3D:
	var tornado = Area3D.new()
	tornado.name = "Tornado"
	
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.8
	capsule.height = 3.0
	collision.shape = capsule
	tornado.add_child(collision)
	
	var visual = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 1.0
	mesh.height = 3.0
	visual.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.7)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.3, 0.6, 1.0)
	material.emission_energy_multiplier = 2.0
	visual.material_override = material
	tornado.add_child(visual)
	
	var script = load("res://scripts/tornado_projectile.gd")
	if script:
		tornado.set_script(script)
	
	return tornado


func cast_w() -> bool:
	if _w_timer > 0:
		return false
	
	if _wind_wall != null and is_instance_valid(_wind_wall):
		_wind_wall.queue_free()
	
	_wind_wall = _create_wind_wall()
	get_tree().root.add_child(_wind_wall)
	
	var facing_direction = -player.global_transform.basis.z
	_wind_wall.global_position = player.global_position + facing_direction * w_distance + Vector3(0, w_height / 2, 0)
	_wind_wall.look_at(player.global_position + Vector3(0, w_height / 2, 0))
	
	_wind_wall_timer = w_duration
	_w_timer = _get_effective_cooldown(w_cooldown, w_ability_haste)
	
	print("Yasuo W Wind Wall created!")
	return true


func _create_wind_wall() -> Area3D:
	var wall = Area3D.new()
	wall.name = "WindWall"
	wall.collision_layer = 0
	wall.collision_mask = 8
	
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(w_width, w_height, 0.3)
	collision.shape = box
	wall.add_child(collision)
	
	var visual = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(w_width, w_height, 0.1)
	visual.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.5, 0.8, 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.2, 0.4, 0.7)
	material.emission_energy_multiplier = 1.5
	visual.material_override = material
	wall.add_child(visual)
	
	wall.body_entered.connect(_on_wind_wall_body_entered)
	wall.area_entered.connect(_on_wind_wall_area_entered)
	
	return wall


func _on_wind_wall_body_entered(body: Node) -> void:
	if body.is_in_group("projectile"):
		body.queue_free()
		print("Wind Wall blocked projectile!")


func _on_wind_wall_area_entered(area: Area3D) -> void:
	if area.is_in_group("projectile"):
		area.queue_free()
		print("Wind Wall blocked projectile area!")


func cast_e(target_position: Vector3) -> bool:
	if _e_timer > 0:
		return false
	
	var direction = target_position - player.global_position
	direction.y = 0
	direction = direction.normalized()
	
	var dash_target = player.global_position + direction * e_dash_distance
	
	var enemies_hit = _get_enemies_along_dash(player.global_position, dash_target, 1.0)
	
	player.global_position = dash_target
	
	var nav_agent = player.get_node_or_null("NavigationAgent3D")
	if nav_agent:
		nav_agent.set_target_position(dash_target)
	
	for enemy in enemies_hit:
		if enemy.has_method("take_damage"):
			enemy.take_damage(e_damage + PlayerInventory.get_bonus_ad() * 0.5)
			print("Yasuo E dashed through enemy: ", enemy.name)
	
	_e_timer = _get_effective_cooldown(e_cooldown, e_ability_haste)
	print("Yasuo E Sweeping Blade used!")
	return true


func _get_enemies_along_dash(from: Vector3, to: Vector3, width: float) -> Array:
	var hit = []
	var dash_vec = Vector2(to.x - from.x, to.z - from.z)
	var dash_len = dash_vec.length()
	if dash_len < 0.01:
		return hit
	var dash_dir = dash_vec / dash_len
	
	for enemy in _enemies_in_range:
		if not is_instance_valid(enemy):
			continue
		var ep = Vector2(enemy.global_position.x - from.x, enemy.global_position.z - from.z)
		var proj = ep.dot(dash_dir)
		if proj < -0.5 or proj > dash_len + 0.5:
			continue
		var perp_dist = abs(ep.x * dash_dir.y - ep.y * dash_dir.x)
		if perp_dist < width:
			hit.append(enemy)
	return hit


func cast_r() -> bool:
	if _r_timer > 0:
		return false
	
	_update_airborne_enemies()
	
	if _airborne_enemies.is_empty():
		print("Yasuo R: No airborne enemies in range!")
		return false
	
	for enemy in _airborne_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(r_damage + PlayerInventory.get_bonus_ad() * 1.0)
		print("Yasuo R hit airborne enemy: ", enemy.name)
	
	_airborne_enemies.clear()
	_r_timer = _get_effective_cooldown(r_cooldown, r_ability_haste)
	print("Yasuo R Last Breath used!")
	return true


func _update_airborne_enemies() -> void:
	_airborne_enemies.clear()
	
	for enemy in _enemies_in_range:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_airborne") and enemy.is_airborne():
			_airborne_enemies.append(enemy)


func _get_enemies_in_cone(origin: Vector3, direction: Vector3, range_val: float, angle: float) -> Array:
	var hit_enemies = []
	var half_angle_rad = deg_to_rad(angle / 2)
	
	for enemy in _enemies_in_range:
		if not is_instance_valid(enemy):
			continue
		
		var to_enemy = enemy.global_position - origin
		to_enemy.y = 0
		var distance = to_enemy.length()
		
		if distance > range_val:
			continue
		
		to_enemy = to_enemy.normalized()
		var dot = direction.dot(to_enemy)
		var enemy_angle = acos(clamp(dot, -1.0, 1.0))
		
		if enemy_angle <= half_angle_rad:
			hit_enemies.append(enemy)
	
	return hit_enemies


func _create_slash_effect(origin: Vector3, direction: Vector3, range_val: float, color: Color) -> void:
	var slash = MeshInstance3D.new()
	var arr_mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	
	var arc_segments = 16
	var arc_angle = deg_to_rad(120)
	var width = 0.1
	
	for i in range(arc_segments):
		var angle1 = -arc_angle / 2 + float(i) / arc_segments * arc_angle
		var angle2 = -arc_angle / 2 + float(i + 1) / arc_segments * arc_angle
		
		var p1 = Vector3(cos(angle1) * range_val, 0, sin(angle1) * range_val)
		var p2 = Vector3(cos(angle2) * range_val, 0, sin(angle2) * range_val)
		
		vertices.append(Vector3(0, -width, 0))
		vertices.append(p1)
		vertices.append(p2)
		vertices.append(Vector3(0, width, 0))
		vertices.append(p2)
		vertices.append(p1)
	  
	# === 核心修复：构造符合 Godot 4 标准的 Mesh 数组 ===
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	slash.mesh = arr_mesh
	
	# 设置材质和位置
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 建议增加这一行，防止因为面朝向问题导致看不到特效
	material.cull_mode = BaseMaterial3D.CULL_DISABLED 
	slash.material_override = material
	
	get_tree().root.add_child(slash)
	slash.global_position = origin + Vector3(0, 1, 0)
	
	# 【核心修复】：增加特效朝向的防崩溃校验
	if direction.length_squared() > 0.001:
		var up_vec = Vector3.UP if abs(direction.y) < 0.99 else Vector3.RIGHT
		slash.look_at(origin + Vector3(0, 1, 0) + direction, up_vec)
	_animate_slash(slash)


func _animate_slash(slash: MeshInstance3D) -> void:
	var duration = 0.2
	var elapsed = 0.0
	
	# 获取当前的材质
	var mat = slash.material_override as StandardMaterial3D
	if not mat: return

	while elapsed < duration:
		# 每一帧检查节点是否还活着
		if not is_instance_valid(slash):
			return
			
		elapsed += get_process_delta_time()
		mat.albedo_color.a = lerp(1.0, 0.0, elapsed / duration)
		
		# 等待下一帧
		await get_tree().process_frame
	
	if is_instance_valid(slash):
		slash.queue_free()


func _on_detection_zone_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and body is Node3D:
		if body not in _enemies_in_range:
			_enemies_in_range.append(body)


func _on_detection_zone_body_exited(body: Node) -> void:
	if body in _enemies_in_range:
		_enemies_in_range.erase(body)


func get_aa_cooldown() -> float:
	return max(0, _aa_timer)

func get_q_cooldown() -> float:
	return max(0, _q_timer)

func get_w_cooldown() -> float:
	return max(0, _w_timer)

func get_e_cooldown() -> float:
	return max(0, _e_timer)

func get_r_cooldown() -> float:
	return max(0, _r_timer)

func get_aa_max_cooldown() -> float:
	return aa_cooldown

func get_q_max_cooldown() -> float:
	return _get_effective_cooldown(q_cooldown, q_ability_haste)

func get_w_max_cooldown() -> float:
	return _get_effective_cooldown(w_cooldown, w_ability_haste)

func get_e_max_cooldown() -> float:
	return _get_effective_cooldown(e_cooldown, e_ability_haste)

func get_r_max_cooldown() -> float:
	return _get_effective_cooldown(r_cooldown, r_ability_haste)

func get_q_stacks() -> int:
	return _q_stacks

func get_enemy_count() -> int:
	return _enemies_in_range.size()
