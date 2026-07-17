extends Node

## 아이템/제작법 카탈로그. data/ 아래 리소스 디렉터리를 스캔해 id 로 캐시한다.
##
## 새 .tres 를 디렉터리에 넣으면 코드 수정 없이 등록된다. 수동 경로 목록을 두면
## 데이터와 코드가 어긋나므로 유지하지 않는다 (설계서 14장, GAME_SCENARIO 30개 단계).
## 저장 키는 파일 경로가 아니라 리소스의 id 다.
##
## export 빌드 한계:
##   내보내기는 .tres 를 .res 로 변환하고 원본 경로에 .remap 스텁을 남긴다.
##   스캔은 .remap 을 벗겨 원본 경로로 정규화하고, 실제 해석은 ResourceLoader 에 맡긴다
##   (ResourceLoader 가 remap 을 따라간다). 다만 pck 안의 DirAccess 목록은
##   에디터/headless 와 완전히 같지 않을 수 있으므로, 등록 결과는 항상
##   tests/core/test_game_data_registry.gd 가 에디터/headless 기준으로 검증한다.
##   내보낸 빌드에서 항목이 비면 export_presets.cfg 의 리소스 필터부터 본다.

const ItemData = preload("res://scripts/resources/item_data.gd")
const RecipeData = preload("res://scripts/crafting/recipe_data.gd")

## 스캔 대상. 여기에 디렉터리를 더하는 것 말고는 아이템 추가에 코드 변경이 필요 없다.
const ITEM_DIRS: Array[String] = ["res://data/items"]
const RECIPE_DIRS: Array[String] = ["res://data/recipes"]

## 리소스로 인정하는 확장자. .remap 을 벗긴 뒤의 확장자를 본다.
const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res"]

var _items: Dictionary = {}
var _recipes: Dictionary = {}

func _ready() -> void:
	reload_catalog(ITEM_DIRS, RECIPE_DIRS)

## 디렉터리를 다시 훑어 카탈로그를 통째로 교체한다.
## 부분 갱신을 하지 않는 이유: 지워진 리소스가 캐시에 남으면 조회가 조용히 성공한다.
func reload_catalog(item_dirs: Array, recipe_dirs: Array) -> void:
	_items = _load_by_id(item_dirs, "ItemData")
	_recipes = _load_by_id(recipe_dirs, "RecipeData")

func _load_by_id(dirs: Array, kind: String) -> Dictionary:
	var out: Dictionary = {}
	for dir_path: String in dirs:
		for path: String in scan_resource_paths(dir_path):
			if not ResourceLoader.exists(path):
				continue
			var resource: Resource = load(path)
			if resource == null:
				push_error("%s: failed to load %s" % [kind, path])
				continue
			# id 없는 리소스를 파일명으로 대신 채우지 않는다 (설계서 13장).
			var raw_id: Variant = resource.get(&"id")
			if not (raw_id is StringName or raw_id is String) or String(raw_id).is_empty():
				push_error("%s: missing id in %s" % [kind, path])
				continue
			var id: StringName = StringName(raw_id)
			if out.has(id):
				push_error("%s: duplicate id %s in %s" % [kind, id, path])
				continue
			out[id] = resource
	return out

## 디렉터리의 리소스 경로를 정렬해 돌려준다. 없는 디렉터리는 빈 결과다.
## 정렬은 로드 순서를 결정적으로 만들어 중복 id 진단이 실행마다 흔들리지 않게 한다.
static func scan_resource_paths(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		var normalized: String = _normalize_resource_file(file_name)
		if normalized.is_empty():
			continue
		out.append(dir_path.path_join(normalized))
	out.sort()
	return out

## 파일명을 원본 리소스 이름으로 되돌린다. 리소스가 아니면 빈 문자열.
## export: "a.tres.remap" -> "a.tres". 에디터: "a.tres.import" 같은 부산물도 벗긴다.
static func _normalize_resource_file(file_name: String) -> String:
	var name: String = file_name
	while name.get_extension() == "remap" or name.get_extension() == "import":
		name = name.get_basename()
	if not RESOURCE_EXTENSIONS.has(name.get_extension()):
		return ""
	return name

# 설계서 13장: 누락된 데이터 리소스를 조용히 기본값으로 대체하지 않는다.
func get_item(id: StringName) -> ItemData:
	if not _items.has(id):
		push_error("Missing item data: %s" % id)
		return null
	return _items[id]

func get_recipe(id: StringName) -> RecipeData:
	return _recipes.get(id)
