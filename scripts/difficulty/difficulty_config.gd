class_name DifficultyConfig
extends Resource

@export var id: StringName = &"standard"
@export var display_name: String = "표준"
@export_multiline var description: String = ""

@export_group("자원 여유")
@export_range(0.25, 3.0, 0.05) var resource_spawn_quantity_multiplier: float = 1.0
@export_range(0.25, 3.0, 0.05) var resource_respawn_time_multiplier: float = 1.0

@export_group("흔적 가독성")
@export_range(0.25, 3.0, 0.05) var trace_feedback_duration_multiplier: float = 1.0
@export_range(0.25, 3.0, 0.05) var trace_feedback_intensity_multiplier: float = 1.0

@export_group("사망 복구")
@export_range(0.0, 1.0, 0.05) var death_item_keep_ratio: float = 0.5

@export_group("포식자 관용도")
@export_range(0.25, 3.0, 0.05) var raptor_investigate_threshold_multiplier: float = 1.0
@export_range(0.0, 5.0, 0.05) var raptor_chase_give_up_seconds: float = 1.0
