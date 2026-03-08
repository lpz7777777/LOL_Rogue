extends Node
class_name HexSkillManager
## 海克斯强化管理器：统一管理海克斯定义、应用逻辑及效果（回旋镖、狂徒等）

# 海克斯强化定义（每 5 级出现）
const HEX_DEFS: Array = [
	{"id": "hex_boomerang", "name": "回旋镖", "desc": "周期性向最近敌人释放回旋镖\n飞出至最大距离后返回\n对路径上敌人造成伤害", "color": Color(0.9, 0.5, 0.1), "icon": "magic", "heroes": "all"},
	{"id": "hex_might", "name": "海克斯之力", "desc": "AD+25\n全技能伤害提升", "color": Color(0.95, 0.35, 0.2), "icon": "attack", "heroes": "all"},
	{"id": "hex_vitality", "name": "海克斯生机", "desc": "生命上限 +200\n脱战每秒回复 2% 最大生命", "color": Color(0.2, 0.9, 0.4), "icon": "health", "heroes": "all"},
	# {"id": "hex_alacrity", "name": "海克斯迅捷", "desc": "全部技能极速 +25%\n移速 +0.5", "color": Color(0.3, 0.75, 1.0), "icon": "speed", "heroes": "all"},
	# {"id": "hex_chain", "name": "狂暴", "desc": "全部伤害 +15\n移速 +0.3", "color": Color(0.9, 0.8, 0.2), "icon": "magic", "heroes": "all"},
]

static func get_defs_for_hero(hero_name: String) -> Array:
	var result: Array = []
	for def in HEX_DEFS:
		var heroes = def.get("heroes", "all")
		var applies = (heroes is String and heroes == "all") or (heroes is Array and hero_name in heroes)
		if applies:
			result.append(def.duplicate(true))
	return result


static func apply(p: Node, skill_manager: Node, hex_id: String) -> void:
	match hex_id:
		"hex_boomerang":
			_add_hex_boomerang(p)
		"hex_might":
			if skill_manager:
				skill_manager.aa_damage += 25
				skill_manager.q_damage += 25
				if skill_manager.get("w_damage") != null: skill_manager.w_damage += 25
				if skill_manager.get("e_damage") != null: skill_manager.e_damage += 25
				skill_manager.r_damage += 25
		"hex_vitality":
			if p:
				p.max_health += 200
				var eff_max = p.max_health + PlayerInventory.get_bonus_max_health()
				p.current_health = min(p.current_health + 200, eff_max)
				_add_hex_warmog(p)
		"hex_alacrity":
			if skill_manager and skill_manager.get("ability_haste") != null:
				skill_manager.ability_haste += 25
			if p and p.get("move_speed") != null:
				p.move_speed += 0.5
		"hex_chain":
			if skill_manager:
				skill_manager.aa_damage += 15
				skill_manager.q_damage += 15
				if skill_manager.get("w_damage") != null: skill_manager.w_damage += 15
				if skill_manager.get("e_damage") != null: skill_manager.e_damage += 15
				skill_manager.r_damage += 15
			if p and p.get("move_speed") != null:
				p.move_speed += 0.3


static func _add_hex_boomerang(player: Node) -> void:
	if player == null:
		return
	var node = Node.new()
	node.set_script(_make_boomerang_script())
	node.name = "HexBoomerang"
	player.add_child(node)


static func _add_hex_warmog(player: Node) -> void:
	if player == null:
		return
	var node = Node.new()
	node.set_script(_make_warmog_script())
	node.name = "HexWarmog"
	player.add_child(node)


static func _make_boomerang_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node
var _timer: float = 0.0
var _player: Node3D = null
const C = 4.0
const D = 30.0
const SP = 18.0
const MD = 16.0
const HR = 2.0
const SC = 12.0
const BOOM = "res://assets/levelup/hex/boomerang_freefire.glb"

func _ready():
	_player = get_parent() as Node3D
	if _player == null:
		queue_free()
		return
	_fire()

func _process(delta: float):
	if _player == null or not is_instance_valid(_player):
		return
	if _player.get("is_dead"):
		return
	_timer += delta
	if _timer >= C:
		_timer = 0.0
		_fire()

func _get_nearest():
	var from = _player.global_position
	var nearest = null
	var nd = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d = Vector2(from.x - e.global_position.x, from.z - e.global_position.z).length()
		if d < nd:
			nd = d
			nearest = e
	return nearest

func _fire():
	var t = _get_nearest()
	var dir: Vector3
	if t and is_instance_valid(t):
		dir = (t.global_position - _player.global_position)
	else:
		dir = -_player.global_transform.basis.z
	dir.y = 0
	dir = dir.normalized()
	if dir.length_squared() < 0.001:
		dir = Vector3.FORWARD
	var spawn = _player.global_position + Vector3(0, 1.2, 0)
	var parent_3d = _player.get_parent() as Node3D
	if parent_3d == null:
		parent_3d = get_tree().current_scene as Node3D
	if parent_3d == null:
		return
	var proj = Area3D.new()
	proj.set_script(load("res://scripts/hex_boomerang_projectile.gd") as GDScript)
	proj.name = "BoomerangProjectile"
	parent_3d.add_child(proj)
	proj.global_position = spawn
	var scene = load(BOOM) as PackedScene
	var vis = scene.instantiate() if scene else null
	if vis:
		proj.add_child(vis)
		if vis is Node3D:
			vis.position = Vector3.ZERO
			vis.scale = Vector3(SC, SC, SC)
	else:
		var box = BoxMesh.new()
		box.size = Vector3(0.6, 0.15, 1.2)
		var m = MeshInstance3D.new()
		m.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.5, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.4, 0.05)
		m.material_override = mat
		proj.add_child(m)
	proj.setup(_player, dir, D, SP, MD, HR)
"""
	var err = s.reload()
	if err != OK:
		push_error("HexSkillManager: failed to create boomerang script: %s" % err)
	return s


static func _make_warmog_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends Node
var _player: Node = null
var _last_damage: float = -999.0
var _regen_t: float = 0.0

func _ready():
	_player = get_parent()

func _process(delta: float):
	if _player == null or not is_instance_valid(_player):
		return
	if _player.get("is_dead"):
		return
	var ch = _player.get("current_health")
	var mh = _player.get("max_health")
	if ch == null or mh == null:
		return
	var prev = _player.get_meta("_hex_warmog_last_health", ch)
	_player.set_meta("_hex_warmog_last_health", ch)
	if ch < prev - 0.01:
		_last_damage = Time.get_ticks_msec() / 1000.0
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_damage < 3.0:
		return
	if ch >= mh:
		return
	_regen_t += delta
	if _regen_t >= 1.0:
		_regen_t = 0.0
		_player.set("current_health", min(ch + mh * 0.02, mh))
		if _player.has_method("_update_hero_health_bar"):
			_player.call("_update_hero_health_bar")
"""
	var err = s.reload()
	if err != OK:
		push_error("HexSkillManager: failed to create warmog script: %s" % err)
	return s
