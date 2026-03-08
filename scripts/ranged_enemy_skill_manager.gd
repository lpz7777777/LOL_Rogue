extends Node3D
class_name RangedEnemySkillManager

## 远程敌人的技能管理：发射飞星弹道（类似 EZ Q），仅命中英雄时造成伤害

@export_group("飞星攻击")
@export var projectile_damage: float = 12.0
@export var projectile_range: float = 25  # 攻击射程，由本 SkillManager 统一管理
var beam_range: float:
	get: return projectile_range
@export var projectile_speed: float = 18.0  # 比 EZ Q(35) 更慢
@export var attack_cooldown: float = 1.8

@export_group("视觉")
@export var projectile_color: Color = Color(1.0, 1.0, 1.0, 1.0)  # 白色子弹

var _attack_timer: float = 0.0
var _projectile_script: GDScript = null


func _ready() -> void:
	_projectile_script = load("res://scripts/ranged_enemy_projectile.gd") as GDScript


func _process(delta: float) -> void:
	_attack_timer -= delta


## 尝试发射飞星弹道，成功返回 true；弹道在攻击动画开始后 0.3s 发出
func try_fire_beam(owner_enemy: Node3D, target: CharacterBody3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _attack_timer > 0:
		return false
	
	var to_player = target.global_position - owner_enemy.global_position
	to_player.y = 0
	var dist_2d = to_player.length()
	
	if dist_2d > projectile_range:
		return false
	
	var flat_dir = to_player.normalized()
	if flat_dir.length_squared() < 0.001:
		flat_dir = Vector3.FORWARD
	
	# 攻击动画播放后 0.3s 再发出子弹
	var timer := get_tree().create_timer(0.3)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self) and is_instance_valid(owner_enemy):
			_spawn_projectile(owner_enemy, flat_dir)
	)
	
	_attack_timer = attack_cooldown
	return true


func _spawn_projectile(owner_enemy: Node3D, direction: Vector3) -> void:
	var projectile = Area3D.new()
	projectile.name = "RangedEnemyProjectile"
	if _projectile_script:
		projectile.set_script(_projectile_script)
	
	get_tree().root.add_child(projectile)
	projectile.global_position = owner_enemy.global_position + Vector3(0, 1.0, 0)
	
	if projectile.has_method("setup"):
		# 弹道最大飞行距离 ≈ 攻击范围 + 小幅缓冲，避免子弹飞得过远
		var max_dist = projectile_range + 1.5
		projectile.setup(direction, projectile_damage, projectile_speed, projectile_color, max_dist)


func is_on_cooldown() -> bool:
	return _attack_timer > 0


func set_beam_damage(value: float) -> void:
	projectile_damage = value


func set_projectile_range(value: float) -> void:
	projectile_range = value
