extends Area3D
class_name RangedEnemyProjectile

## 远程敌人的子弹弹道，仅命中英雄时造成伤害

@export var speed: float = 18.0
@export var damage: float = 12.0
@export var lifetime: float = 3.0
@export var projectile_color: Color = Color(1.0, 1.0, 1.0, 1.0)  # 白色子弹

var direction: Vector3 = Vector3.FORWARD
var _lifetime_timer: float = 0.0
var _has_hit: bool = false


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 8  # projectile
	collision_mask = 1 | 4  # env + player
	body_entered.connect(_on_body_entered)
	monitorable = false


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_lifetime_timer += delta
	if _lifetime_timer >= lifetime:
		queue_free()


func setup(p_direction: Vector3, p_damage: float, p_speed: float = 18.0, p_color: Color = Color(1.0, 1.0, 1.0, 1.0), p_max_distance: float = -1.0) -> void:
	direction = p_direction.normalized()
	damage = p_damage
	speed = p_speed
	projectile_color = p_color
	if p_max_distance > 0:
		lifetime = p_max_distance / p_speed  # 根据最大飞行距离计算存活时间
	if direction.length_squared() > 0.001:
		var up_vec = Vector3.UP if abs(direction.y) < 0.99 else Vector3.RIGHT
		look_at(global_position + direction, up_vec)
	_create_bullet_visual()


func _create_bullet_visual() -> void:
	# 子弹形：较宽弹体 + 尖弹头
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.08
	capsule.height = 0.7
	collision.shape = capsule
	collision.rotation_degrees.x = 90
	add_child(collision)
	
	# 弹体：较宽圆柱
	var body = MeshInstance3D.new()
	body.name = "Visual"
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.065
	cyl.bottom_radius = 0.08
	cyl.height = 0.55
	body.mesh = cyl
	body.rotation_degrees.x = 90
	var body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = projectile_color
	body_mat.emission_enabled = true
	body_mat.emission = projectile_color
	body_mat.emission_energy_multiplier = 1.5
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.material_override = body_mat
	add_child(body)
	
	# 弹头：小圆锥尖
	var tip = MeshInstance3D.new()
	var tip_mesh = CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.08
	tip_mesh.height = 0.18
	tip.mesh = tip_mesh
	tip.position = Vector3(0, 0, -0.36)
	tip.rotation_degrees.x = 90
	var tip_mat = StandardMaterial3D.new()
	tip_mat.albedo_color = projectile_color
	tip_mat.emission_enabled = true
	tip_mat.emission = projectile_color
	tip_mat.emission_energy_multiplier = 2.0
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip.material_override = tip_mat
	add_child(tip)
	
	# 极简拖尾：少量小粒子
	var trail = GPUParticles3D.new()
	trail.name = "BulletTrail"
	trail.emitting = true
	trail.amount = 6
	trail.lifetime = 0.12
	trail.explosiveness = 0.0
	trail.fixed_fps = 60
	var trail_mat = ParticleProcessMaterial.new()
	trail_mat.direction = Vector3(0, 0, 1)
	trail_mat.spread = 15.0
	trail_mat.initial_velocity_min = 0.5
	trail_mat.initial_velocity_max = 1.0
	trail_mat.gravity = Vector3.ZERO
	trail_mat.damping_min = 3.0
	trail_mat.damping_max = 5.0
	trail_mat.scale_min = 0.15
	trail_mat.scale_max = 0.25
	trail_mat.color = Color(projectile_color.r, projectile_color.g, projectile_color.b, 0.4)
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var trail_curve = CurveTexture.new()
	trail_curve.curve = curve
	trail_mat.scale_curve = trail_curve
	trail_mat.alpha_curve = trail_curve
	trail.process_material = trail_mat
	var dot = SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	trail.draw_pass_1 = dot
	add_child(trail)


func _create_hit_spark() -> void:
	var root = Node3D.new()
	get_tree().root.add_child(root)
	root.global_position = global_position
	var sphere = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	sphere.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.6)
	mat.emission_enabled = true
	mat.emission = projectile_color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material_override = mat
	root.add_child(sphere)
	root.scale = Vector3(0.2, 0.2, 0.2)
	var tween = get_tree().create_tween()
	tween.bind_node(root)
	tween.tween_property(root, "scale", Vector3(1.0, 1.0, 1.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.1)
	tween.tween_callback(root.queue_free)


func _on_body_entered(body: Node3D) -> void:
	if _has_hit:
		return
	if not body.is_in_group("player"):
		# 撞到墙/环境等，销毁但不造成伤害
		queue_free()
		return
	_has_hit = true
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_create_hit_spark()
	queue_free()
