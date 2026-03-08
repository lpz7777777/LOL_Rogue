extends Node3D
class_name ChaserEnemySkillManager

## 近战追击敌人的技能管理：接触伤害、近战攻击

@export_group("近战攻击")
@export var attack_range: float = 2.0
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.5

@export_group("接触伤害")
@export var contact_damage: float = 10.0
@export var contact_damage_cooldown: float = 1.0

var _attack_timer: float = 0.0
var _contact_timer: float = 0.0


func _ready() -> void:
	_attack_timer = 0.0
	_contact_timer = 0.0


func _process(delta: float) -> void:
	if _attack_timer > 0:
		_attack_timer -= delta
	if _contact_timer > 0:
		_contact_timer -= delta


## 尝试近战攻击（仅校验），成功返回 true；伤害在动画命中时机（0.3s 后）由 apply_melee_damage 施加
func try_melee_attack(owner_enemy: Node3D, target: CharacterBody3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _attack_timer > 0:
		return false
	
	var dist = Vector2(
		owner_enemy.global_position.x - target.global_position.x,
		owner_enemy.global_position.z - target.global_position.z
	).length()
	if dist > attack_range:
		return false
	
	_attack_timer = attack_cooldown
	return true


## 在攻击动画命中时刻施加伤害（由 chaser 在动画开始 0.3s 后调用）
func apply_melee_damage(_owner_enemy: Node3D, target: CharacterBody3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("take_damage"):
		target.take_damage(attack_damage)


## 接触玩家时调用，内部处理冷却
func on_contact_with_player(player: Node) -> void:
	if player == null or not player.is_in_group("player"):
		return
	if _contact_timer > 0:
		return
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)
	_contact_timer = contact_damage_cooldown


func is_attack_on_cooldown() -> bool:
	return _attack_timer > 0


func set_attack_damage(value: float) -> void:
	attack_damage = value


func set_contact_damage(value: float) -> void:
	contact_damage = value
