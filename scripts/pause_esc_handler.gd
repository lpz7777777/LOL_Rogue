extends Node

## 暂停界面 Esc 键监听，process_mode=ALWAYS 保证暂停时也能响应

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not event.echo:
		var hud = get_parent()
		if hud == null:
			return
		if hud.get("_is_shop_open") and hud.has_method("_close_shop"):
			hud._close_shop()
		elif not hud.get("_is_showing_levelup") and hud.has_method("_toggle_pause"):
			hud._toggle_pause()
		get_viewport().set_input_as_handled()
