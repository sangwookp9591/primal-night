extends GutTest

const WorldScene: PackedScene = preload("res://scenes/world/test_world.tscn")

func test_world_uses_isometric_tilemap_layers_and_navigation_region() -> void:
	var world: Node2D = autofree(WorldScene.instantiate())
	var ground: TileMapLayer = world.get_node("Ground")
	var collision: TileMapLayer = world.get_node("Collision")
	var occlusion: TileMapLayer = world.get_node("Occlusion")
	var navigation: NavigationRegion2D = world.get_node("NavigationRegion2D")

	assert_not_null(ground)
	assert_not_null(collision)
	assert_not_null(occlusion)
	assert_not_null(navigation)
	assert_eq(ground.tile_set.tile_shape, TileSet.TILE_SHAPE_ISOMETRIC)
	assert_eq(ground.tile_set.tile_size, Vector2i(64, 32))
	assert_true(ground.y_sort_enabled)
	assert_true(collision.y_sort_enabled)
	assert_true(occlusion.y_sort_enabled)
