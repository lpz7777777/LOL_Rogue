extends StaticBody3D
class_name DummyEnemy

## 木桩敌人脚本
## 用于测试技能伤害和索敌系统

## 最大生命值
@export var max_health: float = 1000.0

## 当前生命值
var current_health: float = max_health

## 视觉模型节点
@onready var visual: MeshInstance3D = $Visual if has_node("Visual") else null

## 原始缩放
var _original_scale: Vector3 = Vector3.ONE

## 受击反馈计时器
var _hit_feedback_timer: float = 0.0

## 受击反馈持续时间
@export var hit_feedback_duration: float = 0.15

## 原始材质颜色
var _original_color: Color = Color.RED

var _health_bar: Control = null
var _health_bar_fill: ColorRect = null

@export_group("Health Bar")
@export var show_health_bar: bool = true
@export var health_bar_width: float = 20.0
@export var health_bar_height: float = 1.5
@export var health_bar_offset: float = 6.5
@export var health_bar_background_color: Color = Color(0.15, 0.15, 0.15, 0.9)
@export var health_bar_fill_color: Color = Color(0.8, 0.15, 0.15, 1.0)
@export var health_bar_border_color: Color = Color(0.0, 0.0, 0.0, 1.0)


func _ready() -> void:
	add_to_group("enemy")
	
	if visual:
		_original_scale = visual.scale
		var material = visual.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			_original_color = material.albedo_color
	
	current_health = max_health
	
	if show_health_bar:
		# 这里建议使用 call_deferred 或直接调用（如果不急于在下一行使用它）
		_create_health_bar() 
	
	print("DummyEnemy initialized: ", name)


func _process(delta: float) -> void:
	if _hit_feedback_timer > 0:
		_hit_feedback_timer -= delta
		var progress = 1.0 - (_hit_feedback_timer / hit_feedback_duration)
		var scale_factor = 1.0 + 0.1 * sin(progress * PI)
		if visual:
			visual.scale = _original_scale * scale_factor
		if visual:
			var material = visual.get_surface_override_material(0)
			if material and material is StandardMaterial3D:
				material.albedo_color = _original_color.lerp(Color.WHITE, 0.5 * (1.0 - progress))
		if _hit_feedback_timer <= 0:
			if visual:
				visual.scale = _original_scale
				var material = visual.get_surface_override_material(0)
				if material and material is StandardMaterial3D:
					material.albedo_color = _original_color
	
	if _health_bar:
		_update_health_bar_position()


func _create_health_bar() -> void:
	var billboard = Node3D.new()
	billboard.name = "HealthBarAnchor"
	billboard.position = Vector3(0, health_bar_offset, 0)
	add_child(billboard)
	
	var sprite = Sprite3D.new()
	sprite.name = "HealthBarSprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.fixed_size = true
	sprite.pixel_size = 0.01
	sprite.render_priority = 10
	sprite.texture = await _create_health_bar_texture()
	billboard.add_child(sprite)


func _create_health_bar_texture() -> Texture2D:
	var border_size = 1
	var vp_w = int(health_bar_width) + border_size * 2
	var vp_h = int(health_bar_height) + border_size * 2
	
	var viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(vp_w, vp_h)
	
	var container = Control.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(container)
	
	var border_rect = ColorRect.new()
	border_rect.color = health_bar_border_color
	border_rect.custom_minimum_size = Vector2(vp_w, vp_h)
	border_rect.position = Vector2(0, 0)
	container.add_child(border_rect)
	
	var background = ColorRect.new()
	background.color = health_bar_background_color
	background.custom_minimum_size = Vector2(health_bar_width, health_bar_height)
	background.position = Vector2(border_size, border_size)
	border_rect.add_child(background)
	
	_health_bar_fill = ColorRect.new()
	_health_bar_fill.color = health_bar_fill_color
	_health_bar_fill.custom_minimum_size = Vector2(health_bar_width, health_bar_height)
	_health_bar_fill.position = Vector2(0, 0)
	background.add_child(_health_bar_fill)
	
	_health_bar = container
	
	add_child(viewport)
	await get_tree().process_frame
	
	return viewport.get_texture()


func _update_health_bar_position() -> void:
	if _health_bar_fill == null:
		return
	_health_bar_fill.custom_minimum_size.x = health_bar_width * get_health_percent()


## 受到伤害
func take_damage(amount: float) -> void:
	current_health -= amount
	
	print("[", name, "] 受到了 ", amount, " 点伤害，剩余生命值: ", current_health)
	
	if current_health > 0:
		_trigger_hit_feedback()
	
	if current_health <= 0:
		_on_death()


## 触发受击视觉反馈
func _trigger_hit_feedback() -> void:
	_hit_feedback_timer = hit_feedback_duration
	
	if visual:
		visual.scale = _original_scale * 1.1
		var material = visual.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			material.albedo_color = Color.WHITE


## 死亡处理
func _on_death() -> void:
	print("[", name, "] 木桩被摧毁！")
	await get_tree().create_timer(1.0).timeout
	_respawn()


## 重生
func _respawn() -> void:
	current_health = max_health
	print("[", name, "] 木桩已重生！")


## 获取当前生命值百分比
func get_health_percent() -> float:
	return clamp(current_health / max_health, 0.0, 1.0)


## 重置木桩状态
func reset() -> void:
	current_health = max_health
	_hit_feedback_timer = 0.0
	if visual:
		visual.scale = _original_scale
