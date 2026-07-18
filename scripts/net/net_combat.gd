class_name NetCombat
extends Node

## 근접전 권위 경계. 클라이언트는 방향 의도만 보내고 호스트가 소유권, 장비,
## 쿨다운, 스태미나, 거리와 전방 호를 다시 판정한다.

const ATTACK_NOISE: NoiseProfile = preload("res://data/senses/noise_melee_attack.tres")
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

func _ready() -> void:
	add_to_group(&"net_combat")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_event_bus = get_node_or_null("/root/EventBus")
	_guard = RpcGuard.new()
	_guard.register_rule(&"submit_attack_intent", false, REQUEST_MAX_PER_SECOND, 96)
	_guard.register_rule(&"apply_attack_feedback", true, RESULT_MAX_PER_SECOND, 96)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_guard.watch_session(_session)

func _physics_process(delta: float) -> void:
	_now_seconds += delta

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

func _reject(reason: String) -> bool:
	_rejection_count += 1
	push_warning("NetCombat: 요청 거부 — %s" % reason)
	return false
