class_name NetCombat
extends Node

## 근접전 권위 경계. 클라이언트는 방향 의도만 보내고 호스트가 소유권, 장비,
## 쿨다운, 스태미나, 거리와 전방 호를 다시 판정한다.

const ATTACK_NOISE: NoiseProfile = preload("res://data/senses/noise_melee_attack.tres")
const BOW_SHOT_NOISE: NoiseProfile = preload("res://data/senses/noise_bow_shot.tres")
const ARROW_IMPACT_NOISE: NoiseProfile = preload("res://data/senses/noise_arrow_impact.tres")
const ArrowProjectileScript = preload("res://scripts/combat/arrow_projectile.gd")
const WorldItemScene: PackedScene = preload("res://scenes/items/world_item.tscn")
const REQUEST_MAX_PER_SECOND := 8
const RESULT_MAX_PER_SECOND := 32
const PLAYER_ID_MAX_LENGTH := 32
const SPEAR_RANGE := 112.0
const SPEAR_HALF_ARC_DEGREES := 24.0
const KNIFE_RANGE := 62.0
const KNIFE_HALF_ARC_DEGREES := 52.0
const ATTACK_COOLDOWN := 0.65
const ATTACK_STAMINA := 18.0
const SPEAR_DAMAGE := 30.0
const KNIFE_DAMAGE := 18.0
const BOW_DAMAGE := 20.0
const BOW_RANGE := 520.0
const BOW_SPEED := 720.0
const BOW_HIT_RADIUS := 24.0
const BOW_RELOAD_SECONDS := 1.0
const BOW_AIM_MOVE_MULTIPLIER := 0.45
const ARROW_RECOVERY_RATE := 1.0

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _guard: RpcGuard
var _now_seconds := 0.0
var _next_attack_at: Dictionary = {}
var _noise_emitter := NoiseEmitter.new()
var _event_bus: Node
var _rejection_count := 0
var _aiming: Dictionary = {}
var _projectiles: Dictionary = {}
var _next_projectile_id := 1

func _ready() -> void:
	add_to_group(&"net_combat")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_event_bus = get_node_or_null("/root/EventBus")
	_guard = RpcGuard.new()
	_guard.register_rule(&"submit_attack_intent", false, REQUEST_MAX_PER_SECOND, 96)
	_guard.register_rule(&"apply_attack_feedback", true, RESULT_MAX_PER_SECOND, 96)
	_guard.register_rule(&"submit_bow_aim_intent", false, REQUEST_MAX_PER_SECOND, 96)
	_guard.register_rule(&"submit_bow_fire_intent", false, REQUEST_MAX_PER_SECOND, 96)
	_guard.register_rule(&"apply_bow_aim_feedback", true, RESULT_MAX_PER_SECOND, 96)
	_guard.register_rule(&"spawn_arrow_result", true, RESULT_MAX_PER_SECOND, 128)
	_guard.register_rule(&"finish_arrow_result", true, RESULT_MAX_PER_SECOND, 128)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_guard.watch_session(_session)

func _physics_process(delta: float) -> void:
	_now_seconds += delta
	if multiplayer.is_server():
		_tick_projectiles(delta)
	else:
		for state: Dictionary in _projectiles.values():
			(state.node as ArrowProjectile).advance(BOW_SPEED * delta)

func request_bow_aim(avatar: Player, active: bool, direction: Vector2) -> bool:
	if avatar == null or avatar.controller_peer_id != multiplayer.get_unique_id():
		return _reject("로컬 소유가 아닌 아바타")
	var player_id := _player_id_of(avatar)
	if multiplayer.is_server():
		return _confirm_bow_aim(player_id, active, direction)
	submit_bow_aim_intent.rpc_id(RpcGuard.HOST_PEER_ID, String(player_id), active, direction)
	return true

func request_bow_fire(avatar: Player, direction: Vector2) -> bool:
	if avatar == null or avatar.controller_peer_id != multiplayer.get_unique_id():
		return _reject("로컬 소유가 아닌 아바타")
	var player_id := _player_id_of(avatar)
	if multiplayer.is_server():
		return _confirm_bow_fire(player_id, direction)
	submit_bow_fire_intent.rpc_id(RpcGuard.HOST_PEER_ID, String(player_id), direction)
	return true

@rpc("any_peer", "call_remote", "reliable")
func submit_bow_aim_intent(claimed_player_id: String, active: bool, direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _guard.check(&"submit_bow_aim_intent", sender,
			claimed_player_id.length() + 17, _now_seconds):
		_rejection_count += 1
		return
	var actual := _session.get_player_id_for_peer(sender)
	if claimed_player_id.length() > PLAYER_ID_MAX_LENGTH or String(actual) != claimed_player_id:
		_reject("타인 아바타 조준 변조")
		return
	_confirm_bow_aim(actual, active, direction)

@rpc("any_peer", "call_remote", "reliable")
func submit_bow_fire_intent(claimed_player_id: String, direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _guard.check(&"submit_bow_fire_intent", sender,
			claimed_player_id.length() + 16, _now_seconds):
		_rejection_count += 1
		return
	var actual := _session.get_player_id_for_peer(sender)
	if claimed_player_id.length() > PLAYER_ID_MAX_LENGTH or String(actual) != claimed_player_id:
		_reject("타인 아바타 발사 변조")
		return
	_confirm_bow_fire(actual, direction)

func _confirm_bow_aim(player_id: StringName, active: bool, direction: Vector2) -> bool:
	var avatar := _avatar_of(player_id)
	if avatar == null or not direction.is_finite() or direction.is_zero_approx():
		return _reject("잘못된 조준 의도")
	if active and avatar.equipment.get_equipped(&"main_hand") != &"bow":
		return _reject("활 필요")
	_aiming[player_id] = active
	var facing := snap_direction_8(direction)
	avatar.set_bow_aim_feedback(active, facing)
	if not multiplayer.get_peers().is_empty():
		apply_bow_aim_feedback.rpc(String(player_id), active, facing)
	return true

func _confirm_bow_fire(player_id: StringName, direction: Vector2) -> bool:
	var avatar := _avatar_of(player_id)
	if avatar == null or avatar.equipment.get_equipped(&"main_hand") != &"bow":
		return _reject("활 필요")
	if not bool(_aiming.get(player_id, false)):
		return _reject("조준 없이 발사")
	if not direction.is_finite() or direction.is_zero_approx():
		return _reject("잘못된 발사 방향")
	if _now_seconds < float(_next_attack_at.get(player_id, 0.0)):
		return _reject("활 재장전 중")
	if not avatar.inventory.remove_item(&"arrow", 1):
		_confirm_bow_aim(player_id, false, direction)
		return _reject("화살 없음")
	_next_attack_at[player_id] = _now_seconds + BOW_RELOAD_SECONDS
	_confirm_bow_aim(player_id, false, direction)
	var facing := snap_direction_8(direction)
	_noise_emitter.emit_profile(_event_bus, BOW_SHOT_NOISE, avatar.global_position, avatar,
		_now_seconds)
	var projectile_id := _next_projectile_id
	_next_projectile_id += 1
	_spawn_projectile(projectile_id, player_id, avatar.global_position, facing)
	if not multiplayer.get_peers().is_empty():
		spawn_arrow_result.rpc(projectile_id, String(player_id), avatar.global_position, facing)
	return true

func _spawn_projectile(projectile_id: int, player_id: StringName, origin: Vector2,
		direction: Vector2) -> void:
	var projectile := ArrowProjectileScript.new() as ArrowProjectile
	projectile.name = "ArrowProjectile%d" % projectile_id
	projectile.direction = direction.normalized()
	get_parent().add_child(projectile)
	projectile.global_position = origin
	_projectiles[projectile_id] = {
		node = projectile,
		player_id = player_id,
		traveled = 0.0,
	}

func _tick_projectiles(delta: float) -> void:
	var distance := BOW_SPEED * delta
	for projectile_id: int in _projectiles.keys():
		var state: Dictionary = _projectiles[projectile_id]
		var projectile: ArrowProjectile = state.node
		var start := projectile.global_position
		projectile.advance(distance)
		state.traveled = float(state.traveled) + distance
		var hit := _find_arrow_hit(start, projectile.global_position)
		if hit != null:
			var shooter := _avatar_of(state.player_id)
			hit.take_damage(BOW_DAMAGE, projectile.direction, shooter)
			_finish_projectile(projectile_id, hit.global_position)
		elif float(state.traveled) >= BOW_RANGE:
			_finish_projectile(projectile_id,
				start + projectile.direction * (distance - (float(state.traveled) - BOW_RANGE)))

func _find_arrow_hit(from: Vector2, to: Vector2) -> Raptor:
	var best: Raptor
	var best_ratio := INF
	var segment := to - from
	var length_squared := segment.length_squared()
	for node: Node in get_tree().get_nodes_in_group(&"raptor"):
		var raptor := node as Raptor
		if raptor == null or raptor.multiplayer != multiplayer or raptor.is_dead():
			continue
		var ratio := clampf((raptor.global_position - from).dot(segment) / length_squared, 0.0, 1.0)
		if raptor.global_position.distance_to(from + segment * ratio) <= BOW_HIT_RADIUS \
				and ratio < best_ratio:
			best = raptor
			best_ratio = ratio
	return best

func _finish_projectile(projectile_id: int, endpoint: Vector2) -> void:
	var state: Dictionary = _projectiles.get(projectile_id, {})
	if state.is_empty():
		return
	var projectile: ArrowProjectile = state.node
	projectile.queue_free()
	_projectiles.erase(projectile_id)
	_noise_emitter.emit_profile(_event_bus, ARROW_IMPACT_NOISE, endpoint, projectile, _now_seconds)
	if ARROW_RECOVERY_RATE >= 1.0:
		_spawn_recovered_arrow(projectile_id, endpoint)
	if not multiplayer.get_peers().is_empty():
		finish_arrow_result.rpc(projectile_id, endpoint, ARROW_RECOVERY_RATE >= 1.0)

func _spawn_recovered_arrow(projectile_id: int, endpoint: Vector2) -> WorldItem:
	var item := WorldItemScene.instantiate() as WorldItem
	item.name = "RecoveredArrow%d" % projectile_id
	item.item_id = &"arrow"
	item.count = 1
	get_parent().add_child(item)
	item.global_position = endpoint
	return item

@rpc("authority", "call_remote", "reliable")
func apply_bow_aim_feedback(player_id: String, active: bool, direction: Vector2) -> void:
	if not _guard.check(&"apply_bow_aim_feedback", multiplayer.get_remote_sender_id(),
			player_id.length() + 17, _now_seconds):
		return
	var avatar := _avatar_of(StringName(player_id))
	if avatar != null:
		avatar.set_bow_aim_feedback(active, direction)

@rpc("authority", "call_remote", "reliable")
func spawn_arrow_result(projectile_id: int, player_id: String, origin: Vector2,
		direction: Vector2) -> void:
	if not _guard.check(&"spawn_arrow_result", multiplayer.get_remote_sender_id(),
			player_id.length() + 40, _now_seconds) or projectile_id <= 0:
		return
	var avatar := _avatar_of(StringName(player_id))
	if avatar != null:
		avatar.inventory.remove_item(&"arrow", 1)
	_spawn_projectile(projectile_id, StringName(player_id), origin, direction)

@rpc("authority", "call_remote", "reliable")
func finish_arrow_result(projectile_id: int, endpoint: Vector2, recoverable: bool) -> void:
	if not _guard.check(&"finish_arrow_result", multiplayer.get_remote_sender_id(),
			32, _now_seconds) or projectile_id <= 0 or not endpoint.is_finite():
		return
	var state: Dictionary = _projectiles.get(projectile_id, {})
	if not state.is_empty():
		(state.node as ArrowProjectile).queue_free()
		_projectiles.erase(projectile_id)
	if recoverable:
		_spawn_recovered_arrow(projectile_id, endpoint)

func request_attack(avatar: Player, direction: Vector2) -> bool:
	if avatar == null or avatar.controller_peer_id != multiplayer.get_unique_id():
		return _reject("로컬 소유가 아닌 아바타")
	var player_id := StringName(avatar.name)
	if avatar == _host_player:
		player_id = _session.get_local_player_id()
	if multiplayer.is_server():
		return _confirm_attack(player_id, direction)
	submit_attack_intent.rpc_id(RpcGuard.HOST_PEER_ID, String(player_id), direction)
	return true

@rpc("any_peer", "call_remote", "reliable")
func submit_attack_intent(claimed_player_id: String, direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _guard.check(&"submit_attack_intent", sender,
			claimed_player_id.length() + 16, _now_seconds):
		_rejection_count += 1
		return
	var actual := _session.get_player_id_for_peer(sender)
	if claimed_player_id.is_empty() or claimed_player_id.length() > PLAYER_ID_MAX_LENGTH \
			or String(actual) != claimed_player_id:
		_reject("타인 아바타 공격 변조")
		return
	_confirm_attack(actual, direction)

func _confirm_attack(player_id: StringName, direction: Vector2) -> bool:
	var avatar := _avatar_of(player_id)
	if avatar == null or not direction.is_finite() or direction.is_zero_approx():
		return _reject("잘못된 공격 의도")
	var weapon := avatar.equipment.get_equipped(&"main_hand")
	if weapon != &"stone_spear" and weapon != &"stone_knife":
		return _reject("무기 필요")
	if _now_seconds < float(_next_attack_at.get(player_id, 0.0)):
		return _reject("공격 쿨다운")
	if not avatar.stamina.try_spend(ATTACK_STAMINA):
		return _reject("스태미나 부족")
	_next_attack_at[player_id] = _now_seconds + ATTACK_COOLDOWN
	var facing := snap_direction_8(direction)
	avatar.play_attack_feedback(facing)
	if not multiplayer.get_peers().is_empty():
		apply_attack_feedback.rpc(String(player_id), facing)
	_noise_emitter.emit_profile(_event_bus, ATTACK_NOISE, avatar.global_position, avatar,
		_now_seconds)
	var attack_range := SPEAR_RANGE if weapon == &"stone_spear" else KNIFE_RANGE
	var half_arc := SPEAR_HALF_ARC_DEGREES if weapon == &"stone_spear" else KNIFE_HALF_ARC_DEGREES
	var damage := SPEAR_DAMAGE if weapon == &"stone_spear" else KNIFE_DAMAGE
	var best: Raptor
	var best_distance := INF
	for node: Node in get_tree().get_nodes_in_group(&"raptor"):
		var raptor := node as Raptor
		if raptor == null or raptor.multiplayer != multiplayer or raptor.is_dead():
			continue
		var offset := raptor.global_position - avatar.global_position
		if is_in_melee_arc(offset, facing, attack_range, half_arc):
			var distance := offset.length_squared()
			if distance < best_distance:
				best_distance = distance
				best = raptor
	if best != null:
		best.take_damage(damage, facing, avatar)
	return true

@rpc("authority", "call_remote", "reliable")
func apply_attack_feedback(player_id: String, direction: Vector2) -> void:
	if not _guard.check(&"apply_attack_feedback", multiplayer.get_remote_sender_id(),
			player_id.length() + 16, _now_seconds):
		return
	var avatar := _avatar_of(StringName(player_id))
	if avatar != null:
		avatar.play_attack_feedback(direction)

static func snap_direction_8(direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		return Vector2.DOWN
	var angle := snappedf(direction.angle(), PI / 4.0)
	return Vector2.from_angle(angle)

static func is_in_melee_arc(offset: Vector2, facing: Vector2, attack_range: float,
		half_arc_degrees: float) -> bool:
	if offset.is_zero_approx() or offset.length() > attack_range or facing.is_zero_approx():
		return false
	return absf(rad_to_deg(facing.normalized().angle_to(offset.normalized()))) <= half_arc_degrees

func get_rejection_count() -> int:
	return _rejection_count

func _avatar_of(player_id: StringName) -> Player:
	if player_id == _session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID):
		return _host_player
	return _container.get_node_or_null(NodePath(String(player_id))) as Player

func _player_id_of(avatar: Player) -> StringName:
	if avatar == _host_player:
		return _session.get_local_player_id()
	return StringName(avatar.name)

func _reject(reason: String) -> bool:
	_rejection_count += 1
	push_warning("NetCombat: 요청 거부 — %s" % reason)
	return false
