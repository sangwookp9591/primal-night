class_name ActionDefinition
extends Resource

@export var id: StringName
@export var duration: float = 0.0
@export var animation: StringName
@export var stamina_cost: float = 0.0
@export var noise: float = 0.0

func is_valid() -> bool:
	return id != &"" and is_finite(duration) and duration >= 0.0 and is_finite(stamina_cost) and stamina_cost >= 0.0
