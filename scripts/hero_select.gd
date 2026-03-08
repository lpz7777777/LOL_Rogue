extends Control

@export var background_color: Color = Color(0.08, 0.08, 0.12, 1.0)
@export var title_color: Color = Color(0.9, 0.75, 0.3, 1.0)
@export var hero_card_color: Color = Color(0.12, 0.12, 0.18, 1.0)
@export var hero_card_hover_color: Color = Color(0.2, 0.2, 0.3, 1.0)
@export var hero_card_border_color: Color = Color(0.5, 0.45, 0.35, 1.0)
@export var hero_selected_border_color: Color = Color(0.3, 0.7, 0.9, 1.0)

var _card_styles: Dictionary = {}


func _ready() -> void:
	_create_ui()


func _create_ui() -> void:
	var background = ColorRect.new()
	background.name = "Background"
	background.color = background_color
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 100)
	margin_container.add_theme_constant_override("margin_right", 100)
	margin_container.add_theme_constant_override("margin_top", 80)
	margin_container.add_theme_constant_override("margin_bottom", 80)
	add_child(margin_container)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 60)
	margin_container.add_child(main_vbox)
	
	var title_label = _create_title()
	main_vbox.add_child(title_label)
	
	var heroes_container = HBoxContainer.new()
	heroes_container.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes_container.add_theme_constant_override("separation", 40)
	main_vbox.add_child(heroes_container)
	
	var ezreal_card = _create_hero_card("Ezreal", "Ezreal", Color(0.3, 0.7, 0.9, 1.0))
	heroes_container.add_child(ezreal_card)
	
	var yasuo_card = _create_hero_card("Yasuo", "Yasuo", Color(0.8, 0.2, 0.2, 1.0))
	heroes_container.add_child(yasuo_card)
	
	var back_button_container = CenterContainer.new()
	main_vbox.add_child(back_button_container)
	
	var back_button = _create_back_button()
	back_button_container.add_child(back_button)


func _create_title() -> Label:
	var title = Label.new()
	title.text = "SELECT YOUR CHAMPION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", title_color)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	return title


func _create_hero_card(hero_id: String, hero_name: String, accent_color: Color) -> Control:
	var card = Control.new()
	card.custom_minimum_size = Vector2(320, 420)
	card.name = hero_id
	
	var card_background = PanelContainer.new()
	card_background.name = "CardBackground"
	card_background.custom_minimum_size = Vector2(320, 420)
	card_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = hero_card_color
	style.border_color = hero_card_border_color
	style.set_border_width_all(6)
	style.set_corner_radius_all(20)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	card_background.add_theme_stylebox_override("panel", style)
	card.add_child(card_background)
	
	_card_styles[hero_id] = {"background": card_background, "style": style}
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	card_background.add_child(vbox)
	
	var portrait = _create_hero_portrait(hero_id, accent_color)
	vbox.add_child(portrait)
	
	var name_label = Label.new()
	name_label.text = hero_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 42)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 4)
	vbox.add_child(name_label)
	
	var select_hint = Label.new()
	select_hint.text = "Click to Select"
	select_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_hint.add_theme_font_size_override("font_size", 24)
	select_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	vbox.add_child(select_hint)
	
	var button = Button.new()
	button.name = "SelectButton"
	button.text = ""
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var button_normal = StyleBoxFlat.new()
	button_normal.bg_color = Color(0, 0, 0, 0)
	button_normal.set_border_width_all(0)
	button.add_theme_stylebox_override("normal", button_normal)
	button.add_theme_stylebox_override("hover", button_normal)
	button.add_theme_stylebox_override("pressed", button_normal)
	
	card.add_child(button)
	
	button.pressed.connect(_on_hero_selected.bind(hero_id))
	button.mouse_entered.connect(_on_card_hover.bind(hero_id, true))
	button.mouse_exited.connect(_on_card_hover.bind(hero_id, false))
	
	return card


func _create_hero_portrait(hero_id: String, accent_color: Color) -> Control:
	var container = Control.new()
	container.custom_minimum_size = Vector2(200, 200)
	
	var background = ColorRect.new()
	background.color = Color(0.1, 0.1, 0.15, 1.0)
	background.custom_minimum_size = Vector2(200, 200)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(background)
	
	var border = ReferenceRect.new()
	border.editor_only = false
	border.border_color = accent_color
	border.border_width = 4.0
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(border)
	
	var hero_initial = Label.new()
	hero_initial.text = hero_id
	hero_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hero_initial.add_theme_font_size_override("font_size", 80)
	hero_initial.add_theme_color_override("font_color", accent_color)
	hero_initial.add_theme_color_override("font_outline_color", Color.BLACK)
	hero_initial.add_theme_constant_override("outline_size", 4)
	hero_initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(hero_initial)
	
	return container


func _create_back_button() -> Button:
	var button = Button.new()
	button.text = "Back"
	button.custom_minimum_size = Vector2(200, 60)
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	normal_style.border_color = Color(0.5, 0.45, 0.35, 1.0)
	normal_style.set_border_width_all(4)
	normal_style.set_corner_radius_all(12)
	
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.25, 0.25, 0.35, 1.0)
	hover_style.border_color = Color(0.7, 0.6, 0.4, 1.0)
	hover_style.set_border_width_all(4)
	hover_style.set_corner_radius_all(12)
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	
	button.pressed.connect(_on_back_pressed)
	
	return button


func _on_card_hover(hero_id: String, is_hovering: bool) -> void:
	if not _card_styles.has(hero_id):
		return
	
	var card_data = _card_styles[hero_id]
	var style: StyleBoxFlat = card_data.style
	
	if style:
		if is_hovering:
			style.bg_color = hero_card_hover_color
			style.border_color = hero_selected_border_color
		else:
			style.bg_color = hero_card_color
			style.border_color = hero_card_border_color


func _on_hero_selected(hero_id: String) -> void:
	Global.current_hero = hero_id
	SceneManager.go_to_game_with_hero(hero_id)


func _on_back_pressed() -> void:
	SceneManager.go_to_main_menu()
