extends GutTest

const NetTestRigScript = preload("res://tests/support/net_test_rig.gd")

var roots: Array[Node] = []
var rigs: Array[RefCounted] = []


func after_each() -> void:
	for rig: RefCounted in rigs:
		rig.disconnect_all()
	for root: Node in roots:
		get_tree().set_multiplayer(null, root.get_path())
	rigs.clear()
	roots.clear()


func test_two_rigs_bind_distinct_dynamic_ports_in_one_process() -> void:
	var first: Dictionary = _make_host("FirstHost")
	var second: Dictionary = _make_host("SecondHost")
	assert_eq(first.rig.start_host(first.service), OK)
	assert_eq(second.rig.start_host(second.service), OK)
	assert_gt(first.service.bound_port, 0)
	assert_gt(second.service.bound_port, 0)
	assert_ne(first.service.bound_port, second.service.bound_port)


func _make_host(root_name: String) -> Dictionary:
	var root: Node = add_child_autofree(Node.new())
	root.name = root_name
	roots.append(root)
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var service: LocalSessionService = LocalSessionService.new()
	service.name = "NetSession"
	root.add_child(service)
	var rig: RefCounted = NetTestRigScript.new(get_tree())
	rigs.append(rig)
	return {root = root, service = service, rig = rig}
