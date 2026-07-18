class_name RecipeData
extends Resource

@export var id: StringName
@export var ingredients: Dictionary = {}
@export var result: ItemData
@export var result_count: int = 1
## 결과 아이템 대신 현재 착용한 옷의 Damaged 상태를 지우는 수선 제작법.
@export var repairs_outfit: bool = false
@export var action: ActionDefinition
@export_multiline var observation_hint: String = ""
@export_multiline var observation_success: String = ""
