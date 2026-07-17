class_name RecipeData
extends Resource

@export var id: StringName
@export var ingredients: Dictionary = {}
@export var result: ItemData
@export var result_count: int = 1
@export var action: ActionDefinition
@export_multiline var observation_hint: String = ""
@export_multiline var observation_success: String = ""
