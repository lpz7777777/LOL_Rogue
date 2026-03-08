extends Node

## 暂停界面 Esc 键监听，process_mode=ALWAYS 保证暂停时也能响应

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.echo:
		var hud = get_parent()
		if hud and hud.has_method("_toggle_pause"):
			hud._toggle_pause()
			get_viewport().set_input_as_handled()
