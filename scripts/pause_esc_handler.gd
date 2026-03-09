extends Node

## 暂停界面 Esc 键监听，使用 _process + Input 因暂停时 _input 可能不被调用
## process_mode 需为 ALWAYS 或 WHEN_PAUSED

func _process(_delta: float) -> void:
	if not Input.is_action_just_pressed("pause"):
		return
	var hud = get_parent().get_parent()
	if hud == null:
		return
	if hud.get("_is_shop_open") and hud.has_method("_close_shop"):
		hud._close_shop()
	elif not hud.get("_is_showing_levelup") and hud.has_method("_toggle_pause"):
		hud._toggle_pause()
