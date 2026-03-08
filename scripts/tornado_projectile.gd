extends Area3D
class_name TornadoProjectile

@export var speed: float = 15.0
@export var damage: float = 35.0
@export var max_range: float = 12.0
@export var knockup_duration: float = 1.0

var direction: Vector3 = Vector3.FORWARD
var owner_node: Node3D = null
var _distance_traveled: float = 0.0
var _hit_enemies: Array[Node] = []


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var velocity: Vector3 = direction * speed
	global_position += velocity * delta
	
	_distance_traveled += speed * delta
	
	rotation_degrees.y += 720 * delta
	
	if _distance_traveled >= max_range:
		queue_free()
		return


func setup(
	p_direction: Vector3,
	p_damage: float = 35.0,
	p_speed: float = 15.0,
	p_range: float = 12.0,
	p_knockup: float = 1.0,
	p_owner: Node3D = null
) -> void:
	direction = p_direction.normalized()
	damage = p_damage
	speed = p_speed
	max_range = p_range
	knockup_duration = p_knockup
	owner_node = p_owner
	
	# 【核心修复】：增加防崩溃数学校验
	if direction.length_squared() > 0.001:
		var up_vec = Vector3.UP if abs(direction.y) < 0.99 else Vector3.RIGHT
		look_at(global_position + direction, up_vec)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemy"):
		return
	if body == owner_node:
		return
	if body in _hit_enemies:
		return
	_handle_hit(body)


func _handle_hit(target: Node) -> void:
	if target in _hit_enemies:
		return
	
	_hit_enemies.append(target)
	
	if target.has_method("take_damage"):
		target.take_damage(damage)
	
	_apply_knockup(target)
	
	print("Tornado hit ", target.name, " for ", damage, " damage with knockup!")


func _apply_knockup(target: Node) -> void:
	if target.has_method("set_airborne"):
		target.set_airborne(true, knockup_duration)
		return
	
	if "airborne" in target:
		target.airborne = true
	
	if target is Node3D:
		var tween = create_tween()
		var original_y = target.global_position.y
		var peak_y = original_y + 2.0
		
		tween.tween_property(target, "global_position:y", peak_y, knockup_duration * 0.3)
		tween.tween_property(target, "global_position:y", original_y, knockup_duration * 0.7)
		
		await tween.finished
		
		if target.has_method("set_airborne"):
			target.set_airborne(false, 0.0)
		elif "airborne" in target:
			target.airborne = false
