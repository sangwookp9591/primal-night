extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")

class CountingPromptTarget:
	extends Area2D

	var prompt_reads: int = 0
	var interact_count: int = 0

	func _init() -> void:
		collision_layer = 4
		collision_mask = 0
		monitoring = false
		var shape: CollisionShape2D = CollisionShape2D.new()
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 16.0
		shape.shape = circle
		add_child(shape)

	func can_interact(_who: Node) -> bool:
		return true

	func get_hold_seconds() -> float:
		return 1.0

	func get_prompt() -> String:
		prompt_reads += 1
		return "cached prompt"

	func interact(_who: Node) -> void:
		interact_count += 1

func test_hold_prompt_is_read_once_at_begin_and_reused_during_process() -> void:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	var target: CountingPromptTarget = CountingPromptTarget.new()
	world.add_child(player)
	world.add_child(target)
	target.position = Vector2(24.0, 0.0)
	await wait_physics_frames(2)
	var labels: Array[String] = []
	player.interactor.hold_changed.connect(func(_ratio: float, label: String) -> void:
		labels.append(label)
	)

	player.interactor.begin()
	player.interactor._process(0.25)
	player.interactor._process(0.25)
	player.interactor._process(0.25)

	assert_eq(target.prompt_reads, 1, "홀드 중 프롬프트는 begin 시점 캐시에서 나와야 한다")
	assert_eq(labels, ["cached prompt", "cached prompt", "cached prompt", "cached prompt"])
