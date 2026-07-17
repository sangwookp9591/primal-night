extends GutTest

## GameData 는 data/items, data/recipes 를 디렉터리 스캔해 자동 등록한다 (설계서 14장).
## 새 .tres 를 넣을 때 코드를 고쳐야 한다면 이 테스트가 깨진다.

const GameDataScript = preload("res://scripts/core/game_data.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

const TEMP_DIR: String = "res://tests/.tmp_catalog"

var _game_data: Node = null

func before_each() -> void:
	_game_data = get_node("/root/GameData")
	_remove_temp_dir()

func after_each() -> void:
	_remove_temp_dir()

func _remove_temp_dir() -> void:
	var dir: DirAccess = DirAccess.open(TEMP_DIR)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(TEMP_DIR)

func _make_temp_dir() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)

## 파일시스템을 진실의 원천으로 삼는다. 목록을 테스트에 다시 적으면
## 하드코딩 배열을 다른 곳으로 옮긴 것에 불과하다.
func _resource_files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	assert_not_null(dir, "%s 디렉터리를 열 수 있어야 한다" % dir_path)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		if file_name.get_extension() == "tres":
			out.append(dir_path.path_join(file_name))
	return out


func test_every_item_resource_in_data_dir_is_registered() -> void:
	var paths: PackedStringArray = _resource_files("res://data/items")
	assert_gt(paths.size(), 0, "전제: data/items 에 아이템 리소스가 있다")

	for path: String in paths:
		var item: ItemData = load(path)
		assert_not_null(item, "%s 를 ItemData 로 읽을 수 있어야 한다" % path)
		if item == null:
			continue
		var registered: ItemData = _game_data.get_item(item.id)
		assert_not_null(registered, "%s 가 자동 등록되어야 한다 (수동 목록 금지)" % item.id)
		assert_eq(registered.id, item.id, "등록 키와 ItemData.id 가 일치해야 한다")


func test_every_recipe_resource_in_data_dir_is_registered() -> void:
	var paths: PackedStringArray = _resource_files("res://data/recipes")
	assert_gt(paths.size(), 0, "전제: data/recipes 에 제작법 리소스가 있다")

	for path: String in paths:
		var recipe: RecipeData = load(path)
		assert_not_null(recipe, "%s 를 RecipeData 로 읽을 수 있어야 한다" % path)
		if recipe == null:
			continue
		var registered: RecipeData = _game_data.get_recipe(recipe.id)
		assert_not_null(registered, "%s 가 자동 등록되어야 한다 (수동 목록 금지)" % recipe.id)
		assert_eq(registered.id, recipe.id, "등록 키와 RecipeData.id 가 일치해야 한다")


## 후속 작업이 의존하는 핵심 계약: 파일만 추가하면 코드 수정 없이 등록된다.
func test_new_item_file_is_registered_without_code_change() -> void:
	_make_temp_dir()
	var item: ItemData = ItemDataScript.new()
	item.id = &"tmp_scan_probe"
	item.display_name = "스캔 탐침"
	item.weight = 1.0
	assert_eq(ResourceSaver.save(item, TEMP_DIR.path_join("tmp_scan_probe.tres")), OK)

	var registry: Node = autofree(GameDataScript.new())
	registry.reload_catalog([TEMP_DIR], [])

	var found: ItemData = registry.get_item(&"tmp_scan_probe")
	assert_not_null(found, "새로 추가한 .tres 는 코드 수정 없이 등록되어야 한다")
	if found != null:
		assert_eq(found.display_name, "스캔 탐침", "표시 이름은 리소스에서 와야 한다")


func test_scan_ignores_non_resource_files() -> void:
	_make_temp_dir()
	var note: FileAccess = FileAccess.open(TEMP_DIR.path_join("README.txt"), FileAccess.WRITE)
	assert_not_null(note, "임시 파일을 만들 수 있어야 한다")
	if note != null:
		note.store_string("not a resource")
		note.close()

	var paths: PackedStringArray = GameDataScript.scan_resource_paths(TEMP_DIR)

	assert_eq(paths.size(), 0, "리소스가 아닌 파일은 스캔 결과에 들어가면 안 된다")


## export 빌드는 .tres 를 .res 로 변환하고 .remap 을 남긴다.
## 스캔은 원본 경로로 정규화해 ResourceLoader 가 remap 을 해석하게 둔다.
func test_scan_normalizes_remap_and_import_suffixes() -> void:
	_make_temp_dir()
	for file_name: String in ["a.tres.remap", "b.res.remap", "c.tres"]:
		var f: FileAccess = FileAccess.open(TEMP_DIR.path_join(file_name), FileAccess.WRITE)
		if f != null:
			f.store_string("stub")
			f.close()

	var paths: Array = Array(GameDataScript.scan_resource_paths(TEMP_DIR))

	assert_eq(paths.size(), 3, "remap 확장자를 벗겨 원본 경로 3개가 나와야 한다")
	assert_has(paths, TEMP_DIR.path_join("a.tres"), ".remap 을 벗긴 원본 경로여야 한다")
	assert_has(paths, TEMP_DIR.path_join("b.res"), ".res.remap 도 원본 경로여야 한다")
	assert_has(paths, TEMP_DIR.path_join("c.tres"), "일반 .tres 는 그대로 들어간다")


## 정렬은 로드 순서를 결정적으로 만든다. 중복 id 진단이 실행마다 달라지면 안 된다.
func test_scan_returns_sorted_paths() -> void:
	_make_temp_dir()
	for file_name: String in ["z.tres", "a.tres", "m.tres"]:
		var f: FileAccess = FileAccess.open(TEMP_DIR.path_join(file_name), FileAccess.WRITE)
		if f != null:
			f.store_string("stub")
			f.close()

	var paths: PackedStringArray = GameDataScript.scan_resource_paths(TEMP_DIR)
	var sorted_paths: PackedStringArray = paths.duplicate()
	sorted_paths.sort()

	assert_eq(paths, sorted_paths, "스캔 결과는 경로 정렬 순서여야 한다")


func test_missing_directory_scans_to_empty_without_crashing() -> void:
	var paths: PackedStringArray = GameDataScript.scan_resource_paths("res://data/does_not_exist")

	assert_eq(paths.size(), 0, "없는 디렉터리는 빈 결과를 준다")
