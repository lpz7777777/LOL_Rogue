extends Node3D
class_name EzrealSkillManager

@export var player: CharacterBody3D

@export var detection_zone: Area3D

@export var projectile_scene: PackedScene

@export_group("Auto Attack")
@export var aa_damage: float = 20.0
@export var aa_speed: float = 25.0
@export var aa_cooldown: float = 1.0
@export var aa_range: float = 13.0

@export_group("Q Skill - Mystic Shot")
@export var q_damage: float = 25.0
@export var q_speed: float = 50.0
@export var q_cooldown: float = 1.2
@export var q_range: float = 15.0

@export_group("W Skill - Essence Flux")
@export var w_damage: float = 20.0
@export var w_speed: float = 50.0
@export var w_cooldown: float = 2.0
@export var w_range: float = 12.0
@export var w_aoe_radius: float = 6.0

@export_group("E Skill - Arcane Shift")
@export var e_max_distance: float = 8.0
@export var e_cooldown: float = 3.0
@export var e_damage: float = 30.0

@export_group("R Skill - Trueshot Barrage")
@export var r_damage: float = 100.0
@export var r_speed: float = 30.0
@export var r_cooldown: float = 10.0
@export var r_range: float = 50.0
@export var r_width: float = 2.0

## 法强 (AP)，技能按比例加成；AD = aa_damage
@export var ap: float = 0.0

## 技能极速：冷却时间 = 基础冷却 / (1 + 极速%)，100% 时冷却减半
var ability_haste: float = 0.0  # 全局， percent
var q_ability_haste: float = 0.0
var w_ability_haste: float = 0.0
var e_ability_haste: float = 0.0
var r_ability_haste: float = 0.0

func _get_effective_cooldown(base: float, skill_haste: float) -> float:
	var total_haste = ability_haste + PlayerInventory.get_bonus_ability_haste()
	return base / (1.0 + (skill_haste + total_haste) / 100.0)

func _ad() -> float:
	return aa_damage + PlayerInventory.get_bonus_ad()

func _ap() -> float:
	return ap + PlayerInventory.get_bonus_ap()

## 技能 AD/AP 加成比例，参考 LOL 伊泽瑞尔
const Q_AD_RATIO: float = 1.2    # Q 主 AD
const Q_AP_RATIO: float = 0.15
const W_AD_RATIO: float = 0.15
const W_AP_RATIO: float = 0.8    # W 主 AP
const E_AD_RATIO: float = 0.5
const E_AP_RATIO: float = 0.5
const R_AD_RATIO: float = 1.0
const R_AP_RATIO: float = 0.9

const SKILL_AA_INTERVAL: float = 0.2  # Q/W/E/R 与平A、技能互相之间最少间隔

const SFX_AA_FIRE: String = "res://assets/Ezreal/skill/sfx/aa_fire.wav"
const SFX_AA_HIT: String = "res://assets/Ezreal/skill/sfx/aa_hit.wav"
const SFX_Q_FIRE: String = "res://assets/Ezreal/skill/sfx/q_fire.wav"
const SFX_Q_HIT: String = "res://assets/Ezreal/skill/sfx/q_hit.wav"
const SFX_W_FIRE: String = "res://assets/Ezreal/skill/sfx/w_fire.wav"
const SFX_W_HIT: String = "res://assets/Ezreal/skill/sfx/w_hit.wav"
const SFX_E_FIRE: String = "res://assets/Ezreal/skill/sfx/e_fire.wav"
const SFX_R_FIRE: String = "res://assets/Ezreal/skill/sfx/r_fire.wav"

func _get_skill_damage(base: float, ad_ratio: float, ap_ratio: float) -> float:
	"""基础伤害 + AD加成 + AP加成，包含装备加成"""
	return base + ad_ratio * _ad() + ap_ratio * _ap()

var _aa_timer: float = 0.0
var _skill_interval_timer: float = 0.0  # 上次释放技能/平A后的公共间隔
var _q_timer: float = 0.0
var _w_timer: float = 0.0
var _e_timer: float = 0.0
var _r_timer: float = 0.0

var _enemies_in_range: Array[Node3D] = []

var _camera: Camera3D = null


func _play_sfx(path: String) -> void:
	if path.is_empty():
		return
	if not ResourceLoader.exists(path):
		return
	var stream = load(path) as AudioStream
	if stream == null:
		return
	var audio_player = AudioStreamPlayer.new()
	audio_player.stream = stream
	audio_player.bus = "Master"
	add_child(audio_player)
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()


func _unlock_skill_anim() -> void:
	if is_instance_valid(player):
		player.set("_playing_skill_anim", false)
		player.set("_skill_trans_to_idle", "")
		player.set("_skill_trans_to_run", "")


func _ready() -> void:
	if player == null:
		player = get_parent() as CharacterBody3D
	
	if detection_zone == null:
		detection_zone = get_node_or_null("DetectionZone")
	
	if detection_zone:
		detection_zone.body_entered.connect(_on_detection_zone_body_entered)
		detection_zone.body_exited.connect(_on_detection_zone_body_exited)
		var max_range = max(aa_range, q_range, w_range)
		var shape_node = detection_zone.get_node_or_null("CollisionShape3D")
		if shape_node and shape_node.shape:
			var shape = shape_node.shape
			if shape is SphereShape3D:
				shape.radius = max_range
			elif shape is CylinderShape3D:
				shape.radius = max_range
				shape.height = max_range * 2.0  # 足够高以覆盖站立单位
	
	_camera = get_viewport().get_camera_3d()
	
	if projectile_scene == null:
		print("EzrealSkillManager: 使用内置默认投射物配置")


func _process(delta: float) -> void:
	_update_cooldowns(delta)
	_auto_cast_skills(delta)


func _update_cooldowns(delta: float) -> void:
	if _aa_timer > 0:
		_aa_timer -= delta
	if _skill_interval_timer > 0:
		_skill_interval_timer -= delta
	if _q_timer > 0:
		_q_timer -= delta
	if _w_timer > 0:
		_w_timer -= delta
	if _e_timer > 0:
		_e_timer -= delta
	if _r_timer > 0:
		_r_timer -= delta


func _auto_cast_skills(_delta: float) -> void:
	if player.get("is_casting") or player.get("_playing_skill_anim") or player.get("is_dead"):
		return
	var nearest_enemy: Node3D = _get_nearest_enemy()
	
	if nearest_enemy == null:
		return
	
	var dist_xz = _get_xz_distance(player.global_position, nearest_enemy.global_position)
	var player_speed_2d = Vector2(player.velocity.x, player.velocity.z).length()
	
	if _aa_timer <= 0 and _skill_interval_timer <= 0 and player_speed_2d < 0.5 and dist_xz <= aa_range:
		_cast_auto_attack(nearest_enemy)
		_aa_timer = aa_cooldown
		_skill_interval_timer = SKILL_AA_INTERVAL


func _get_nearest_enemy() -> Node3D:
	if _enemies_in_range.is_empty():
		return null
	
	var nearest: Node3D = null
	var nearest_distance: float = INF
	
	for enemy in _enemies_in_range:
		if not is_instance_valid(enemy):
			continue
		var dist = _get_xz_distance(player.global_position, enemy.global_position)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest = enemy
	
	return nearest


func _get_xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _get_nearest_enemy_global(from_pos: Vector3, max_range: float) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		var dist = _get_xz_distance(from_pos, enemy.global_position)
		if dist <= max_range and dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest


func can_cast_auto_attack() -> bool:
	"""攻击范围内有敌人且平A不在冷却、技能间隔已过时返回 true"""
	return _aa_timer <= 0 and _skill_interval_timer <= 0 and _get_nearest_enemy_global(player.global_position, aa_range) != null


func try_cast_auto_attack() -> bool:
	"""若攻击范围内有敌人且平A未在冷却，则释放平A并返回 true"""
	if not can_cast_auto_attack():
		return false
	var nearest = _get_nearest_enemy_global(player.global_position, aa_range)
	_cast_auto_attack(nearest)
	_aa_timer = aa_cooldown
	_skill_interval_timer = SKILL_AA_INTERVAL
	return true


func _cast_auto_attack(target: Node3D) -> void:
	# 平 A 时强制朝向目标
	var look_dir = target.global_position - player.global_position
	look_dir.y = 0
	if look_dir.length_squared() > 0.001:
		player.rotation.y = atan2(look_dir.x, look_dir.z)
	if player != null and player.has_method("play_attack_animation"):
		player.play_attack_animation()
	var direction = (target.global_position - player.global_position).normalized()
	_play_sfx(SFX_AA_FIRE)
	_spawn_projectile(
		direction,
		_ad(),
		aa_speed,
		false,
		false,
		0.0,
		Color.YELLOW,
		"normal",
		SFX_AA_HIT
	)
	print("Ezreal Auto Attack fired at ", target.name)


func cast_q_direction(direction: Vector3) -> void:
	if _q_timer > 0:
		print("Ezreal Q on cooldown: ", _q_timer)
		return
	if _skill_interval_timer > 0:
		return
	_q_timer = _get_effective_cooldown(q_cooldown, q_ability_haste)
	_skill_interval_timer = SKILL_AA_INTERVAL

	var flat_dir = Vector3(direction.x, 0, direction.z).normalized()
	if flat_dir.length_squared() < 0.001:
		flat_dir = Vector3.FORWARD

	if flat_dir.length_squared() > 0.001:
		player.rotation.y = atan2(flat_dir.x, flat_dir.z)

	player.stop_moving()
	_play_sfx(SFX_Q_FIRE)
	if player.has_method("play_skill_animation_with_transitions"):
		player.play_skill_animation_with_transitions(
			"ezreal_spell1_anm",
			"ezreal_spell1_to_idle_anm",
			"ezreal_spell1_to_run_anm"
		)

	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(player):
		return
	var q_dmg = _get_skill_damage(q_damage, Q_AD_RATIO, Q_AP_RATIO)
	var proj = _spawn_projectile(flat_dir, q_dmg, q_speed, false, false, 0.0, Color.CYAN, "comet", SFX_Q_HIT)
	if proj:
		proj.lifetime = aa_range * 2.0 / q_speed
	_unlock_skill_anim()
	_aa_timer = max(_aa_timer, SKILL_AA_INTERVAL)
	print("Ezreal Q fired in direction ", flat_dir)


func cast_w_direction(direction: Vector3) -> void:
	if _w_timer > 0:
		print("Ezreal W on cooldown: ", _w_timer)
		return
	if _skill_interval_timer > 0:
		return
	_w_timer = _get_effective_cooldown(w_cooldown, w_ability_haste)
	_skill_interval_timer = SKILL_AA_INTERVAL

	var flat_dir = Vector3(direction.x, 0, direction.z).normalized()
	if flat_dir.length_squared() < 0.001:
		flat_dir = Vector3.FORWARD

	if flat_dir.length_squared() > 0.001:
		player.rotation.y = atan2(flat_dir.x, flat_dir.z)

	player.stop_moving()
	if player.has_method("play_skill_animation_with_transitions"):
		player.play_skill_animation_with_transitions(
			"ezreal_spell2_anm",
			"ezreal_spell2_to_idle_anm",
			"ezreal_spell2_to_run_anm"
		)

	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(player):
		return
	_play_sfx(SFX_W_FIRE)
	var w_dmg = _get_skill_damage(w_damage, W_AD_RATIO, W_AP_RATIO)
	var proj = _spawn_projectile(flat_dir, w_dmg, w_speed, false, true, w_aoe_radius, Color.PURPLE, "explosive", SFX_W_HIT)
	if proj:
		proj.lifetime = aa_range * 2.0 / w_speed
	_unlock_skill_anim()
	_aa_timer = max(_aa_timer, SKILL_AA_INTERVAL)
	print("Ezreal W fired in direction ", flat_dir)


const MAP_BOUNDARY: float = 148.0

func cast_e(target_position: Vector3) -> void:
	if _e_timer > 0:
		print("Ezreal E Skill on cooldown: ", _e_timer, " seconds remaining")
		return
	if _skill_interval_timer > 0:
		return
	
	_skill_interval_timer = SKILL_AA_INTERVAL
	var direction = target_position - player.global_position
	direction.y = 0
	
	if direction.length() > e_max_distance:
		direction = direction.normalized() * e_max_distance
	
	var new_position = player.global_position + direction
	new_position = _clamp_to_map_boundary(player.global_position, new_position)
	
	if direction.length_squared() > 0.001:
		player.rotation.y = atan2(direction.x, direction.z)
	
	player.stop_moving()
	_play_sfx(SFX_E_FIRE)
	if player.has_method("play_skill_animation"):
		player.play_skill_animation("ezreal_spell3_180_anm")
	
	_e_timer = _get_effective_cooldown(e_cooldown, e_ability_haste)
	
	await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(player):
		return
	
	player.global_position = new_position
	
	var nav_agent = player.get_node_or_null("NavigationAgent3D")
	if nav_agent:
		nav_agent.set_target_position(new_position)
	
	if player.has_method("play_skill_animation"):
		player.play_skill_animation("ezreal_spell3_exit_anm")
	
	var e_dmg = _get_skill_damage(e_damage, E_AD_RATIO, E_AP_RATIO)
	var nearest_enemy = _get_nearest_enemy_global(new_position, aa_range)
	if nearest_enemy and is_instance_valid(nearest_enemy):
		var bolt_direction = (nearest_enemy.global_position - player.global_position).normalized()
		_spawn_projectile(
			bolt_direction,
			e_dmg,
			40.0,
			false,
			false,
			0.0,
			Color(0.5, 0.8, 1.0, 1.0),
			"arcane_bolt",
			SFX_Q_HIT
		)
		print("Ezreal E Skill fired arcane bolt at ", nearest_enemy.name)
	
	_unlock_skill_anim()
	_aa_timer = max(_aa_timer, SKILL_AA_INTERVAL)
	print("Ezreal E Skill used, teleported to ", new_position)


func cast_r(target_direction: Vector3) -> void:
	if _r_timer > 0:
		print("Ezreal R Skill on cooldown: ", _r_timer, " seconds remaining")
		return
	if _skill_interval_timer > 0:
		return
	_r_timer = _get_effective_cooldown(r_cooldown, r_ability_haste)
	_skill_interval_timer = SKILL_AA_INTERVAL
	
	var direction = target_direction.normalized()
	direction.y = 0
	direction = direction.normalized()
	
	if direction.length_squared() > 0.001:
		player.rotation.y = atan2(direction.x, direction.z)
	
	player.stop_moving()
	player.set("is_casting", true)
	_play_sfx(SFX_R_FIRE)
	if player.has_method("play_skill_animation_with_transitions"):
		player.play_skill_animation_with_transitions(
			"ezreal_spell4_anm",
			"ezreal_spell4_to_idle_anm",
			"ezreal_spell4_to_run_anm"
		)
	
	var anim_len = 1.0
	if player.has_method("_get_animation_length"):
		anim_len = player.call("_get_animation_length", "ezreal_spell4_anm")
	await get_tree().create_timer(anim_len).timeout
	if not is_instance_valid(player):
		return
	
	var r_dmg = _get_skill_damage(r_damage, R_AD_RATIO, R_AP_RATIO)
	_spawn_projectile(
		direction,
		r_dmg,
		r_speed,
		true,
		false,
		0.0,
		Color.GOLD,
		"crescent",
		""  # R 弹幕无单独命中音（blast 已足够）
	)
	print("Ezreal R Skill (Crescent) fired in direction ", direction)
	_aa_timer = max(_aa_timer, SKILL_AA_INTERVAL)
	
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(player):
		player.set("is_casting", false)
		player.set("_playing_skill_anim", false)


func _spawn_projectile(
	direction: Vector3,
	damage: float,
	speed: float,
	piercing: bool,
	has_aoe: bool,
	aoe_radius: float,
	color: Color,
	projectile_type: String = "normal",
	hit_sound_path: String = ""
) -> Area3D:
	var projectile: Area3D
	
	if projectile_scene:
		projectile = projectile_scene.instantiate()
	else:
		projectile = _create_projectile_by_type(projectile_type)
	
	# 2.5D 游戏中投射物水平飞行，消除 Y 方向分量
	var flat_direction = Vector3(direction.x, 0, direction.z).normalized()
	if flat_direction.length_squared() < 0.001:
		flat_direction = Vector3.FORWARD

	get_tree().root.add_child(projectile)
	
	projectile.global_position = player.global_position + Vector3(0, 1.5, 0)
	
	if projectile.has_method("setup"):
		projectile.setup(
			flat_direction,
			damage,
			speed,
			player,
			piercing,
			has_aoe,
			aoe_radius,
			hit_sound_path
		)
	
	match projectile_type:
		"normal":
			projectile.hit_radius = 0.3
		"comet":
			projectile.hit_radius = 0.3
		"explosive":
			projectile.hit_radius = 0.5
		"crescent":
			projectile.hit_radius = r_width * 0.75
		"arcane_bolt":
			projectile.hit_radius = 0.3
		_:
			projectile.hit_radius = 0.5
	
	if projectile_type != "crescent":
		var visual = projectile.get_node_or_null("Visual")
		if visual and visual is MeshInstance3D:
			var material = StandardMaterial3D.new()
			material.albedo_color = color
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 5.0
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			visual.material_override = material
	
	if projectile_type == "crescent":
		projectile.scale = Vector3(r_width * 0.6, 0.5, 1.5)

	return projectile


func _create_projectile_by_type(projectile_type: String) -> Area3D:
	var projectile = Area3D.new()
	projectile.name = "EzrealProjectile"

	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"

	var visual: MeshInstance3D

	match projectile_type:
		"normal":
			collision.shape = _create_capsule_shape(0.1, 1.4)
			collision.rotation_degrees.x = 90

			visual = MeshInstance3D.new()
			visual.name = "Visual"
			var cap = CapsuleMesh.new()
			cap.radius = 0.05
			cap.height = 1.2
			visual.mesh = cap
			visual.rotation_degrees.x = 90

			var glow = _create_glow_mesh_capsule(0.15, 1.4, Color(1.0, 0.85, 0.2, 0.25), 4.0)
			glow.rotation_degrees.x = 90
			projectile.add_child(glow)

			var outer = _create_glow_mesh_capsule(0.25, 1.6, Color(1.0, 0.7, 0.1, 0.1), 2.0)
			outer.rotation_degrees.x = 90
			projectile.add_child(outer)

		"comet":
			collision.shape = _create_capsule_shape(0.18, 2.0)
			collision.rotation_degrees.x = 90

			visual = MeshInstance3D.new()
			visual.name = "Visual"
			var cap_q = CapsuleMesh.new()
			cap_q.radius = 0.14
			cap_q.height = 1.8
			visual.mesh = cap_q
			visual.rotation_degrees.x = 90

			var glow_q = _create_glow_mesh_capsule(0.26, 2.0, Color(0.2, 0.8, 1.0, 0.3), 5.0)
			glow_q.rotation_degrees.x = 90
			projectile.add_child(glow_q)

			var outer_q = _create_glow_mesh_capsule(0.4, 2.2, Color(0.1, 0.5, 1.0, 0.1), 2.5)
			outer_q.rotation_degrees.x = 90
			projectile.add_child(outer_q)

			var tip = MeshInstance3D.new()
			var tip_mesh = SphereMesh.new()
			tip_mesh.radius = 0.22
			tip_mesh.height = 0.44
			tip.mesh = tip_mesh
			tip.position = Vector3(0, 0, -0.9)
			var tip_mat = StandardMaterial3D.new()
			tip_mat.albedo_color = Color(0.6, 0.95, 1.0, 0.9)
			tip_mat.emission_enabled = true
			tip_mat.emission = Color(0.4, 0.9, 1.0)
			tip_mat.emission_energy_multiplier = 8.0
			tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			tip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tip.material_override = tip_mat
			projectile.add_child(tip)

			var trail = GPUParticles3D.new()
			trail.name = "CometTrail"
			trail.emitting = true
			trail.amount = 24
			trail.lifetime = 0.35
			trail.explosiveness = 0.0
			trail.fixed_fps = 60
			var trail_mat = ParticleProcessMaterial.new()
			trail_mat.direction = Vector3(0, 0, 1)
			trail_mat.spread = 8.0
			trail_mat.initial_velocity_min = 1.0
			trail_mat.initial_velocity_max = 3.0
			trail_mat.gravity = Vector3.ZERO
			trail_mat.damping_min = 2.0
			trail_mat.damping_max = 4.0
			trail_mat.scale_min = 0.6
			trail_mat.scale_max = 1.0
			trail_mat.color = Color(0.3, 0.85, 1.0, 0.5)
			var trail_curve = CurveTexture.new()
			var curve = Curve.new()
			curve.add_point(Vector2(0, 1))
			curve.add_point(Vector2(1, 0))
			trail_curve.curve = curve
			trail_mat.scale_curve = trail_curve
			trail_mat.alpha_curve = trail_curve
			trail.process_material = trail_mat
			var spark_mesh = SphereMesh.new()
			spark_mesh.radius = 0.05
			spark_mesh.height = 0.1
			var spark_mat = StandardMaterial3D.new()
			spark_mat.albedo_color = Color(0.4, 0.9, 1.0, 0.7)
			spark_mat.emission_enabled = true
			spark_mat.emission = Color(0.3, 0.8, 1.0)
			spark_mat.emission_energy_multiplier = 6.0
			spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			spark_mesh.material = spark_mat
			trail.draw_pass_1 = spark_mesh
			projectile.add_child(trail)

		"explosive":
			var sphere_w = SphereShape3D.new()
			sphere_w.radius = 0.4
			collision.shape = sphere_w

			visual = MeshInstance3D.new()
			visual.name = "Visual"
			visual.mesh = _create_explosive_mesh()

			var glow_w = _create_glow_mesh_sphere(0.55, Color(0.7, 0.2, 1.0, 0.2), 4.0)
			projectile.add_child(glow_w)

		"crescent":
			var box = BoxShape3D.new()
			box.size = Vector3(r_width * 1.2, 0.6, 0.6)
			collision.shape = box

			visual = MeshInstance3D.new()
			visual.name = "Visual"
			visual.mesh = _create_crescent_mesh()
			var r_main_mat = StandardMaterial3D.new()
			r_main_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.95)
			r_main_mat.emission_enabled = true
			r_main_mat.emission = Color(1.0, 0.75, 0.15)
			r_main_mat.emission_energy_multiplier = 10.0
			r_main_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			r_main_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			r_main_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			visual.material_override = r_main_mat

			var inner_glow_r = MeshInstance3D.new()
			inner_glow_r.mesh = _create_crescent_mesh_scaled(0.85)
			var inner_mat_r = StandardMaterial3D.new()
			inner_mat_r.albedo_color = Color(1.0, 1.0, 0.85, 0.7)
			inner_mat_r.emission_enabled = true
			inner_mat_r.emission = Color(1.0, 0.95, 0.6)
			inner_mat_r.emission_energy_multiplier = 15.0
			inner_mat_r.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			inner_mat_r.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			inner_mat_r.cull_mode = BaseMaterial3D.CULL_DISABLED
			inner_glow_r.material_override = inner_mat_r
			projectile.add_child(inner_glow_r)

			var outer_glow_r = MeshInstance3D.new()
			outer_glow_r.mesh = _create_crescent_mesh_scaled(1.3)
			var outer_mat_r = StandardMaterial3D.new()
			outer_mat_r.albedo_color = Color(1.0, 0.6, 0.1, 0.15)
			outer_mat_r.emission_enabled = true
			outer_mat_r.emission = Color(1.0, 0.5, 0.05)
			outer_mat_r.emission_energy_multiplier = 4.0
			outer_mat_r.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			outer_mat_r.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			outer_mat_r.cull_mode = BaseMaterial3D.CULL_DISABLED
			outer_glow_r.material_override = outer_mat_r
			projectile.add_child(outer_glow_r)

			var core_sphere = _create_glow_mesh_sphere(0.5, Color(1.0, 0.95, 0.7, 0.6), 12.0)
			projectile.add_child(core_sphere)

			var r_trail = GPUParticles3D.new()
			r_trail.name = "RTrail"
			r_trail.emitting = true
			r_trail.amount = 40
			r_trail.lifetime = 0.5
			r_trail.explosiveness = 0.0
			r_trail.fixed_fps = 60
			var r_trail_mat = ParticleProcessMaterial.new()
			r_trail_mat.direction = Vector3(0, 0, 1)
			r_trail_mat.spread = 20.0
			r_trail_mat.initial_velocity_min = 2.0
			r_trail_mat.initial_velocity_max = 5.0
			r_trail_mat.gravity = Vector3.ZERO
			r_trail_mat.damping_min = 3.0
			r_trail_mat.damping_max = 6.0
			r_trail_mat.scale_min = 0.4
			r_trail_mat.scale_max = 1.2
			r_trail_mat.color = Color(1.0, 0.8, 0.2, 0.6)
			var r_trail_curve_tex = CurveTexture.new()
			var r_trail_curve = Curve.new()
			r_trail_curve.add_point(Vector2(0, 1))
			r_trail_curve.add_point(Vector2(0.5, 0.6))
			r_trail_curve.add_point(Vector2(1, 0))
			r_trail_curve_tex.curve = r_trail_curve
			r_trail_mat.scale_curve = r_trail_curve_tex
			r_trail_mat.alpha_curve = r_trail_curve_tex
			r_trail.process_material = r_trail_mat
			var r_spark_mesh = SphereMesh.new()
			r_spark_mesh.radius = 0.08
			r_spark_mesh.height = 0.16
			var r_spark_mat = StandardMaterial3D.new()
			r_spark_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.8)
			r_spark_mat.emission_enabled = true
			r_spark_mat.emission = Color(1.0, 0.7, 0.1)
			r_spark_mat.emission_energy_multiplier = 8.0
			r_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			r_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			r_spark_mesh.material = r_spark_mat
			r_trail.draw_pass_1 = r_spark_mesh
			projectile.add_child(r_trail)

			var r_shimmer = GPUParticles3D.new()
			r_shimmer.name = "RShimmer"
			r_shimmer.emitting = true
			r_shimmer.amount = 20
			r_shimmer.lifetime = 0.3
			r_shimmer.explosiveness = 0.0
			r_shimmer.fixed_fps = 60
			var r_shimmer_mat = ParticleProcessMaterial.new()
			r_shimmer_mat.direction = Vector3(0, 1, 0)
			r_shimmer_mat.spread = 180.0
			r_shimmer_mat.initial_velocity_min = 0.5
			r_shimmer_mat.initial_velocity_max = 2.0
			r_shimmer_mat.gravity = Vector3.ZERO
			r_shimmer_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			r_shimmer_mat.emission_box_extents = Vector3(r_width * 0.4, 0.2, 0.15)
			r_shimmer_mat.scale_min = 0.2
			r_shimmer_mat.scale_max = 0.5
			r_shimmer_mat.color = Color(1.0, 1.0, 0.7, 0.5)
			var r_shimmer_curve_tex = CurveTexture.new()
			var r_shimmer_curve = Curve.new()
			r_shimmer_curve.add_point(Vector2(0, 1))
			r_shimmer_curve.add_point(Vector2(1, 0))
			r_shimmer_curve_tex.curve = r_shimmer_curve
			r_shimmer_mat.alpha_curve = r_shimmer_curve_tex
			r_shimmer.process_material = r_shimmer_mat
			var r_dot_mesh = SphereMesh.new()
			r_dot_mesh.radius = 0.04
			r_dot_mesh.height = 0.08
			var r_dot_mat = StandardMaterial3D.new()
			r_dot_mat.albedo_color = Color(1.0, 1.0, 0.9, 0.9)
			r_dot_mat.emission_enabled = true
			r_dot_mat.emission = Color(1.0, 0.95, 0.6)
			r_dot_mat.emission_energy_multiplier = 10.0
			r_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			r_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			r_dot_mesh.material = r_dot_mat
			r_shimmer.draw_pass_1 = r_dot_mesh
			projectile.add_child(r_shimmer)

		"arcane_bolt":
			collision.shape = _create_capsule_shape(0.12, 0.8)
			collision.rotation_degrees.x = 90

			visual = MeshInstance3D.new()
			visual.name = "Visual"
			var cap_e = CapsuleMesh.new()
			cap_e.radius = 0.08
			cap_e.height = 0.7
			visual.mesh = cap_e
			visual.rotation_degrees.x = 90

			var glow_e = _create_glow_mesh_capsule(0.2, 0.9, Color(0.4, 0.75, 1.0, 0.3), 5.0)
			glow_e.rotation_degrees.x = 90
			projectile.add_child(glow_e)

			var spark = _create_glow_mesh_sphere(0.3, Color(0.6, 0.9, 1.0, 0.15), 3.0)
			projectile.add_child(spark)

		_:
			var sphere = SphereShape3D.new()
			sphere.radius = 0.3
			collision.shape = sphere

			visual = MeshInstance3D.new()
			visual.name = "Visual"
			var mesh = SphereMesh.new()
			mesh.radius = 0.3
			mesh.height = 0.6
			visual.mesh = mesh

	projectile.add_child(collision)
	projectile.add_child(visual)

	var script = load("res://scripts/ezreal_projectile.gd")
	if script:
		projectile.set_script(script)

	return projectile


func _create_glow_mesh_capsule(radius: float, height: float, color: Color, energy: float) -> MeshInstance3D:
	var glow = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	glow.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = mat
	return glow


func _create_glow_mesh_sphere(radius: float, color: Color, energy: float) -> MeshInstance3D:
	var glow = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	glow.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = mat
	return glow


func _create_capsule_shape(radius: float, height: float) -> CapsuleShape3D:
	var capsule = CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	return capsule


func _create_comet_mesh() -> Mesh:
	var arr_mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	
	var segments = 16
	var rings = 8
	
	for i in range(rings):
		var t1 = float(i) / rings
		var t2 = float(i + 1) / rings
		
		var radius1 = 0.3 * (1.0 - t1 * 0.7)
		var radius2 = 0.3 * (1.0 - t2 * 0.7)
		var z1 = t1 * 1.2 - 0.3
		var z2 = t2 * 1.2 - 0.3
		
		for j in range(segments):
			var angle1 = float(j) / segments * TAU
			var angle2 = float(j + 1) / segments * TAU
			
			vertices.append(Vector3(cos(angle1) * radius1, sin(angle1) * radius1, z1))
			vertices.append(Vector3(cos(angle2) * radius1, sin(angle2) * radius1, z1))
			vertices.append(Vector3(cos(angle1) * radius2, sin(angle1) * radius2, z2))
			
			vertices.append(Vector3(cos(angle2) * radius1, sin(angle2) * radius1, z1))
			vertices.append(Vector3(cos(angle2) * radius2, sin(angle2) * radius2, z2))
			vertices.append(Vector3(cos(angle1) * radius2, sin(angle1) * radius2, z2))
			
			for _k in range(6):
				normals.append(Vector3.FORWARD)
				uvs.append(Vector2(0.5, 0.5))
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _create_explosive_mesh() -> Mesh:
	var mesh = SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	return mesh


func _create_crescent_mesh() -> Mesh:
	return _create_crescent_mesh_scaled(1.0)


func _create_crescent_mesh_scaled(scale_factor: float) -> Mesh:
	var arr_mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	
	var outer_radius = 2.0 * scale_factor
	var inner_radius = 1.2 * scale_factor
	var thickness = 0.3 * scale_factor
	var segments = 32
	var arc_angle = PI * 0.8
	var angle_offset = -PI / 2.0
	
	for i in range(segments):
		var angle1 = angle_offset - arc_angle / 2 + float(i) / segments * arc_angle
		var angle2 = angle_offset - arc_angle / 2 + float(i + 1) / segments * arc_angle
		var outer_x1 = cos(angle1) * outer_radius
		var outer_z1 = sin(angle1) * outer_radius
		var outer_x2 = cos(angle2) * outer_radius
		var outer_z2 = sin(angle2) * outer_radius
		
		var inner_x1 = cos(angle1) * inner_radius
		var inner_z1 = sin(angle1) * inner_radius
		var inner_x2 = cos(angle2) * inner_radius
		var inner_z2 = sin(angle2) * inner_radius
		
		vertices.append(Vector3(outer_x1, thickness / 2, outer_z1))
		vertices.append(Vector3(inner_x1, thickness / 2, inner_z1))
		vertices.append(Vector3(outer_x2, thickness / 2, outer_z2))
		
		vertices.append(Vector3(inner_x1, thickness / 2, inner_z1))
		vertices.append(Vector3(inner_x2, thickness / 2, inner_z2))
		vertices.append(Vector3(outer_x2, thickness / 2, outer_z2))
		
		vertices.append(Vector3(outer_x1, -thickness / 2, outer_z1))
		vertices.append(Vector3(outer_x2, -thickness / 2, outer_z2))
		vertices.append(Vector3(inner_x1, -thickness / 2, inner_z1))
		
		vertices.append(Vector3(inner_x1, -thickness / 2, inner_z1))
		vertices.append(Vector3(outer_x2, -thickness / 2, outer_z2))
		vertices.append(Vector3(inner_x2, -thickness / 2, inner_z2))
		
		for _k in range(12):
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.5, 0.5))
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _create_arcane_bolt_mesh() -> Mesh:
	var mesh = SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	return mesh


func _clamp_to_map_boundary(from: Vector3, to: Vector3) -> Vector3:
	if abs(to.x) <= MAP_BOUNDARY and abs(to.z) <= MAP_BOUNDARY:
		return to
	var dir = to - from
	var t = 1.0
	if dir.x > 0.001 and to.x > MAP_BOUNDARY:
		t = min(t, (MAP_BOUNDARY - from.x) / dir.x)
	elif dir.x < -0.001 and to.x < -MAP_BOUNDARY:
		t = min(t, (-MAP_BOUNDARY - from.x) / dir.x)
	if dir.z > 0.001 and to.z > MAP_BOUNDARY:
		t = min(t, (MAP_BOUNDARY - from.z) / dir.z)
	elif dir.z < -0.001 and to.z < -MAP_BOUNDARY:
		t = min(t, (-MAP_BOUNDARY - from.z) / dir.z)
	var result = from + dir * max(t, 0.0)
	result.x = clamp(result.x, -MAP_BOUNDARY + 0.5, MAP_BOUNDARY - 0.5)
	result.z = clamp(result.z, -MAP_BOUNDARY + 0.5, MAP_BOUNDARY - 0.5)
	return result


func _on_detection_zone_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and body is Node3D:
		if body not in _enemies_in_range:
			_enemies_in_range.append(body)
			print("Enemy entered detection: ", body.name)


func _on_detection_zone_body_exited(body: Node) -> void:
	if body in _enemies_in_range:
		_enemies_in_range.erase(body)
		print("Enemy left detection: ", body.name)


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

func get_enemy_count() -> int:
	return _enemies_in_range.size()
