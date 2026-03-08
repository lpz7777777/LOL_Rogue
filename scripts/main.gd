extends Node3D

func _ready() -> void:
	_spawn_hero()

func _spawn_hero() -> void:
	var hero_scene: PackedScene = null
	
	# 根据全局变量加载不同的场景文件
	if Global.current_hero == "Yasuo":
		hero_scene = load("res://scenes/Yasuo.tscn")
	else:
		hero_scene = load("res://scenes/Ezreal.tscn")
	
	if hero_scene:
		# 实例化场景
		var hero_instance = hero_scene.instantiate()
	
		# 【核心修复】：必须先 add_child，节点才算“进入场景树”
		add_child(hero_instance)
		
		# 节点进入场景树后，设置全局坐标才是安全的
		hero_instance.global_position = Vector3(0, 0.5, 0) 
		
		print("成功生成英雄: ", Global.current_hero)
	else:
		print("错误：找不到英雄场景文件！请检查路径 res://scenes/...")
