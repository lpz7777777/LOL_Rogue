extends Node

## 暂停界面 Esc 键监听
## process_mode 需为 ALWAYS 或 WHEN_PAUSED

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var hud = get_parent().get_parent()
		if hud == null:
			return
		
		if hud.get("_is_shop_open") and hud.has_method("_close_shop"):
			hud._close_shop()
		elif not hud.get("_is_showing_levelup") and hud.has_method("_toggle_pause"):
			hud._toggle_pause()
			
		get_viewport().set_input_as_handled()