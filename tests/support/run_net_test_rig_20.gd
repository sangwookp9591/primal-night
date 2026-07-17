extends SceneTree

const NetTestRigScript = preload("res://tests/support/net_test_rig.gd")
const REPEAT_COUNT: int = 20


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var collisions: int = 0
	for iteration: int in range(REPEAT_COUNT):
		var first: Dictionary = _make_host("First%d" % iteration)
		var second: Dictionary = _make_host("Second%d" % iteration)
		var first_error: Error = first.rig.start_host(first.service)
		var second_error: Error = second.rig.start_host(second.service)
		if first_error != OK or second_error != OK \
				or first.service.bound_port == second.service.bound_port:
			collisions += 1
		first.rig.disconnect_all()
		second.rig.disconnect_all()
		set_multiplayer(null, first.root.get_path())
		set_multiplayer(null, second.root.get_path())
		first.root.queue_free()
		second.root.queue_free()
		await process_frame
	print("NetTestRig parallel repeat: runs=%d collisions=%d" % [REPEAT_COUNT, collisions])
	quit(0 if collisions == 0 else 1)


func _make_host(root_name: String) -> Dictionary:
	var root: Node = Node.new()
	root.name = root_name
	get_root().add_child(root)
	set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var service: LocalSessionService = LocalSessionService.new()
	service.name = "NetSession"
	root.add_child(service)
	return {
		root = root,
		service = service,
		rig = NetTestRigScript.new(self),
	}
