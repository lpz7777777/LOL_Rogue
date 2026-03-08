extends CanvasLayer

var _hex_skill_manager: GDScript  # 运行时 load，避免 preload 解析顺序问题

const CIRCLE_SHADER_CODE = """
shader_type canvas_item;
void fragment() {
    float dist = distance(UV, vec2(0.5));
    if (dist > 0.5) {
        discard;
    }
}
"""

const EXP_RING_SHADER_CODE = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.05, 0.3, 0.75, 1.0);
uniform vec4 bg_color : source_color = vec4(0.1, 0.1, 0.18, 0.5);
uniform vec4 border_color : source_color = vec4(0.55, 0.45, 0.25, 0.9);
uniform float inner_radius : hint_range(0.0, 0.5) = 0.42;
uniform float outer_radius : hint_range(0.0, 0.5) = 0.50;
uniform float border_width : hint_range(0.0, 0.02) = 0.006;
void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    if (dist < inner_radius - border_width || dist > outer_radius + border_width) {
        discard;
    }
    if (dist < inner_radius || dist > outer_radius) {
        COLOR = border_color;
    } else {
        float angle = atan(uv.x, -uv.y);
        if (angle < 0.0) {
            angle += 6.283185307;
        }
        float fill = angle / 6.283185307;
        if (fill <= progress) {
            COLOR = fill_color;
        } else {
            COLOR = bg_color;
        }
    }
}
"""

var skill_manager: Node = null

@export_group("UI Config")
@export var skill_slot_size: Vector2 = Vector2(192, 192)
@export var slot_spacing: int = 18
@export var bottom_margin: int = 12
@export var background_color: Color = Color(0.15, 0.15, 0.2, 0.9)
@export var border_color: Color = Color(0.4, 0.35, 0.25, 1.0)
@export var cooldown_mask_color: Color = Color(0, 0, 0, 0.7)
@export var ready_glow_color: Color = Color(0.2, 0.6, 1.0, 0.3)

@export_group("Portrait Config")
@export var portrait_size: Vector2 = Vector2(380, 380)  # 独立头像框
@export var portrait_offset_left: int = 120  # 距离屏幕左边缘的偏移
@export var portrait_spacing: int = 10  # 头像与主 UI 栏的间距
@export var portrait_color: Color = Color(0.2, 0.3, 0.5, 1.0)
@export var portrait_border_color: Color = Color(0.6, 0.5, 0.3, 1.0)

@export_group("Stats Panel Config")
@export var stats_panel_width: float = 160.0
@export var stats_panel_color: Color = Color(0.12, 0.12, 0.18, 0.9)
@export var stats_label_color: Color = Color(0.9, 0.85, 0.7, 1.0)
@export var stats_value_color: Color = Color(0.3, 0.9, 0.5, 1.0)

var _skill_slots: Array[Dictionary] = []
var _main_container: HBoxContainer = null
var _player: CharacterBody3D = null

var _ad_label: Label = null
var _ap_label: Label = null
var _as_label: Label = null
var _ah_label: Label = null

var _hud_hp_fill: ColorRect = null
var _hud_hp_label: Label = null
var _hud_hp_wrapper: Control = null
var _exp_ring_material: ShaderMaterial = null
var _level_circle: Control = null
var _level_label: Label = null

var _levelup_overlay: Control = null
var _levelup_cards: Array = []
var _is_showing_levelup: bool = false
var _pause_overlay: Control = null
var _is_pause_menu: bool = false

# 金币与装备
var _gold_label: Label = null
var _equipment_slot_panels: Array[Panel] = []
var _shop_overlay: Control = null
var _is_shop_open: bool = false

# 计时与游戏结束
var _game_start_time: float = 0.0
var _timer_bar: Control = null
var _timer_label: Label = null
var _game_over_overlay: Control = null
var _game_over_time_label: Label = null
var _is_game_over: bool = false

# 每个强化对应的图标文件名（放在 res://assets/levelup/icons/ 下）
# heroes: "all" 或 ["Ezreal"] 或 ["Yasuo"]，仅该英雄可选此强化
var _upgrade_defs: Array = [
	{"id": "aa_damage", "name": "攻击之力", "desc": "AD+{v}", "min_v": 3.0, "max_v": 8.0, "step": 1.0, "color": Color(0.95, 0.3, 0.2), "icon": "attack", "heroes": "all"},
	{"id": "aa_speed", "name": "狂暴利刃", "desc": "攻速 +{v}%", "min_v": 8.0, "max_v": 15.0, "step": 1.0, "color": Color(1.0, 0.85, 0.15), "icon": "speed", "heroes": "all"},
	{"id": "move_speed", "name": "疾行之风", "desc": "+{v} 移速", "min_v": 0.3, "max_v": 0.8, "step": 0.1, "color": Color(0.3, 0.9, 0.4), "icon": "speed", "heroes": "all"},
	{"id": "max_health", "name": "巨人之力", "desc": "+{v} 生命上限", "min_v": 50.0, "max_v": 120.0, "step": 10.0, "color": Color(0.2, 0.85, 0.35), "icon": "health", "heroes": "all"},
	{"id": "ap", "name": "法术强化", "desc": "+{v} 法强", "min_v": 15.0, "max_v": 40.0, "step": 5.0, "color": Color(0.55, 0.2, 0.95), "icon": "magic", "heroes": ["Ezreal"]},
	{"id": "q_damage", "name": "神秘射击", "desc": "+{v} Q伤害", "min_v": 5.0, "max_v": 15.0, "step": 1.0, "color": Color(0.15, 0.8, 1.0), "icon": "magic", "heroes": ["Ezreal"]},
	{"id": "w_damage", "name": "精华涌流", "desc": "+{v} W伤害", "min_v": 5.0, "max_v": 15.0, "step": 1.0, "color": Color(0.65, 0.3, 1.0), "icon": "magic", "heroes": ["Ezreal"]},
	{"id": "e_damage", "name": "奥术跃迁", "desc": "+{v} E伤害", "min_v": 8.0, "max_v": 20.0, "step": 1.0, "color": Color(0.3, 0.55, 1.0), "icon": "magic", "heroes": ["Ezreal"]},
	{"id": "r_damage", "name": "精准弹幕", "desc": "+{v} R伤害", "min_v": 15.0, "max_v": 45.0, "step": 5.0, "color": Color(1.0, 0.75, 0.15), "icon": "magic", "heroes": ["Ezreal"]},
	{"id": "aa_range", "name": "鹰眼术", "desc": "+{v} 攻击距离", "min_v": 0.5, "max_v": 2.0, "step": 0.5, "color": Color(1.0, 0.55, 0.15), "icon": "range", "heroes": "all"},
	{"id": "tornado_damage", "name": "旋风烈斩", "desc": "+{v} 旋风伤害", "min_v": 8.0, "max_v": 20.0, "step": 2.0, "color": Color(0.4, 0.7, 1.0), "icon": "magic", "heroes": ["Yasuo"]},
	{"id": "yasuo_q_damage", "name": "斩钢闪", "desc": "+{v} Q伤害", "min_v": 5.0, "max_v": 15.0, "step": 1.0, "color": Color(0.35, 0.75, 1.0), "icon": "magic", "heroes": ["Yasuo"]},
	{"id": "e_dash_speed", "name": "踏前斩·疾", "desc": "+{v} E冲刺速度", "min_v": 2.0, "max_v": 6.0, "step": 1.0, "color": Color(0.2, 0.85, 0.9), "icon": "speed", "heroes": ["Yasuo"]},
	{"id": "e_dash_distance", "name": "踏前斩·远", "desc": "+{v} E冲刺距离", "min_v": 0.8, "max_v": 2.5, "step": 0.1, "color": Color(0.25, 0.8, 0.85), "icon": "range", "heroes": ["Yasuo"]},
	{"id": "yasuo_e_damage", "name": "踏前斩", "desc": "+{v} E伤害", "min_v": 5.0, "max_v": 15.0, "step": 1.0, "color": Color(0.3, 0.7, 0.95), "icon": "magic", "heroes": ["Yasuo"]},
	{"id": "yasuo_r_damage", "name": "狂风绝息斩", "desc": "+{v} R伤害", "min_v": 20.0, "max_v": 50.0, "step": 5.0, "color": Color(0.9, 0.5, 0.2), "icon": "magic", "heroes": ["Yasuo"]},
	{"id": "r_range", "name": "终极射程", "desc": "+{v} R技能范围", "min_v": 3.0, "max_v": 10.0, "step": 1.0, "color": Color(0.95, 0.6, 0.2), "icon": "range", "heroes": "all"},
	{"id": "q_cooldown_reduce", "name": "Q技能极速", "desc": "Q技能极速 +{v}%", "min_v": 5.0, "max_v": 12.0, "step": 1.0, "color": Color(0.3, 0.6, 1.0), "icon": "speed", "heroes": "all"},
	{"id": "r_cooldown_reduce", "name": "R技能极速", "desc": "R技能极速 +{v}%", "min_v": 8.0, "max_v": 15.0, "step": 1.0, "color": Color(0.9, 0.5, 0.2), "icon": "speed", "heroes": "all"},
	{"id": "ability_haste", "name": "技能极速", "desc": "全部技能极速 +{v}%", "min_v": 5.0, "max_v": 12.0, "step": 1.0, "color": Color(0.2, 0.6, 0.9), "icon": "speed", "heroes": "all"},
	{"id": "w_aoe_radius", "name": "精华扩散", "desc": "+{v} W范围", "min_v": 1.0, "max_v": 3.0, "step": 0.5, "color": Color(0.7, 0.35, 1.0), "icon": "range", "heroes": ["Ezreal"]},
]



func _ready() -> void:
	_hex_skill_manager = load("res://scripts/hex_skill_manager.gd") as GDScript
	_game_start_time = Time.get_ticks_msec() / 1000.0
	_create_ui()
	_create_timer_bar()
	_find_skill_manager()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _is_shop_open:
			_close_shop()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _is_game_over:
		return
	if Input.is_action_just_pressed("shop_toggle") and not _is_pause_menu:
		if _is_shop_open:
			_close_shop()
		else:
			_open_shop()
	_update_timer_display()
	_update_gold_display()
	_update_cooldown_display()
	_update_stats_display()
	_update_hud_health_bar()
	_update_exp_ring()
	_update_level_display()
	_check_levelup()


func _get_hero_name() -> String:
	return Global.current_hero


func _get_asset_path(filename: String) -> String:
	"""英雄根目录资源，如 portrait、hero_full 等"""
	var hero = _get_hero_name()
	return "res://assets/" + hero + "/" + filename


func _get_skill_icon_path(filename: String) -> String:
	"""技能图标路径，统一放在 skill/icon 子目录"""
	var hero = _get_hero_name()
	return "res://assets/" + hero + "/skill/icon/" + filename


func _find_skill_manager() -> void:
	if skill_manager != null:
		return
	
	# 获取所有加入了 "player" 分组的节点
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		
		# 尝试找 EZ 的技能管理器
		skill_manager = _player.get_node_or_null("EzrealSkillManager")
		
		# 如果没找到，说明选的是亚索，尝试找亚索的技能管理器
		if skill_manager == null:
			skill_manager = _player.get_node_or_null("YasuoSkillManager")
		
		if skill_manager != null:
			print("HUD 成功连接到技能管理器: ", skill_manager.name)

func _create_ui() -> void:
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	center_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	center_container.position.y = -bottom_margin
	
	var margin_wrapper = MarginContainer.new()
	margin_wrapper.add_theme_constant_override("margin_left", portrait_offset_left)
	center_container.add_child(margin_wrapper)
	
	# 底部横向布局：[独立头像(左)] [主 UI 栏(右)]
	var bottom_row = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", portrait_spacing)
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin_wrapper.add_child(bottom_row)
	
	# 英雄头像：独立于主 UI 栏，放在左侧，底部对齐
	var portrait = _create_portrait()
	portrait.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom_row.add_child(portrait)
	
	var main_background = PanelContainer.new()
	main_background.add_theme_stylebox_override("panel", _create_main_background_style())
	main_background.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom_row.add_child(main_background)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 0)
	main_background.add_child(main_vbox)
	
	_main_container = HBoxContainer.new()
	_main_container.add_theme_constant_override("separation", 20)
	_main_container.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(_main_container)
	
	var stats_panel = _create_stats_panel()
	_main_container.add_child(stats_panel)
	
	var skills_panel = PanelContainer.new()
	skills_panel.add_theme_stylebox_override("panel", _create_background_style())
	_main_container.add_child(skills_panel)
	
	var slots_container = HBoxContainer.new()
	slots_container.add_theme_constant_override("separation", slot_spacing)
	slots_container.add_theme_constant_override("padding_left", 18)
	slots_container.add_theme_constant_override("padding_right", 18)
	slots_container.add_theme_constant_override("padding_top", 0)
	slots_container.add_theme_constant_override("padding_bottom", 0)
	skills_panel.add_child(slots_container)
	
	_create_skill_slots(slots_container)

	var equipment_panel = _create_equipment_bar()
	_main_container.add_child(equipment_panel)
	
	var hp_bar = _create_hud_health_bar()
	main_vbox.add_child(hp_bar)
	
	add_child(center_container)
	_create_level_circle()
	_create_pause_overlay()
	_create_shop_overlay()
	_create_game_over_overlay()


@export_group("Equipment Config")
@export var equipment_slot_size: Vector2 = Vector2(90, 90)  # 使 2 行 + 间距 + 边距 = 技能栏行高 192
@export var equipment_slot_spacing: int = 4

func _create_main_background_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	style.border_color = border_color
	style.set_border_width_all(5)
	style.set_corner_radius_all(20)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 0
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, -6)
	return style


func _create_stats_panel() -> Control:
	var panel = PanelContainer.new()
	var bar_height = skill_slot_size.y  # 与技能框同高，上下贴边
	panel.custom_minimum_size = Vector2(stats_panel_width, bar_height)
	
	var style = StyleBoxFlat.new()
	style.bg_color = stats_panel_color
	style.border_color = Color(0.3, 0.28, 0.22, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "STATS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6, 1.0))
	vbox.add_child(title)
	
	_ad_label = _create_stat_row(vbox, "AD", "10")
	_ap_label = _create_stat_row(vbox, "AP", "0")
	_as_label = _create_stat_row(vbox, "AS", "1.00")
	_ah_label = _create_stat_row(vbox, "AH", "0")
	
	return panel


func _create_stat_row(container: VBoxContainer, stat_name: String, initial_value: String) -> Label:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	container.add_child(row)
	
	var name_label = Label.new()
	name_label.text = stat_name
	name_label.custom_minimum_size.x = 40
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", stats_label_color)
	row.add_child(name_label)
	
	var value_label = Label.new()
	value_label.text = initial_value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size.x = 64
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.add_theme_color_override("font_color", stats_value_color)
	value_label.add_theme_color_override("font_outline_color", Color.BLACK)
	value_label.add_theme_constant_override("outline_size", 2)
	row.add_child(value_label)
	
	return value_label


func _create_portrait() -> Control:
	var ring_thickness = 26.0
	var ring_size = portrait_size + Vector2(ring_thickness * 2, ring_thickness * 2)

	var container = Control.new()
	container.custom_minimum_size = ring_size
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var portrait_image = TextureRect.new()
	portrait_image.name = "PortraitImage"
	portrait_image.custom_minimum_size = portrait_size
	portrait_image.position = Vector2(ring_thickness, ring_thickness)
	portrait_image.size = portrait_size
	portrait_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	var texture_path = _get_asset_path("hero.jpg")
	if ResourceLoader.exists(texture_path):
		portrait_image.texture = load(texture_path)

	var shader = Shader.new()
	shader.code = CIRCLE_SHADER_CODE
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	portrait_image.material = shader_material

	container.add_child(portrait_image)

	var border_panel = Panel.new()
	border_panel.custom_minimum_size = portrait_size
	border_panel.position = Vector2(ring_thickness, ring_thickness)
	border_panel.size = portrait_size
	border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = portrait_border_color
	style.set_border_width_all(6)
	style.set_corner_radius_all(int(portrait_size.x / 2))

	border_panel.add_theme_stylebox_override("panel", style)
	container.add_child(border_panel)

	var exp_ring = ColorRect.new()
	exp_ring.custom_minimum_size = ring_size
	exp_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	exp_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ring_shader = Shader.new()
	ring_shader.code = EXP_RING_SHADER_CODE
	_exp_ring_material = ShaderMaterial.new()
	_exp_ring_material.shader = ring_shader
	_exp_ring_material.set_shader_parameter("progress", 0.0)
	_exp_ring_material.set_shader_parameter("fill_color", Color(0.05, 0.3, 0.75, 1.0))
	_exp_ring_material.set_shader_parameter("bg_color", Color(0.08, 0.08, 0.15, 0.5))
	_exp_ring_material.set_shader_parameter("border_color", Color(0.55, 0.45, 0.25, 0.9))
	var half_ring = ring_size.x / 2.0
	var half_portrait = portrait_size.x / 2.0
	_exp_ring_material.set_shader_parameter("inner_radius", half_portrait / half_ring * 0.5)
	_exp_ring_material.set_shader_parameter("outer_radius", 0.5)
	_exp_ring_material.set_shader_parameter("border_width", 0.006)
	exp_ring.material = _exp_ring_material

	container.add_child(exp_ring)

	return container


func _create_background_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(5)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(0)
	return style


func _create_equipment_bar() -> Control:
	var margin = 4
	var panel_h = skill_slot_size.y  # 与技能栏行高一致
	var wrapper = HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 8)
	wrapper.custom_minimum_size.y = panel_h
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(
		equipment_slot_size.x * 3 + equipment_slot_spacing * 2 + margin * 2,
		panel_h
	)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	style.border_color = Color(0.35, 0.3, 0.22, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	panel.add_theme_stylebox_override("panel", style)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", equipment_slot_spacing)
	grid.add_theme_constant_override("v_separation", equipment_slot_spacing)
	panel.add_child(grid)

	_equipment_slot_panels.clear()
	for i in range(6):
		var slot = Panel.new()
		slot.custom_minimum_size = equipment_slot_size
		var slot_style = StyleBoxFlat.new()
		slot_style.bg_color = Color(0.12, 0.11, 0.1, 0.95)
		slot_style.border_color = Color(0.5, 0.42, 0.3, 0.9)
		slot_style.set_border_width_all(2)
		slot_style.set_corner_radius_all(6)
		slot.add_theme_stylebox_override("panel", slot_style)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(slot)
		_equipment_slot_panels.append(slot)

	wrapper.add_child(panel)
	
	# 金币显示（装备框右侧），保持总高度与技能栏一致
	var gold_col = VBoxContainer.new()
	gold_col.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_col.add_theme_constant_override("separation", 4)
	var gold_icon = _create_gold_icon()
	gold_col.add_child(gold_icon)
	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 22)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	_gold_label.add_theme_color_override("font_outline_color", Color(0.2, 0.15, 0.05, 1.0))
	_gold_label.add_theme_constant_override("outline_size", 2)
	gold_col.add_child(_gold_label)
	wrapper.add_child(gold_col)
	
	_update_gold_display()
	PlayerInventory.gold_changed.connect(_on_gold_changed)
	PlayerInventory.equipment_changed.connect(_on_equipment_changed)

	return wrapper


func _create_skill_slots(container: HBoxContainer) -> void:
	var skills_data = [
		{"name": "AA", "key": "A", "filename": "aa"},
		{"name": "Q", "key": "Q", "filename": "q"},
		{"name": "W", "key": "W", "filename": "w"},
		{"name": "E", "key": "E", "filename": "e"},
		{"name": "R", "key": "R", "filename": "r"},
	]
	
	for i in range(skills_data.size()):
		var skill_data = skills_data[i]
		var slot = _create_single_slot(skill_data, i)
		container.add_child(slot)
		_skill_slots.append({
			"index": i,
			"name": skill_data.name,
			"cooldown_mask": slot.get_node_or_null("CooldownMask"),
			"cooldown_label": slot.get_node_or_null("CooldownLabel"),
			"background": slot.get_node_or_null("SkillBackground"),
		})


func _create_single_slot(skill_data: Dictionary, _index: int) -> Control:
	var slot = Control.new()
	slot.custom_minimum_size = skill_slot_size
	
	var background = TextureRect.new()
	background.name = "SkillBackground"
	background.custom_minimum_size = skill_slot_size
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
	var texture_path = _get_skill_icon_path(skill_data.filename + ".jpg")
	if ResourceLoader.exists(texture_path):
		background.texture = load(texture_path)
	else:
		var fallback = ColorRect.new()
		fallback.name = "FallbackColor"
		fallback.color = Color(0.3, 0.3, 0.3, 1.0)
		fallback.custom_minimum_size = skill_slot_size
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.add_child(fallback)
	
	background.add_child(_create_border())
	slot.add_child(background)
	
	var key_label = Label.new()
	key_label.text = skill_data.key
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override("font_size", 54)
	key_label.add_theme_color_override("font_color", Color.WHITE)
	key_label.add_theme_color_override("font_outline_color", Color.BLACK)
	key_label.add_theme_constant_override("outline_size", 6)
	key_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.add_child(key_label)
	
	var cooldown_mask = TextureProgressBar.new()
	cooldown_mask.name = "CooldownMask"
	cooldown_mask.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	cooldown_mask.min_value = 0.0
	cooldown_mask.max_value = 1.0
	cooldown_mask.step = 0.01
	cooldown_mask.value = 0.0
	cooldown_mask.custom_minimum_size = skill_slot_size
	cooldown_mask.visible = false
	cooldown_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var progress_texture = PlaceholderTexture2D.new()
	progress_texture.size = skill_slot_size
	cooldown_mask.texture_progress = progress_texture
	cooldown_mask.tint_progress = cooldown_mask_color
	cooldown_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	slot.add_child(cooldown_mask)
	
	var cooldown_label = Label.new()
	cooldown_label.name = "CooldownLabel"
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cooldown_label.add_theme_font_size_override("font_size", 46)
	cooldown_label.add_theme_color_override("font_color", Color.WHITE)
	cooldown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cooldown_label.add_theme_constant_override("outline_size", 6)
	cooldown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	cooldown_label.visible = false
	cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cooldown_label)
	cooldown_label.position.y += 60
	
	return slot


func _create_border() -> Control:
	var border = ReferenceRect.new()
	border.editor_only = false
	border.border_color = Color(0.6, 0.55, 0.45, 1.0)
	border.border_width = 3.0
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	return border


func _update_cooldown_display() -> void:
	if skill_manager == null:
		_find_skill_manager()
		if skill_manager == null:
			return
	
	var cooldowns = [
		skill_manager.get_aa_cooldown(),
		skill_manager.get_q_cooldown(),
		skill_manager.get_w_cooldown(),
		skill_manager.get_e_cooldown(),
		skill_manager.get_r_cooldown(),
	]
	
	var max_cooldowns = [
		skill_manager.get_aa_max_cooldown(),
		skill_manager.get_q_max_cooldown(),
		skill_manager.get_w_max_cooldown(),
		skill_manager.get_e_max_cooldown(),
		skill_manager.get_r_max_cooldown(),
	]
	
	for i in range(_skill_slots.size()):
		var slot_data = _skill_slots[i]
		var cooldown = cooldowns[i]
		var max_cd = max_cooldowns[i]
		
		var mask = slot_data.cooldown_mask
		var label = slot_data.cooldown_label
		
		if mask == null or label == null:
			continue
		
		if cooldown > 0:
			mask.visible = true
			label.visible = true
			label.text = "%.1f" % cooldown
			
			var progress = cooldown / max_cd if max_cd > 0 else 0.0
			mask.value = progress
		else:
			mask.visible = false
			label.visible = false
			mask.value = 0.0


func _create_gold_icon() -> Control:
	var icon = Panel.new()
	icon.custom_minimum_size = Vector2(24, 24)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.95, 0.78, 0.15, 1.0)
	s.border_color = Color(0.85, 0.65, 0.1, 1.0)
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	icon.add_theme_stylebox_override("panel", s)
	return icon


func _update_gold_display() -> void:
	if _gold_label:
		_gold_label.text = "%d" % PlayerInventory.gold


func _on_gold_changed(_new_amount: int) -> void:
	_update_gold_display()


func _on_equipment_changed(_slot_index: int, _item_id: StringName) -> void:
	_refresh_equipment_slot_display()


func _refresh_equipment_slot_display() -> void:
	for i in range(mini(_equipment_slot_panels.size(), PlayerInventory.SLOT_COUNT)):
		var slot = _equipment_slot_panels[i]
		for c in slot.get_children():
			c.queue_free()
		var item_id = PlayerInventory.get_equipped_item(i)
		if item_id != &"":
			var def = PlayerInventory.get_item_def(item_id)
			var icon_name: String = str(def.get("icon", ""))
			var icon_path = "res://assets/shop/" + icon_name
			var texture = ResourceLoader.load(icon_path, "Texture2D") as Texture2D
			if texture != null:
				var tex_rect = TextureRect.new()
				tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.texture = texture
				tex_rect.mouse_filter = Control.MOUSE_FILTER_STOP
				slot.add_child(tex_rect)
			else:
				var lbl = Label.new()
				lbl.text = def.get("name", "?")
				lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				lbl.add_theme_font_size_override("font_size", 14)
				lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
				lbl.add_theme_color_override("font_outline_color", Color.BLACK)
				lbl.add_theme_constant_override("outline_size", 1)
				slot.add_child(lbl)
				lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _update_stats_display() -> void:
	if skill_manager == null:
		_find_skill_manager()
		if skill_manager == null:
			return
	
	if _ad_label:
		var ad_val = skill_manager.aa_damage + PlayerInventory.get_bonus_ad()
		_ad_label.text = "%.0f" % ad_val
	
	if _ap_label:
		if skill_manager.get_class() == "EzrealSkillManager":
			var ap_val = skill_manager.ap + PlayerInventory.get_bonus_ap()
			_ap_label.text = "%.0f" % ap_val
		else:
			_ap_label.text = "0"
	
	if _as_label:
		var attack_speed = 1.0 / skill_manager.aa_cooldown
		_as_label.text = "%.2f" % attack_speed
	
	if _ah_label:
		var base_ah = skill_manager.get("ability_haste") if skill_manager.get("ability_haste") != null else 0.0
		var total_ah = base_ah + PlayerInventory.get_bonus_ability_haste()
		_ah_label.text = "%.0f%%" % total_ah


func _create_hud_health_bar() -> Control:
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(0, 24)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_hp_wrapper = wrapper

	var bg_panel = Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.08, 0.08, 0.12, 0.9)
	bar_style.border_color = Color(0.3, 0.28, 0.22, 1.0)
	bar_style.set_border_width_all(3)
	bar_style.set_corner_radius_all(8)
	bg_panel.add_theme_stylebox_override("panel", bar_style)
	wrapper.add_child(bg_panel)

	_hud_hp_fill = ColorRect.new()
	_hud_hp_fill.color = Color(0.15, 0.75, 0.25, 1.0)
	_hud_hp_fill.position = Vector2(4, 4)
	_hud_hp_fill.size = Vector2(0, 20)
	wrapper.add_child(_hud_hp_fill)

	_hud_hp_label = Label.new()
	_hud_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_hp_label.add_theme_font_size_override("font_size", 18)
	_hud_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hud_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_hp_label.add_theme_constant_override("outline_size", 3)
	_hud_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_hp_label.text = "HP"
	wrapper.add_child(_hud_hp_label)

	return wrapper


func _create_level_circle() -> void:
	var circle_size = 52.0
	_level_circle = Control.new()
	_level_circle.custom_minimum_size = Vector2(circle_size, circle_size)
	_level_circle.size = Vector2(circle_size, circle_size)
	_level_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	bg_style.border_color = Color(0.75, 0.6, 0.3, 1.0)
	bg_style.set_border_width_all(3)
	bg_style.set_corner_radius_all(int(circle_size / 2))
	bg.add_theme_stylebox_override("panel", bg_style)
	_level_circle.add_child(bg)

	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 30)
	_level_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	_level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_level_label.add_theme_constant_override("outline_size", 3)
	_level_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.text = "1"
	_level_circle.add_child(_level_label)

	add_child(_level_circle)


func _create_timer_bar() -> void:
	var top_bar = Control.new()
	top_bar.name = "TimerBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.anchor_top = 0.0
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 40
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.12, 0.85)
	top_bar.add_child(bg)
	
	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_timer_label.add_theme_font_size_override("font_size", 28)
	_timer_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_timer_label.add_theme_constant_override("outline_size", 2)
	_timer_label.text = "00:00"
	top_bar.add_child(_timer_label)
	
	_timer_bar = top_bar
	add_child(_timer_bar)


func _update_timer_display() -> void:
	if _timer_label == null:
		return
	var elapsed = Time.get_ticks_msec() / 1000.0 - _game_start_time
	var mins = int(elapsed / 60.0)
	var secs = int(fmod(elapsed, 60.0))
	_timer_label.text = "%02d:%02d" % [mins, secs]


func get_elapsed_time_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0 - _game_start_time


func _create_game_over_overlay() -> void:
	_game_over_overlay = Control.new()
	_game_over_overlay.name = "GameOverOverlay"
	_game_over_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.visible = false
	_game_over_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_game_over_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.02, 0.08, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_overlay.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_over_overlay.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 50)
	center.add_child(vbox)
	
	var title = Label.new()
	title.name = "GameOverTitle"
	title.text = "游 戏 结 束"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3))
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0.05))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	_game_over_time_label = Label.new()
	_game_over_time_label.text = "存活时间: 00:00"
	_game_over_time_label.add_theme_font_size_override("font_size", 36)
	_game_over_time_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_game_over_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_time_label)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.22, 0.18, 0.95)
	btn_style.border_color = Color(0.7, 0.6, 0.35, 1.0)
	btn_style.set_border_width_all(3)
	btn_style.set_corner_radius_all(12)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.35, 0.3, 0.22, 0.98)
	
	var restart_btn = Button.new()
	restart_btn.text = "重 新 开 始"
	restart_btn.custom_minimum_size = Vector2(280, 56)
	restart_btn.add_theme_font_size_override("font_size", 28)
	restart_btn.add_theme_stylebox_override("normal", btn_style)
	restart_btn.add_theme_stylebox_override("hover", btn_hover)
	restart_btn.pressed.connect(_on_game_over_restart)
	vbox.add_child(restart_btn)
	
	var main_menu_btn = Button.new()
	main_menu_btn.text = "返 回 主 界 面"
	main_menu_btn.custom_minimum_size = Vector2(280, 56)
	main_menu_btn.add_theme_font_size_override("font_size", 28)
	main_menu_btn.add_theme_stylebox_override("normal", btn_style)
	main_menu_btn.add_theme_stylebox_override("hover", btn_hover)
	main_menu_btn.pressed.connect(_on_game_over_main_menu)
	vbox.add_child(main_menu_btn)
	
	add_child(_game_over_overlay)


func _create_shop_overlay() -> void:
	_shop_overlay = Control.new()
	_shop_overlay.name = "ShopOverlay"
	_shop_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop_overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
	_shop_overlay.visible = false
	_shop_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_shop_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shop_ui = preload("res://scripts/shop_ui.gd").new()
	shop_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_ui.set_offsets_preset(Control.PRESET_FULL_RECT)
	shop_ui.closed.connect(_close_shop)
	_shop_overlay.add_child(shop_ui)
	add_child(_shop_overlay)


func _open_shop() -> void:
	if _shop_overlay == null or _is_shop_open:
		return
	_is_shop_open = true
	get_tree().paused = true
	_shop_overlay.visible = true


func _close_shop() -> void:
	if _shop_overlay == null or not _is_shop_open:
		return
	_is_shop_open = false
	get_tree().paused = false
	_shop_overlay.visible = false


func show_game_over() -> void:
	if _is_game_over:
		return
	_is_game_over = true
	get_tree().paused = true
	
	if _hud_hp_wrapper:
		_hud_hp_wrapper.visible = false
	if _timer_bar:
		_timer_bar.visible = false
	if _level_circle:
		_level_circle.visible = false
	
	var elapsed = get_elapsed_time_seconds()
	var mins = int(elapsed / 60.0)
	var secs = int(fmod(elapsed, 60.0))
	var time_str = "%02d:%02d" % [mins, secs]
	if _game_over_time_label:
		_game_over_time_label.text = "存活时间: " + time_str
	
	_game_over_overlay.visible = true


func _on_game_over_restart() -> void:
	get_tree().paused = false
	SceneManager.go_to_game()


func _on_game_over_main_menu() -> void:
	get_tree().paused = false
	SceneManager.go_to_main_menu()


func _update_hud_health_bar() -> void:
	if _player == null:
		_find_skill_manager()
		if _player == null:
			return
	if _hud_hp_fill == null or _hud_hp_wrapper == null:
		return

	var cur_hp = _player.get("current_health")
	var base_max = _player.get("max_health")
	if cur_hp == null or base_max == null:
		return
	var max_hp = float(base_max) + PlayerInventory.get_bonus_max_health()

	var pct = clamp(float(cur_hp) / max_hp, 0.0, 1.0)
	var margin = 4.0
	var total_w = _hud_hp_wrapper.size.x - margin * 2
	var total_h = _hud_hp_wrapper.size.y - margin * 2
	_hud_hp_fill.position = Vector2(margin, margin)
	_hud_hp_fill.size = Vector2(total_w * pct, total_h)

	if _hud_hp_label:
		_hud_hp_label.text = "%d / %d" % [int(cur_hp), int(max_hp)]


func _create_pause_overlay() -> void:
	_pause_overlay = Control.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.set_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.1, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.set_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 40)
	center.add_child(vbox)

	var title = Label.new()
	title.text = "游 戏 暂 停"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0.2, 0.15, 0.05))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var resume_btn = Button.new()
	resume_btn.text = "继 续 游 戏 (Esc)"
	resume_btn.custom_minimum_size = Vector2(280, 56)
	resume_btn.add_theme_font_size_override("font_size", 28)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.22, 0.18, 0.95)
	btn_style.border_color = Color(0.7, 0.6, 0.35, 1.0)
	btn_style.set_border_width_all(3)
	btn_style.set_corner_radius_all(12)
	resume_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.35, 0.3, 0.22, 0.98)
	resume_btn.add_theme_stylebox_override("hover", btn_hover)
	resume_btn.pressed.connect(_toggle_pause)
	vbox.add_child(resume_btn)

	add_child(_pause_overlay)

	# Esc 监听：用 ALWAYS 模式节点保证暂停时也能响应
	var esc_handler = Node.new()
	esc_handler.name = "PauseEscHandler"
	esc_handler.process_mode = Node.PROCESS_MODE_ALWAYS
	esc_handler.set_script(load("res://scripts/pause_esc_handler.gd") as GDScript)
	add_child(esc_handler)


func _update_exp_ring() -> void:
	if _player == null or _exp_ring_material == null:
		return
	var progress = _player.get("experience")
	var exp_needed = 100.0
	if _player.has_method("get_exp_progress"):
		_exp_ring_material.set_shader_parameter("progress", _player.get_exp_progress())
	elif progress != null:
		if _player.has_method("get_exp_to_next_level"):
			exp_needed = _player.get_exp_to_next_level()
		_exp_ring_material.set_shader_parameter("progress", clamp(float(progress) / exp_needed, 0.0, 1.0))


func _update_level_display() -> void:
	if _player == null or _level_circle == null or _hud_hp_wrapper == null:
		return
	var lv = _player.get("level")
	if lv != null and _level_label:
		_level_label.text = str(int(lv))
	var hp_pos = _hud_hp_wrapper.global_position
	var hp_h = _hud_hp_wrapper.size.y
	var circle_size = _level_circle.size.x
	_level_circle.global_position = Vector2(
		hp_pos.x - circle_size * 0.6,
		hp_pos.y + hp_h / 2.0 - circle_size / 2.0
	)


func set_skill_manager(manager: Node) -> void:
	skill_manager = manager


func _toggle_pause() -> void:
	if _is_showing_levelup:
		return
	if get_tree().paused:
		_is_pause_menu = false
		_pause_overlay.visible = false
		get_tree().paused = false
	else:
		_is_pause_menu = true
		_pause_overlay.visible = true
		get_tree().paused = true


func get_slot_count() -> int:
	return _skill_slots.size()


func _check_levelup() -> void:
	if _is_showing_levelup or _player == null:
		return
	var pending = _player.get("_pending_levelups")
	if pending is int and pending > 0:
		_player.set("_pending_levelups", pending - 1)
		_show_levelup_ui()


func _show_levelup_ui() -> void:
	_is_showing_levelup = true
	get_tree().paused = true

	var player_level: int = _player.get("level") if _player else 1
	var is_hex: bool = (player_level > 0 and player_level % 5 == 0)
	var upgrades: Array
	if is_hex:
		upgrades = _generate_hex_upgrades(3)
	else:
		upgrades = _generate_upgrades(3)
	_create_levelup_overlay(upgrades, is_hex)


func _generate_upgrades(count: int) -> Array:
	var hero = _get_hero_name()
	var pool: Array = []
	for def in _upgrade_defs:
		var heroes = def.get("heroes", "all")
		var applies = (heroes is String and heroes == "all") or (heroes is Array and hero in heroes)
		if applies:
			pool.append(def.duplicate(true))
	pool.shuffle()
	var result: Array = []
	for i in range(mini(count, pool.size())):
		var def = pool[i]
		var upgrade = def.duplicate()
		var value = snapped(randf_range(def.min_v, def.max_v), def.step)
		upgrade["value"] = value
		upgrade["desc"] = def.desc.replace("{v}", _format_stat_value(value))
		result.append(upgrade)
	return result


func _generate_hex_upgrades(count: int) -> Array:
	var hero = _get_hero_name()
	var pool = _hex_skill_manager.get_defs_for_hero(hero)
	pool.shuffle()
	var result: Array = []
	for i in range(mini(count, pool.size())):
		var upgrade = pool[i].duplicate()
		upgrade["value"] = 1.0
		result.append(upgrade)
	return result


func _format_stat_value(v: float) -> String:
	if abs(v - round(v)) < 0.01:
		return str(int(round(v)))
	return "%.1f" % v


func _create_levelup_overlay(upgrades: Array, is_hex: bool = false) -> void:
	_levelup_overlay = Control.new()
	_levelup_overlay.name = "LevelUpOverlay"
	_levelup_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_levelup_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_levelup_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.08, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_levelup_overlay.add_child(bg)

	var center_wrap = CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_levelup_overlay.add_child(center_wrap)

	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 50)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_wrap.add_child(main_vbox)

	var title_container = CenterContainer.new()
	title_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(title_container)

	var title_panel = PanelContainer.new()
	var title_style = StyleBoxFlat.new()
	title_style.bg_color = Color(0.06, 0.06, 0.14, 0.9)
	title_style.border_color = Color(0.8, 0.65, 0.25, 0.8)
	title_style.set_border_width_all(3)
	title_style.set_corner_radius_all(12)
	title_style.content_margin_left = 40
	title_style.content_margin_right = 40
	title_style.content_margin_top = 14
	title_style.content_margin_bottom = 14
	title_panel.add_theme_stylebox_override("panel", title_style)
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_container.add_child(title_panel)

	var title = Label.new()
	title.text = "— 海克斯强化 —" if is_hex else "— 选择一项强化 —"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.05))
	title.add_theme_constant_override("outline_size", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.add_child(title)

	var cards_center = CenterContainer.new()
	cards_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(cards_center)

	var cards_row = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 100)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_center.add_child(cards_row)

	_levelup_cards.clear()
	for upgrade in upgrades:
		var card = _create_upgrade_card(upgrade, is_hex)
		cards_row.add_child(card)
		_levelup_cards.append(card)

	add_child(_levelup_overlay)
	call_deferred("_play_cards_flip_in", _levelup_cards)


const LEVELUP_CARD_ASPECT_W: int = 9
const LEVELUP_CARD_ASPECT_H: int = 16
const LEVELUP_CARD_SCALE: int = 80

func _create_upgrade_card(upgrade: Dictionary, is_hex: bool = false) -> PanelContainer:
	var card_w = LEVELUP_CARD_ASPECT_W * LEVELUP_CARD_SCALE
	var card_h = LEVELUP_CARD_ASPECT_H * LEVELUP_CARD_SCALE

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, card_h)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.7, 0.55, 0.2, 0.8)
	style.set_border_width_all(4)
	style.set_corner_radius_all(24)
	style.set_content_margin_all(4)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var inner = Control.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.set_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(inner)

	var bg = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.set_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_path = "res://assets/levelup/background_hex.jpg" if is_hex else "res://assets/levelup/background.jpg"
	var bg_tex = load(bg_path) as Texture2D
	if bg_tex:
		bg.texture = bg_tex
	else:
		bg.color = Color(0.06, 0.06, 0.14, 0.95)
	inner.add_child(bg)

	var content = CenterContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.set_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(content)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 40)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(vbox)

	var icon_center = CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_center)

	# 图标容器：外圈光晕 + 内圈底 + 图标/色块
	var icon_container = Control.new()
	icon_container.custom_minimum_size = Vector2(144, 144)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 外层光晕（圆形描边）
	var glow_panel = Panel.new()
	glow_panel.custom_minimum_size = Vector2(144, 144)
	glow_panel.position = Vector2(0, 0)
	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.border_color = upgrade.color
	glow_style.set_border_width_all(4)
	glow_style.set_corner_radius_all(72)
	glow_style.shadow_color = Color(upgrade.color.r, upgrade.color.g, upgrade.color.b, 0.6)
	glow_style.shadow_size = 16
	glow_panel.add_theme_stylebox_override("panel", glow_style)
	glow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(glow_panel)

	# 内圈背景（居中，留边距）
	var icon_bg = Panel.new()
	icon_bg.custom_minimum_size = Vector2(120, 120)
	icon_bg.position = Vector2(12, 12)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(upgrade.color.r * 0.25, upgrade.color.g * 0.25, upgrade.color.b * 0.25, 0.9)
	bg_style.border_color = upgrade.color
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(60)
	bg_style.set_content_margin_all(8)
	icon_bg.add_theme_stylebox_override("panel", bg_style)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon_bg)

	# 图标或色块
	var icon_name = upgrade.get("icon", "")
	var icon_path = "res://assets/levelup/icons/" + str(icon_name) + ".png"
	var icon_tex: Texture2D = null
	if ResourceLoader.exists(icon_path):
		icon_tex = load(icon_path) as Texture2D

	if icon_tex:
		var icon_img = TextureRect.new()
		icon_img.custom_minimum_size = Vector2(96, 96)
		icon_img.position = Vector2(24, 24)
		icon_img.texture = icon_tex
		icon_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_img.modulate = upgrade.color.lerp(Color.WHITE, 0.7)
		icon_container.add_child(icon_img)
	else:
		var fallback_panel = Panel.new()
		fallback_panel.custom_minimum_size = Vector2(96, 96)
		fallback_panel.position = Vector2(24, 24)
		var fallback_style = StyleBoxFlat.new()
		fallback_style.bg_color = upgrade.color
		fallback_style.set_corner_radius_all(48)
		fallback_style.shadow_color = Color(upgrade.color.r, upgrade.color.g, upgrade.color.b, 0.5)
		fallback_style.shadow_size = 8
		fallback_panel.add_theme_stylebox_override("panel", fallback_style)
		fallback_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_container.add_child(fallback_panel)

	icon_center.add_child(icon_container)

	var name_label = Label.new()
	name_label.text = upgrade.name
	name_label.add_theme_font_size_override("font_size", 64)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.9))
	name_label.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(120, 6)
	sep.color = Color(0.75, 0.6, 0.25, 0.6)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	var desc_label = Label.new()
	desc_label.text = upgrade.desc
	desc_label.add_theme_font_size_override("font_size", 32)
	desc_label.add_theme_color_override("font_color", upgrade.color.lerp(Color.WHITE, 0.4))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	card.mouse_entered.connect(func():
		style.border_color = Color(1.0, 0.85, 0.3, 1.0)
		style.set_border_width_all(5)
		style.shadow_size = 18
		glow_style.shadow_size = 22
	)
	card.mouse_exited.connect(func():
		style.border_color = Color(0.7, 0.55, 0.2, 0.8)
		style.set_border_width_all(4)
		style.shadow_size = 12
		glow_style.shadow_size = 16
	)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_selected(upgrade, card)
	)

	return card


func _play_cards_flip_in(cards: Array) -> void:
	var card_w = LEVELUP_CARD_ASPECT_W * LEVELUP_CARD_SCALE
	var card_h = LEVELUP_CARD_ASPECT_H * LEVELUP_CARD_SCALE
	for i in cards.size():
		var card = cards[i]
		card.pivot_offset = Vector2(card_w / 2.0, card_h / 2.0)
		card.scale = Vector2(0.0, 0.5)
		card.modulate.a = 0.0
		var tween = get_tree().create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(i * 0.12)
		tween.tween_property(card, "scale", Vector2(1.15, 1.15), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card, "modulate:a", 1.0, 0.35)
		tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_cards_flip_out(cards: Array, selected_card: Control, on_finished: Callable = Callable()) -> void:
	var card_w = LEVELUP_CARD_ASPECT_W * LEVELUP_CARD_SCALE
	var card_h = LEVELUP_CARD_ASPECT_H * LEVELUP_CARD_SCALE
	var finish_tween: Tween = null

	# 被选中的卡片：先放大再淡出
	if selected_card and selected_card in cards:
		selected_card.pivot_offset = Vector2(card_w / 2.0, card_h / 2.0)
		var sel_tween = get_tree().create_tween()
		sel_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		sel_tween.tween_property(selected_card, "scale", Vector2(1.18, 1.18), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		sel_tween.tween_property(selected_card, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		finish_tween = sel_tween

	# 其他卡片：保持原来的旋转退出（压扁）
	var other_idx = 0
	for card in cards:
		if card == selected_card:
			continue
		card.pivot_offset = Vector2(card_w / 2.0, card_h / 2.0)
		var tween = get_tree().create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(other_idx * 0.05)
		tween.tween_property(card, "scale", Vector2(0.0, 1.0), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		other_idx += 1
		if finish_tween == null:
			finish_tween = tween

	if finish_tween and on_finished.is_valid():
		finish_tween.finished.connect(on_finished, CONNECT_ONE_SHOT)


func _on_card_selected(upgrade: Dictionary, card: Control) -> void:
	for c in _levelup_cards:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_upgrade(upgrade)
	print("选择强化: ", upgrade.name, " -> ", upgrade.desc)

	_play_cards_flip_out(_levelup_cards, card, _close_levelup_overlay)


func _close_levelup_overlay(_upgrade = null) -> void:
	if _levelup_overlay:
		_levelup_overlay.queue_free()
		_levelup_overlay = null
	_levelup_cards.clear()

	var pending = _player.get("_pending_levelups") if _player else 0
	if pending is int and pending > 0:
		_player.set("_pending_levelups", pending - 1)
		_show_levelup_ui()
	else:
		_is_showing_levelup = false
		get_tree().paused = false


func _apply_upgrade(upgrade: Dictionary) -> void:
	var value: float = upgrade.value
	match upgrade.id:
		"aa_damage":
			if skill_manager: skill_manager.aa_damage += value
		"aa_speed":
			if skill_manager: skill_manager.aa_cooldown *= (1.0 - value / 100.0)
		"move_speed":
			if _player: _player.move_speed += value
		"max_health":
			if _player:
				_player.max_health += value
				_player.current_health = min(_player.current_health + value, _player.max_health)
		"ap":
			if skill_manager and skill_manager.get_class() == "EzrealSkillManager":
				skill_manager.ap += value
		"q_damage":
			if skill_manager: skill_manager.q_damage += value
		"w_damage":
			if skill_manager: skill_manager.w_damage += value
		"e_damage":
			if skill_manager: skill_manager.e_damage += value
		"r_damage":
			if skill_manager: skill_manager.r_damage += value
		"aa_range":
			if skill_manager: skill_manager.aa_range += value
		"all_damage":
			if skill_manager:
				skill_manager.aa_damage += value
				skill_manager.q_damage += value
				if skill_manager.get("w_damage") != null: skill_manager.w_damage += value
				if skill_manager.get("e_damage") != null: skill_manager.e_damage += value
				skill_manager.r_damage += value
		"tornado_damage":
			if skill_manager and skill_manager.get_class() == "YasuoSkillManager":
				skill_manager.tornado_damage += value
		"yasuo_q_damage":
			if skill_manager: skill_manager.q_damage += value
		"e_dash_speed":
			if skill_manager and skill_manager.get_class() == "YasuoSkillManager":
				skill_manager.e_dash_speed += value
		"e_dash_distance":
			if skill_manager and skill_manager.get_class() == "YasuoSkillManager":
				skill_manager.e_dash_distance += value
		"yasuo_e_damage":
			if skill_manager and skill_manager.get_class() == "YasuoSkillManager":
				skill_manager.e_damage += value
		"yasuo_r_damage":
			if skill_manager: skill_manager.r_damage += value
		"r_range":
			if skill_manager and skill_manager.get("r_range") != null:
				skill_manager.r_range += value
		"q_cooldown_reduce":
			if skill_manager and skill_manager.get("q_ability_haste") != null:
				skill_manager.q_ability_haste += value
		"r_cooldown_reduce":
			if skill_manager and skill_manager.get("r_ability_haste") != null:
				skill_manager.r_ability_haste += value
		"ability_haste":
			if skill_manager and skill_manager.get("ability_haste") != null:
				skill_manager.ability_haste += value
		"w_aoe_radius":
			if skill_manager and skill_manager.get_class() == "EzrealSkillManager":
				skill_manager.w_aoe_radius += value
		# 海克斯强化（由 HexSkillManager 统一处理）
		"hex_boomerang", "hex_might", "hex_vitality", "hex_alacrity", "hex_chain":
			_hex_skill_manager.apply(_player, skill_manager, upgrade.id)
