extends Control

@export var background_color: Color = Color(0.08, 0.08, 0.12, 1.0)
@export var title_color: Color = Color(0.9, 0.75, 0.3, 1.0)
@export var button_color: Color = Color(0.15, 0.15, 0.2, 1.0)
@export var button_hover_color: Color = Color(0.25, 0.25, 0.35, 1.0)
@export var button_border_color: Color = Color(0.6, 0.5, 0.3, 1.0)
@export var button_text_color: Color = Color(0.95, 0.9, 0.8, 1.0)
@export var singleplayer_button_color: Color = Color(0.2, 0.15, 0.1, 1.0)
@export var singleplayer_hover_color: Color = Color(0.35, 0.25, 0.15, 1.0)


func _ready() -> void:
	_create_ui()


func _create_ui() -> void:
	var background = ColorRect.new()
	background.name = "Background"
	background.color = background_color
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_container)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 80)
	center_container.add_child(vbox)
	
	var title_label = _create_title()
	vbox.add_child(title_label)
	
	var button_container = VBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 24)
	vbox.add_child(button_container)
	
	var singleplayer_button = _create_button("Singleplayer", _on_singleplayer_pressed, true)
	button_container.add_child(singleplayer_button)
	
	var practice_button = _create_button("Practice", _on_practice_pressed)
	button_container.add_child(practice_button)
	
	var quit_button = _create_button("Quit", _on_quit_pressed)
	button_container.add_child(quit_button)


func _create_title() -> Label:
	var title = Label.new()
	title.text = "LOL ROGUE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", title_color)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	return title


func _create_button(text: String, callback: Callable, is_highlight: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(400, 80)
	
	var normal_style = StyleBoxFlat.new()
	if is_highlight:
		normal_style.bg_color = singleplayer_button_color
		normal_style.border_color = Color(0.8, 0.6, 0.3, 1.0)
	else:
		normal_style.bg_color = button_color
		normal_style.border_color = button_border_color
	normal_style.set_border_width_all(4)
	normal_style.set_corner_radius_all(12)
	normal_style.content_margin_left = 20
	normal_style.content_margin_right = 20
	normal_style.content_margin_top = 10
	normal_style.content_margin_bottom = 10
	
	var hover_style = StyleBoxFlat.new()
	if is_highlight:
		hover_style.bg_color = singleplayer_hover_color
		hover_style.border_color = Color(1.0, 0.8, 0.4, 1.0)
	else:
		hover_style.bg_color = button_hover_color
		hover_style.border_color = Color(0.8, 0.7, 0.4, 1.0)
	hover_style.set_border_width_all(4)
	hover_style.set_corner_radius_all(12)
	hover_style.content_margin_left = 20
	hover_style.content_margin_right = 20
	hover_style.content_margin_top = 10
	hover_style.content_margin_bottom = 10
	
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", hover_style)
	button.add_theme_font_size_override("font_size", 36)
	button.add_theme_color_override("font_color", button_text_color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	
	button.pressed.connect(callback)
	
	return button


func _on_singleplayer_pressed() -> void:
	Global.set_singleplayer_mode()
	Global.reset_game_stats()
	PlayerInventory.reset()
	SceneManager.go_to_hero_select()


func _on_practice_pressed() -> void:
	Global.set_practice_mode()
	Global.reset_game_stats()
	PlayerInventory.reset()
	SceneManager.go_to_hero_select()


func _on_quit_pressed() -> void:
	get_tree().quit()
