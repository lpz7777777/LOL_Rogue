extends Node3D

const BGM_FIGHT_DIR: String = "res://assets/BGM/fight/"

func _ready() -> void:
	_start_bgm()
	_spawn_hero()


func _start_bgm() -> void:
	var dir = DirAccess.open(BGM_FIGHT_DIR)
	if dir == null:
		return
	var mp3_files: PackedStringArray = []
	dir.list_dir_begin()
	var file = dir.get_next()
	while file != "":
		if file.ends_with(".mp3"):
			mp3_files.append(BGM_FIGHT_DIR + file)
		file = dir.get_next()
	dir.list_dir_end()
	if mp3_files.is_empty():
		return
	var chosen = mp3_files[randi() % mp3_files.size()]
	var stream = load(chosen) as AudioStream
	if stream == null:
		return
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Master"
	player.volume_db = -8.0
	player.autoplay = true
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.finished.connect(func(): player.play())
	add_child(player)

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
