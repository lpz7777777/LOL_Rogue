extends Node

## 玩家背包：金币、装备槽位、装备定义

signal gold_changed(new_amount: int)
signal equipment_changed(slot_index: int, item_id: StringName)

var gold: int = 0
const SLOT_COUNT: int = 6
var _equipment_slots: Array[StringName] = []  # 每个槽位: "" 或 装备 id

## 装备定义: id => { name, price, ad, ap, max_health, ability_haste, desc, icon, categories }
## categories: 用于商店筛选，"物理" "护甲" "魔法"
const ITEM_DEFS: Dictionary = {
	&"long_sword": {"name": "长剑", "price": 350, "ad": 10, "ap": 0, "max_health": 0, "ability_haste": 0, "desc": "+10 攻击力", "icon": "1036_class_t1_longsword.png", "categories": ["物理"]},
	&"blasting_wand": {"name": "爆裂魔杖", "price": 850, "ad": 0, "ap": 40, "max_health": 0, "ability_haste": 0, "desc": "+40 法术强度", "icon": "1026_mage_t1_blastingwand.png", "categories": ["魔法"]},
	&"ruby_crystal": {"name": "红水晶", "price": 400, "ad": 0, "ap": 0, "max_health": 150, "ability_haste": 0, "desc": "+150 生命值", "icon": "1028_base_t1_rubycrystal.png", "categories": ["护甲"]},
	&"bf_sword": {"name": "暴风大剑", "price": 1300, "ad": 40, "ap": 0, "max_health": 0, "ability_haste": 0, "desc": "+40 攻击力", "icon": "1038_marksman_t1_bfsword.png", "categories": ["物理"]},
	&"needlessly_large": {"name": "无用大棒", "price": 1250, "ad": 0, "ap": 60, "max_health": 0, "ability_haste": 0, "desc": "+60 法术强度", "icon": "1058_mage_t1_largerod.png", "categories": ["魔法"]},
	&"giants_belt": {"name": "巨人腰带", "price": 900, "ad": 0, "ap": 0, "max_health": 350, "ability_haste": 0, "desc": "+350 生命值", "icon": "1011_class_t2_giantsbelt.png", "categories": ["护甲"]},
	&"caulfields": {"name": "考尔菲德的战锤", "price": 1100, "ad": 25, "ap": 0, "max_health": 0, "ability_haste": 10, "desc": "+25 攻击力, +10% 技能极速", "icon": "3133_fighter_t2_caulfieldswarhammer.png", "categories": ["物理", "魔法"]},
	&"fiendish_codex": {"name": "恶魔法典", "price": 900, "ad": 0, "ap": 35, "max_health": 0, "ability_haste": 10, "desc": "+35 法强, +10% 技能极速", "icon": "3108_mage_t2_fiendishcodex.png", "categories": ["魔法"]},
	&"dirk": {"name": "锯齿短匕", "price": 1100, "ad": 30, "ap": 0, "max_health": 0, "ability_haste": 0, "desc": "+30 攻击力", "icon": "3134_assassin_t2_serrateddirk.png", "categories": ["物理"]},
	&"amplifying_tome": {"name": "增幅典籍", "price": 350, "ad": 0, "ap": 20, "max_health": 0, "ability_haste": 0, "desc": "+20 法术强度", "icon": "1052_mage_t2_amptome.png", "categories": ["魔法"]},
	&"pickaxe": {"name": "十字镐", "price": 875, "ad": 25, "ap": 0, "max_health": 0, "ability_haste": 0, "desc": "+25 攻击力", "icon": "1037_class_t1_pickaxe.png", "categories": ["物理"]},
	&"cloth_armor": {"name": "布甲", "price": 300, "ad": 0, "ap": 0, "max_health": 100, "ability_haste": 0, "desc": "+100 生命值", "icon": "1029_base_t1_clotharmor.png", "categories": ["护甲"]},
	&"trinity_force": {"name": "三相之力", "price": 3333, "ad": 35, "ap": 0, "max_health": 300, "ability_haste": 20, "desc": "+35 攻击力, +300 生命值, +20% 技能极速", "icon": "3078_fighter_t4_trinityforce.png", "categories": ["物理", "护甲", "魔法"]},
}


func _ready() -> void:
	_equipment_slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_equipment_slots[i] = &""


func reset() -> void:
	gold = 0
	for i in range(SLOT_COUNT):
		_equipment_slots[i] = &""
	gold_changed.emit(0)
	for i in range(SLOT_COUNT):
		equipment_changed.emit(i, &"")


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


func get_item_def(item_id: StringName) -> Dictionary:
	if ITEM_DEFS.has(item_id):
		return ITEM_DEFS[item_id].duplicate()
	return {}


func get_all_item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for k in ITEM_DEFS.keys():
		ids.append(k)
	return ids


## 按分类筛选装备，active_filters 为勾选的分类名数组，空则显示全部
func get_item_ids_filtered(active_filters: Array[String]) -> Array[StringName]:
	if active_filters.is_empty():
		return get_all_item_ids()
	var result: Array[StringName] = []
	for item_id in ITEM_DEFS.keys():
		var def = get_item_def(item_id)
		if def.is_empty():
			continue
		var cats = def.get("categories", [])
		if cats is Array:
			for c in cats:
				if c in active_filters:
					result.append(item_id)
					break
	return result


func get_equipped_item(slot_index: int) -> StringName:
	if slot_index >= 0 and slot_index < SLOT_COUNT:
		return _equipment_slots[slot_index]
	return &""


func can_buy(item_id: StringName) -> bool:
	var def = get_item_def(item_id)
	if def.is_empty():
		return false
	return gold >= def.price


func purchase(item_id: StringName) -> bool:
	var def = get_item_def(item_id)
	if def.is_empty():
		return false
	if gold < def.price:
		return false
	var empty_slot = -1
	for i in range(SLOT_COUNT):
		if _equipment_slots[i] == &"":
			empty_slot = i
			break
	if empty_slot < 0:
		return false  # 背包已满
	gold -= def.price
	_equipment_slots[empty_slot] = item_id
	gold_changed.emit(gold)
	equipment_changed.emit(empty_slot, item_id)
	return true


func get_bonus_ad() -> float:
	var total: float = 0.0
	for i in range(SLOT_COUNT):
		var def = get_item_def(_equipment_slots[i])
		if not def.is_empty():
			total += def.get("ad", 0)
	return total


func get_bonus_ap() -> float:
	var total: float = 0.0
	for i in range(SLOT_COUNT):
		var def = get_item_def(_equipment_slots[i])
		if not def.is_empty():
			total += def.get("ap", 0)
	return total


func get_bonus_max_health() -> float:
	var total: float = 0.0
	for i in range(SLOT_COUNT):
		var def = get_item_def(_equipment_slots[i])
		if not def.is_empty():
			total += def.get("max_health", 0)
	return total


func get_bonus_ability_haste() -> float:
	var total: float = 0.0
	for i in range(SLOT_COUNT):
		var def = get_item_def(_equipment_slots[i])
		if not def.is_empty():
			total += def.get("ability_haste", 0)
	return total
