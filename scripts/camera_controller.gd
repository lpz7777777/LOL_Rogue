extends Camera3D

# 这里的偏移量决定了 2.5D 的感觉
@export var offset: Vector3 = Vector3(0, 22, 12)

func _ready() -> void:
	# 【最关键的一行】
	# 设置为 top_level 后，相机将忽略父节点的旋转和位移
	# 它会停留在世界原点，等待我们在 _process 里手动给它位置
	set_as_top_level(true)
	current = true

func _physics_process(_delta: float) -> void:
	var parent = get_parent()
	if parent:
		# 让相机的位置 = 英雄的位置 + 我们定义的偏移
		# 这样相机只会跟着人走，绝对不会跟着人转
		global_position = parent.global_position + offset
		
		# 强行让相机看向英雄的位置（确保角度正确）
		look_at(parent.global_position)
