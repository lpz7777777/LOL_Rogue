extends Area3D
class_name EzrealProjectile

@export var speed: float = 20.0

@export var damage: float = 10.0

@export var piercing: bool = false

@export var has_aoe: bool = false

@export var aoe_radius: float = 3.0

@export var lifetime: float = 5.0

var direction: Vector3 = Vector3.FORWARD

var owner_node: Node3D = null

var _lifetime_timer: float = 0.0

var _hit_targets: Array[Node] = []

var hit_radius: float = 0.5

@onready var visual: MeshInstance3D = $Visual if has_node("Visual") else null

@export var explosion_effect: PackedScene = null


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var velocity: Vector3 = direction * speed
	global_position += velocity * delta
	
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		_destroy()
		return


var hit_sound_path: String = ""

func setup(
	p_direction: Vector3,
	p_damage: float = 10.0,
	p_speed: float = 20.0,
	p_owner: Node3D = null,
	p_piercing: bool = false,
	p_aoe: bool = false,
	p_aoe_radius: float = 3.0,
	p_hit_sound_path: String = ""
) -> void:
	direction = p_direction.normalized()
	damage = p_damage
	speed = p_speed
	owner_node = p_owner
	piercing = p_piercing
	has_aoe = p_aoe
	aoe_radius = p_aoe_radius
	hit_sound_path = p_hit_sound_path
	
	# 【核心修复】：防止 direction 为 0 或与 UP 向量平行导致报错
	if direction.length_squared() > 0.001:
		var up_vec = Vector3.UP if abs(direction.y) < 0.99 else Vector3.RIGHT
		look_at(global_position + direction, up_vec)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemy"):
		return
	if body == owner_node:
		return
	if body in _hit_targets:
		return
	_handle_hit(body)


func _handle_hit(target: Node) -> void:
	if target in _hit_targets:
		return
	
	_hit_targets.append(target)
	var hit_pos = global_position  # 在可能离开场景树之前捕获位置
	
	if target.has_method("take_damage"):
		target.take_damage(damage)
		print("EzrealProjectile hit ", target.name, " for ", damage, " damage")
	
	_play_hit_sound(hit_pos)
	# 微弱的命中特效，提升打击感
	_create_hit_spark()
	
	if has_aoe:
		_trigger_aoe()
	
	if not piercing:
		_destroy()


func _play_hit_sound(pos: Vector3) -> void:
	if hit_sound_path.is_empty() or not ResourceLoader.exists(hit_sound_path):
		return
	var stream = load(hit_sound_path) as AudioStream
	if stream == null:
		return
	var audio_player = AudioStreamPlayer3D.new()
	audio_player.stream = stream
	audio_player.max_distance = 200.0
	audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	get_tree().root.add_child(audio_player)
	audio_player.global_position = pos
	audio_player.play()
	audio_player.finished.connect(audio_player.queue_free)


func _create_hit_spark() -> void:
	var root = Node3D.new()
	root.name = "HitSpark"
	get_tree().root.add_child(root)
	root.global_position = global_position
	
	var sphere = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	sphere.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.85, 1.0, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.8, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material_override = mat
	root.add_child(sphere)
	
	root.scale = Vector3(0.3, 0.3, 0.3)
	var tween = get_tree().create_tween()
	tween.bind_node(root)
	tween.tween_property(root, "scale", Vector3(1.0, 1.0, 1.0), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tween.tween_callback(root.queue_free)


func _trigger_aoe() -> void:
	if not has_aoe:
		return
	
	print("AoE explosion at ", global_position, " with radius ", aoe_radius)
	
	_create_explosion_visual()
	
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy in _hit_targets:
			continue
		var dist = global_position.distance_to(enemy.global_position)
		if dist < aoe_radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(damage)
				print("AoE hit ", enemy.name, " for ", damage, " damage")


func _create_explosion_visual() -> void:
	var explosion_root = Node3D.new()
	explosion_root.name = "ExplosionEffect"
	get_tree().root.add_child(explosion_root)
	explosion_root.global_position = global_position
	
	var sphere_visual = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = aoe_radius
	sphere_mesh.height = aoe_radius * 2
	sphere_visual.mesh = sphere_mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.4, 1.0, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 1.0)
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_visual.material_override = material
	
	explosion_root.add_child(sphere_visual)
	
	var ring_visual = MeshInstance3D.new()
	var ring_mesh = CylinderMesh.new()
	ring_mesh.top_radius = aoe_radius
	ring_mesh.bottom_radius = aoe_radius
	ring_mesh.height = 0.1
	ring_visual.mesh = ring_mesh
	
	var ring_material = StandardMaterial3D.new()
	ring_material.albedo_color = Color(1.0, 0.8, 0.2, 0.8)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.emission_enabled = true
	ring_material.emission = Color(1.0, 0.6, 0.2)
	ring_material.emission_energy_multiplier = 2.0
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_visual.material_override = ring_material
	
	explosion_root.add_child(ring_visual)
	ring_visual.rotation_degrees.x = 90
	
	# 爆炸粒子特效
	var particles = GPUParticles3D.new()
	particles.amount = 64
	particles.explosiveness = 1.0
	particles.one_shot = true
	particles.lifetime = 0.6
	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = aoe_radius * 2.0
	pm.initial_velocity_max = aoe_radius * 4.0
	pm.gravity = Vector3(0, -20, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color = Color(1.0, 0.6, 1.0, 0.95)
	particles.process_material = pm
	var quad = QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	particles.draw_pass_1 = quad
	var pts_mat = StandardMaterial3D.new()
	pts_mat.albedo_color = Color(1.0, 0.7, 1.0, 0.9)
	pts_mat.emission_enabled = true
	pts_mat.emission = Color(1.0, 0.5, 1.0)
	pts_mat.emission_energy_multiplier = 2.0
	pts_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pts_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particles.material_override = pts_mat
	explosion_root.add_child(particles)
	particles.emitting = true
	
	# 关键：绑定到新创建的节点，这样即使 EzrealProjectile 销毁了，Tween 也会继续运行
	explosion_root.scale = Vector3(0.1, 0.1, 0.1)
	var tween = get_tree().create_tween()
	tween.bind_node(explosion_root)
	
	tween.tween_property(explosion_root, "scale", Vector3(1.0, 1.0, 1.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	if sphere_visual.material_override:
		tween.parallel().tween_property(sphere_visual.material_override, "albedo_color:a", 0.0, 0.35)
	if ring_visual.material_override:
		tween.parallel().tween_property(ring_visual.material_override, "albedo_color:a", 0.0, 0.35)
	
	tween.tween_interval(0.35)
	tween.tween_callback(explosion_root.queue_free)


func _spawn_explosion_effect() -> void:
	if explosion_effect:
		var effect = explosion_effect.instantiate()
		get_tree().root.add_child(effect)
		effect.global_position = global_position


func _destroy() -> void:
	if has_aoe and _hit_targets.is_empty():
		_trigger_aoe()
	queue_free()
