extends Node

const ItemData = preload("res://scripts/resources/item_data.gd")

const ITEM_PATHS: Array[String] = [
	"res://data/items/stone.tres",
	"res://data/items/wood.tres",
	"res://data/items/bandage.tres",
	"res://data/items/raw_meat.tres",
]

var _items: Dictionary = {}

func _ready() -> void:
	for path: String in ITEM_PATHS:
		# ponytail: 아직 없는 .tres 는 건너뛴다. 누락 실패는 조회 시점(get_item)에 낸다.
		if not ResourceLoader.exists(path):
			continue
		var item: ItemData = load(path)
		_items[item.id] = item

# 설계서 13장: 누락된 데이터 리소스를 조용히 기본값으로 대체하지 않는다.
func get_item(id: StringName) -> ItemData:
	if not _items.has(id):
		push_error("Missing item data: %s" % id)
		return null
	return _items[id]
