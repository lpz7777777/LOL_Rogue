extends Area3D
## 回旋镖弹体：沿方向飞出至最大距离后返回，用碰撞检测对路径上敌人造成伤害

var _owner: Node3D = null
var _direction: Vector3 = Vector3.FORWARD
var _damage: float = 30.0
var _speed: float = 18.0
var _max_distance: float = 16.0
var _hit_radius: float = 2.0

var _traveled: float = 0.0
var _returning: bool = false
var _hit_targets: Array[Node] = []
var _return_timeout: float = 10.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	var shape = CollisionShape3D.new()
	shape.name = "BoomerangCollision"
	shape.shape = SphereShape3D.new()
	shape.shape.radius = _hit_radius
	add_child(shape)


func setup(owner_node: Node3D, dir: Vector3, dmg: float, spd: float, max_dist: float, radius: float) -> void:
	_owner = owner_node
	_direction = dir.normalized()
	_damage = dmg
	_speed = spd
	_max_distance = max_dist
	_hit_radius = radius
	# 更新碰撞体半径
	var shape_node = get_node_or_null("BoomerangCollision")
	if shape_node is CollisionShape3D and shape_node.shape is SphereShape3D:
		shape_node.shape.radius = radius


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemy"):
		return
	if body == _owner or body in _hit_targets:
		return
	_hit_targets.append(body)
	if body.has_method("take_damage"):
		body.take_damage(_damage)
		print("Boomerang hit ", body.name, " for ", _damage, " damage")


func _physics_process(delta: float) -> void:
	if _owner == null or not is_instance_valid(_owner):
		queue_free()
		return

	if _returning:
		# 收回时：追着英雄，朝英雄当前位置飞行
		var target_pos = _owner.global_position + Vector3(0, 1.2, 0)
		_direction = (target_pos - global_position)
		_direction.y = 0
		if _direction.length_squared() > 0.001:
			_direction = _direction.normalized()
		else:
			queue_free()
			return
		_return_timeout -= delta
		if _return_timeout <= 0:
			queue_free()
			return
		var dist_xz = Vector2(global_position.x - _owner.global_position.x, global_position.z - _owner.global_position.z).length()
		if dist_xz < 1.0:
			queue_free()
			return

	var move = _speed * delta
	global_position += _direction * move
	_traveled += move

	# 旋转视觉效果（整体旋转）
	rotate_y(delta * 12.0)

	if not _returning:
		if _traveled >= _max_distance:
			_returning = true
			_hit_targets.clear()


