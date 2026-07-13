extends GutTest

const PlayerScene: PackedScene = preload("res://scenes/player/player.tscn")
const PlayerConfigScript = preload("res://scripts/player/player_config.gd")

func before_each() -> void:
	Input.action_release("move_right")
	Input.action_release("run")

func after_each() -> void:
	Input.action_release("move_right")
	Input.action_release("run")

func test_noise_radius_changes_for_idle_walk_and_run() -> void:
	var player: Player = add_child_autofree(PlayerScene.instantiate())
	var config: Resource = PlayerConfigScript.new()
	config.walk_speed = 120.0
	config.run_speed = 240.0
	config.base_walk_noise = 10.0
	config.base_run_noise = 25.0
	player.config = config

	assert_eq(player.get_noise_radius(), 0.0)

	Input.action_press("move_right")
	await wait_physics_frames(1)
	assert_eq(player.get_noise_radius(), 10.0)

	Input.action_press("run")
	await wait_physics_frames(1)
	assert_eq(player.get_noise_radius(), 25.0)

func test_player_cannot_move_through_wall() -> void:
	var world: Node2D = add_child_autofree(Node2D.new())
	var player: Player = PlayerScene.instantiate()
	var wall: StaticBody2D = StaticBody2D.new()
	var wall_shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(16.0, 160.0)
	wall_shape.shape = rectangle
	wall.position = Vector2(48.0, 0.0)
	wall.add_child(wall_shape)
	world.add_child(wall)
	world.add_child(player)

	Input.action_press("move_right")
	await wait_physics_frames(40)

	assert_lt(player.position.x, 35.0)
