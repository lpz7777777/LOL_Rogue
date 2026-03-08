extends Control

## LOL 风格商店界面：左栏分类筛选、中栏装备列表、右栏详情与购买

signal closed

var _detail_name: Label = null
var _detail_desc: Label = null
var _detail_price: Label = null
var _gold_label: Label = null
var _item_buttons: Array[Control] = []
var _selected_item_id: StringName = &""
var _item_grid: GridContainer = null
var _grid_wrapper: CenterContainer = null
var _filter_physical: CheckBox = null
var _filter_armor: CheckBox = null
var _filter_magic: CheckBox = null
var _detail_icon_box: Panel = null
var _detail_icon_tex: TextureRect = null
const ITEM_BOX_SIZE: int = 180
const MARGIN: int = 24


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_shop_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			closed.emit()
			get_viewport().set_input_as_handled()


func _create_shop_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	bg.gui_input.connect(_on_bg_input)
	
	var shop_panel = PanelContainer.new()
	shop_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_panel.offset_left = 50
	shop_panel.offset_top = 50
	shop_panel.offset_right = -50
	shop_panel.offset_bottom = -50
	add_child(shop_panel)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.055, 0.1, 0.1)
	panel_style.border_color = Color(0.6, 0.5, 0.25, 1.0)
	panel_style.set_border_width_all(6)
	panel_style.set_corner_radius_all(20)
	panel_style.content_margin_left = MARGIN
	panel_style.content_margin_right = MARGIN
	panel_style.content_margin_top = MARGIN
	panel_style.content_margin_bottom = MARGIN
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 16
	panel_style.shadow_offset = Vector2(0, 4)
	shop_panel.add_theme_stylebox_override("panel", panel_style)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	shop_panel.add_child(main_vbox)
	
	var header = Label.new()
	header.text = "商 店  (P / ESC 关闭)"
	header.add_theme_font_size_override("font_size", 63)
	header.add_theme_color_override("font_color", Color(0.98, 0.9, 0.6, 1.0))
	header.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05, 1.0))
	header.add_theme_constant_override("outline_size", 6)
	main_vbox.add_child(header)
	
	var gold_row = HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 12)
	var gold_icon = _create_gold_icon()
	gold_row.add_child(gold_icon)
	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_font_size_override("font_size", 51)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25, 1.0))
	gold_row.add_child(_gold_label)
	main_vbox.add_child(gold_row)
	
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 0)
	content_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)
	
	# 左栏：分类筛选
	var left_wrapper = PanelContainer.new()
	var left_style = StyleBoxFlat.new()
	left_style.bg_color = Color(0.09, 0.08, 0.14, 0.95)
	left_style.set_content_margin_all(20)
	left_style.set_corner_radius_all(12)
	left_wrapper.add_theme_stylebox_override("panel", left_style)
	left_wrapper.custom_minimum_size = Vector2(220, 0)
	content_hbox.add_child(left_wrapper)
	var left_panel = VBoxContainer.new()
	left_panel.add_theme_constant_override("separation", 18)
	left_wrapper.add_child(left_panel)
	var filter_title = Label.new()
	filter_title.text = "分类筛选"
	filter_title.add_theme_font_size_override("font_size", 36)
	filter_title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.75, 1.0))
	left_panel.add_child(filter_title)
	_filter_physical = CheckBox.new()
	_filter_physical.text = "物理"
	_filter_physical.button_pressed = true
	_filter_physical.toggled.connect(_on_filter_changed)
	_filter_physical.add_theme_font_size_override("font_size", 33)
	left_panel.add_child(_filter_physical)
	_filter_armor = CheckBox.new()
	_filter_armor.text = "护甲"
	_filter_armor.button_pressed = true
	_filter_armor.toggled.connect(_on_filter_changed)
	_filter_armor.add_theme_font_size_override("font_size", 33)
	left_panel.add_child(_filter_armor)
	_filter_magic = CheckBox.new()
	_filter_magic.text = "魔法"
	_filter_magic.button_pressed = true
	_filter_magic.toggled.connect(_on_filter_changed)
	_filter_magic.add_theme_font_size_override("font_size", 33)
	left_panel.add_child(_filter_magic)
	
	# 左|中 分界线
	var sep1 = _create_vertical_divider()
	content_hbox.add_child(sep1)
	
	# 中栏：装备列表
	var center_wrapper = PanelContainer.new()
	var center_style = StyleBoxFlat.new()
	center_style.bg_color = Color(0.07, 0.065, 0.12, 0.9)
	center_style.set_content_margin_all(16)
	center_style.set_corner_radius_all(12)
	center_wrapper.add_theme_stylebox_override("panel", center_style)
	center_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_wrapper.size_flags_stretch_ratio = 1.0
	center_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(center_wrapper)
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center_wrapper.add_child(scroll)
	_grid_wrapper = CenterContainer.new()
	_grid_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid_wrapper)
	_item_grid = GridContainer.new()
	_item_grid.columns = 4
	_item_grid.add_theme_constant_override("h_separation", 20)
	_item_grid.add_theme_constant_override("v_separation", 20)
	_grid_wrapper.add_child(_item_grid)
	_refresh_item_grid()
	
	# 中|右 分界线
	var sep2 = _create_vertical_divider()
	content_hbox.add_child(sep2)
	
	# 右栏：装备图标大框 + 详情与购买
	var detail_wrapper = PanelContainer.new()
	var detail_style = StyleBoxFlat.new()
	detail_style.bg_color = Color(0.09, 0.08, 0.14, 0.95)
	detail_style.set_content_margin_all(20)
	detail_style.set_corner_radius_all(12)
	detail_wrapper.add_theme_stylebox_override("panel", detail_style)
	detail_wrapper.custom_minimum_size = Vector2(560, 0)
	detail_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_wrapper.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(detail_wrapper)
	var detail_panel = VBoxContainer.new()
	detail_panel.add_theme_constant_override("separation", 24)
	detail_wrapper.add_child(detail_panel)
	
	# 2倍装备框大小的图标展示，严格 1:1
	var icon_size = ITEM_BOX_SIZE * 2
	var icon_box_wrapper = AspectRatioContainer.new()
	icon_box_wrapper.ratio = 1.0
	icon_box_wrapper.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_box_wrapper.stretch_mode = AspectRatioContainer.STRETCH_WIDTH_CONTROLS_HEIGHT
	icon_box_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_icon_box = Panel.new()
	_detail_icon_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_icon_box.custom_minimum_size = Vector2(icon_size, icon_size)
	var icon_box_style = StyleBoxFlat.new()
	icon_box_style.bg_color = Color(0.12, 0.11, 0.18, 0.98)
	icon_box_style.border_color = Color(0.6, 0.5, 0.3, 1.0)
	icon_box_style.set_border_width_all(4)
	icon_box_style.set_corner_radius_all(14)
	_detail_icon_box.add_theme_stylebox_override("panel", icon_box_style)
	icon_box_wrapper.add_child(_detail_icon_box)
	detail_panel.add_child(icon_box_wrapper)
	_detail_icon_tex = TextureRect.new()
	_detail_icon_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_icon_box.add_child(_detail_icon_tex)
	
	var detail_title = Label.new()
	detail_title.text = "物品详情"
	detail_title.add_theme_font_size_override("font_size", 42)
	detail_title.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7, 1.0))
	detail_panel.add_child(detail_title)
	
	_detail_name = Label.new()
	_detail_name.text = "选择物品"
	_detail_name.add_theme_font_size_override("font_size", 48)
	_detail_name.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65, 1.0))
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(_detail_name)
	
	_detail_desc = Label.new()
	_detail_desc.text = ""
	_detail_desc.add_theme_font_size_override("font_size", 36)
	_detail_desc.add_theme_color_override("font_color", Color(0.88, 0.85, 0.78, 1.0))
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(_detail_desc)
	
	_detail_price = Label.new()
	_detail_price.text = ""
	_detail_price.add_theme_font_size_override("font_size", 39)
	_detail_price.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25, 1.0))
	detail_panel.add_child(_detail_price)
	
	var buy_btn = Button.new()
	buy_btn.text = "购买"
	buy_btn.add_theme_font_size_override("font_size", 42)
	buy_btn.custom_minimum_size = Vector2(0, 80)
	buy_btn.pressed.connect(_on_buy_pressed)
	var buy_style = StyleBoxFlat.new()
	buy_style.bg_color = Color(0.2, 0.5, 0.2, 0.9)
	buy_style.border_color = Color(0.4, 0.8, 0.4, 1.0)
	buy_style.set_border_width_all(3)
	buy_style.set_corner_radius_all(12)
	buy_btn.add_theme_stylebox_override("normal", buy_style)
	var buy_hover = buy_style.duplicate()
	buy_hover.bg_color = Color(0.25, 0.6, 0.25, 1.0)
	buy_btn.add_theme_stylebox_override("hover", buy_hover)
	detail_panel.add_child(buy_btn)
	
	_update_gold_display()
	PlayerInventory.gold_changed.connect(func(_arg): _update_gold_display())


func _create_vertical_divider() -> Control:
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(4, 0)
	sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sep.color = Color(0.5, 0.42, 0.25, 0.8)
	return sep


func _create_gold_icon() -> Control:
	var icon = Panel.new()
	icon.custom_minimum_size = Vector2(48, 48)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.95, 0.78, 0.15, 1.0)
	s.border_color = Color(0.85, 0.65, 0.1, 1.0)
	s.set_border_width_all(1)
	s.set_corner_radius_all(16)
	icon.add_theme_stylebox_override("panel", s)
	return icon


func _update_gold_display() -> void:
	if _gold_label:
		_gold_label.text = "%d" % PlayerInventory.gold


func _get_active_filters() -> Array[String]:
	var filters: Array[String] = []
	if _filter_physical and _filter_physical.button_pressed:
		filters.append("物理")
	if _filter_armor and _filter_armor.button_pressed:
		filters.append("护甲")
	if _filter_magic and _filter_magic.button_pressed:
		filters.append("魔法")
	return filters


func _on_filter_changed(_toggled: bool) -> void:
	_refresh_item_grid()


func _refresh_item_grid() -> void:
	if _item_grid == null:
		return
	for c in _item_grid.get_children():
		c.queue_free()
	_item_buttons.clear()
	var filters = _get_active_filters()
	var item_ids = PlayerInventory.get_item_ids_filtered(filters)
	for item_id in item_ids:
		var def = PlayerInventory.get_item_def(item_id)
		if def.is_empty():
			continue
		var item_cell = VBoxContainer.new()
		item_cell.add_theme_constant_override("separation", 8)
		item_cell.alignment = BoxContainer.ALIGNMENT_CENTER
		item_cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var box_wrapper = AspectRatioContainer.new()
		box_wrapper.ratio = 1.0
		box_wrapper.custom_minimum_size = Vector2(ITEM_BOX_SIZE, ITEM_BOX_SIZE)
		box_wrapper.stretch_mode = AspectRatioContainer.STRETCH_WIDTH_CONTROLS_HEIGHT
		box_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var box = Panel.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		var box_style = StyleBoxFlat.new()
		box_style.bg_color = Color(0.1, 0.09, 0.14, 0.98)
		box_style.border_color = Color(0.55, 0.45, 0.28, 1.0)
		box_style.set_border_width_all(3)
		box_style.set_corner_radius_all(12)
		box.add_theme_stylebox_override("panel", box_style)
		box.gui_input.connect(_on_item_box_input.bind(item_id))
		var icon_name: String = str(def.get("icon", ""))
		var icon_path = "res://assets/shop/" + icon_name
		var texture = ResourceLoader.load(icon_path, "Texture2D") as Texture2D
		if texture != null:
			var tex_rect = TextureRect.new()
			tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex_rect.set_offsets_preset(Control.PRESET_FULL_RECT)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.texture = texture
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(tex_rect)
		box_wrapper.add_child(box)
		item_cell.add_child(box_wrapper)
		var name_lbl = Label.new()
		name_lbl.text = def.get("name", "?")
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 33)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75, 1.0))
		name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		name_lbl.add_theme_constant_override("outline_size", 1)
		item_cell.add_child(name_lbl)
		_item_grid.add_child(item_cell)
		_item_buttons.append(box)


func _on_item_box_input(event: InputEvent, item_id: StringName) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_item_selected(item_id)


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		closed.emit()


func _on_item_selected(item_id: StringName) -> void:
	_selected_item_id = item_id
	var def = PlayerInventory.get_item_def(item_id)
	if def.is_empty():
		_detail_name.text = "?"
		_detail_desc.text = ""
		_detail_price.text = ""
		if _detail_icon_tex:
			_detail_icon_tex.texture = null
		return
	_detail_name.text = def.get("name", "?")
	_detail_desc.text = def.get("desc", "")
	_detail_price.text = "价格: %d" % def.get("price", 0)
	if _detail_icon_tex:
		var icon_path = "res://assets/shop/" + str(def.get("icon", ""))
		var tex = ResourceLoader.load(icon_path, "Texture2D") as Texture2D
		_detail_icon_tex.texture = tex


func _on_buy_pressed() -> void:
	if _selected_item_id == &"":
		return
	if PlayerInventory.purchase(_selected_item_id):
		_selected_item_id = &""
		_detail_name.text = "购买成功！"
		_detail_desc.text = ""
		_detail_price.text = ""
		if _detail_icon_tex:
			_detail_icon_tex.texture = null
	else:
		if PlayerInventory.gold < PlayerInventory.get_item_def(_selected_item_id).get("price", 9999):
			_detail_price.text = "金币不足！"
		else:
			_detail_price.text = "背包已满！"
