extends GutTest
func test_tick_gate_and_cancel() -> void:
	var d := ActionDefinition.new(); d.id = &"x"; d.duration = 1.0
	var a := TimedAction.new(d); assert_true(a.start()); assert_false(a.commit())
	a.cancel(); assert_false(a.commit()); assert_eq(a.elapsed_ticks, 0)
