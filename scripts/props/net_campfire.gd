class_name NetCampfire
extends Node

## 모닥불 설치·점화 호스트 권위 + 복제 (설계서 5.8, 7.2/7.4, W2-T5).
## 클라이언트는 설치 '의도'(지정자리 경로)만 보낸다 — 재료·수량은 페이로드에 없어
## 클라이언트가 조작할 수 없다. 호스트가 자기 월드의 실제 CampfireSite 를 조회해
## 자리 점유·거리·재료를 검증하고 결과를 신뢰 전송으로 복제한다.
## 같은 프레임에 두 명이 같은 자리를 요청해도 호스트가 직렬로 처리하므로
## 정확히 하나만 생기고 재료도 한 번만 소비된다 — tests/props/test_net_campfire.gd.
## NetPickup/NetSurvival 과 같은 골격 (RpcGuard + 의도/확정 RPC).

## 설치 검증 거리 (px): 상호작용 손 반경 48 + 자리 반경 18 + 10Hz 위치 스냅샷
## 지연 여유. 게임 규칙이 아니라 변조 방지 슬랙이라 프로토콜 상수다 (NetPickup 관례).
const BUILD_MAX_DISTANCE_PX: float = 128.0
const SITE_PATH_MAX_LENGTH: int = 128
const PLAYER_ID_MAX_LENGTH: int = 32
const REQUEST_MAX_PER_SECOND: int = 10
const CONFIRM_MAX_PER_SECOND: int = 10
const CONFIRM_PAYLOAD_BYTES: int = 256
const COOK_HOLD_SLACK_SECONDS: float = 0.12

@export var session_path: NodePath = ^"../NetSession"
@export var host_player_path: NodePath = ^"../Player"
@export var players_container_path: NodePath = ^"../Players"
## 지정자리 경로 해석 기준. 양쪽 기계가 같은 씬을 로드하므로 상대 경로가 일치한다.
@export var world_root_path: NodePath = ^".."

var _session: SessionService
var _host_player: Player
var _container: Node2D
var _world_root: Node
var _guard: RpcGuard
var _event_bus: Node = null
var _now_seconds: float = 0.0
## 호스트가 확정한 모닥불 → 지정자리 경로. 연료 소진 소등을 복제할 때 쓴다.
var _site_paths_by_campfire: Dictionary = {}
var _cook_holds: Dictionary = {}


func _ready() -> void:
	add_to_group(&"net_campfire")
	_session = get_node(session_path)
	_host_player = get_node(host_player_path)
	_container = get_node(players_container_path)
	_world_root = get_node(world_root_path)
	if has_node("/root/EventBus"):
		_event_bus = get_node("/root/EventBus")
		_event_bus.campfire_extinguished.connect(_on_campfire_extinguished)
	_guard = RpcGuard.new()
	_guard.register_rule(&"request_campfire_build", false, REQUEST_MAX_PER_SECOND, SITE_PATH_MAX_LENGTH + 16)
	_guard.register_rule(&"confirm_campfire_build", true, CONFIRM_MAX_PER_SECOND, CONFIRM_PAYLOAD_BYTES)
	_guard.register_rule(&"confirm_campfire_extinguished", true, CONFIRM_MAX_PER_SECOND, CONFIRM_PAYLOAD_BYTES)
	_guard.register_rule(&"request_cook_hold_start", false, REQUEST_MAX_PER_SECOND, SITE_PATH_MAX_LENGTH)
	_guard.register_rule(&"request_cook_hold_end", false, REQUEST_MAX_PER_SECOND, SITE_PATH_MAX_LENGTH)
	_guard.register_rule(&"request_campfire_cook", false, REQUEST_MAX_PER_SECOND, SITE_PATH_MAX_LENGTH)
	_guard.register_rule(&"confirm_campfire_cook", true, CONFIRM_MAX_PER_SECOND, CONFIRM_PAYLOAD_BYTES)
	_guard.add_peer(RpcGuard.HOST_PEER_ID)
	_guard.watch_session(_session)


func _physics_process(delta: float) -> void:
	# RpcGuard 빈도 창의 시계. 프레임당 덧셈 1회뿐이다 (성능문서 6.1).
	_now_seconds += delta


## 이 기계(멀티플레이 브랜치)가 소유한 노드인가 — CampfireSite 가 자기 기계의
## NetCampfire 를 찾을 때 쓴다 (헤드리스 하네스에선 한 트리에 기계가 2개다).
func owns(node: Node) -> bool:
	return _world_root.is_ancestor_of(node)


## CampfireSite.interact 가 호출한다 (설치 홀드 완료 시점).
## 호스트면 즉시 권위 판정, 클라이언트면 의도 전송.
## 설치자는 페이로드가 아니라 발신자에서 유도한다 (설계서 7.4).
func request(site: CampfireSite, who: Player) -> void:
	if multiplayer.is_server():
		_host_build(who, site)
		return
	request_campfire_build.rpc_id(RpcGuard.HOST_PEER_ID, String(_world_root.get_path_to(site)))


func notify_cook_hold_started(site: CampfireSite, who: Player) -> void:
	if multiplayer.is_server():
		_host_cook_hold_started(who, site)
		return
	request_cook_hold_start.rpc_id(RpcGuard.HOST_PEER_ID, String(_world_root.get_path_to(site)))


func notify_cook_hold_ended(site: CampfireSite, who: Player) -> void:
	if multiplayer.is_server():
		_host_cook_hold_ended(who, site)
		return
	request_cook_hold_end.rpc_id(RpcGuard.HOST_PEER_ID, String(_world_root.get_path_to(site)))


func request_cook(site: CampfireSite, who: Player) -> void:
	if multiplayer.is_server():
		_host_cook(who, site)
		return
	request_campfire_cook.rpc_id(RpcGuard.HOST_PEER_ID, String(_world_root.get_path_to(site)))


@rpc("any_peer", "call_remote", "reliable")
func request_cook_hold_start(site_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_cook_hold_start", sender, site_path.length(), _now_seconds) \
			or not _is_valid_path(site_path):
		return
	_host_cook_hold_started(_avatar_of(_session.get_player_id_for_peer(sender)),
		_world_root.get_node_or_null(site_path) as CampfireSite)


@rpc("any_peer", "call_remote", "reliable")
func request_cook_hold_end(site_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_cook_hold_end", sender, site_path.length(), _now_seconds) \
			or not _is_valid_path(site_path):
		return
	_host_cook_hold_ended(_avatar_of(_session.get_player_id_for_peer(sender)),
		_world_root.get_node_or_null(site_path) as CampfireSite)


@rpc("any_peer", "call_remote", "reliable")
func request_campfire_cook(site_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_campfire_cook", sender, site_path.length(), _now_seconds) \
			or not _is_valid_path(site_path):
		return
	_host_cook(_avatar_of(_session.get_player_id_for_peer(sender)),
		_world_root.get_node_or_null(site_path) as CampfireSite)


func _host_cook_hold_started(who: Player, site: CampfireSite) -> void:
	if not _can_cook(who, site):
		return
	_cook_holds[_cook_key(who, site)] = _now_seconds
	site._start_cooking_smell()


func _host_cook_hold_ended(who: Player, site: CampfireSite) -> void:
	if who != null and site != null:
		_cook_holds.erase(_cook_key(who, site))
		site._end_cooking_smell()


func _host_cook(who: Player, site: CampfireSite) -> void:
	if not _can_cook(who, site):
		return
	var key := _cook_key(who, site)
	if not _cook_holds.has(key):
		return
	var elapsed := _now_seconds - float(_cook_holds[key])
	if elapsed + COOK_HOLD_SLACK_SECONDS < CampfireSite.COOK_SECONDS:
		push_warning("NetCampfire: 굽기 홀드 미달 %.2fs" % elapsed)
		return
	_cook_holds.erase(key)
	site._end_cooking_smell()
	if not site.apply_cook(who):
		return
	if multiplayer.get_peers().size() > 0:
		confirm_campfire_cook.rpc(String(_world_root.get_path_to(site)), String(_player_id_of(who)))


@rpc("authority", "call_remote", "reliable")
func confirm_campfire_cook(site_path: String, player_id: String) -> void:
	if not _guard.check(&"confirm_campfire_cook", multiplayer.get_remote_sender_id(),
			site_path.length() + player_id.length(), _now_seconds):
		return
	if not _is_valid_path(site_path) or player_id.is_empty() \
			or player_id.length() > PLAYER_ID_MAX_LENGTH:
		return
	var site := _world_root.get_node_or_null(site_path) as CampfireSite
	if site != null:
		site.apply_cook(_avatar_of(StringName(player_id)))


func _can_cook(who: Player, site: CampfireSite) -> bool:
	return who != null and is_instance_valid(who) and site != null \
		and site.campfire != null and site.campfire.is_lit \
		and who.global_position.distance_to(site.global_position) <= BUILD_MAX_DISTANCE_PX \
		and who.inventory.has_item(&"raw_meat", 1)


func _cook_key(who: Player, site: CampfireSite) -> String:
	return "%d:%d" % [who.get_instance_id(), site.get_instance_id()]


## 클라이언트 → 호스트: 설치 의도. 경로만 받고 모든 사실은 호스트 월드에서 조회한다.
@rpc("any_peer", "call_remote", "reliable")
func request_campfire_build(site_path: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not _guard.check(&"request_campfire_build", sender, site_path.length(), _now_seconds):
		return
	if not _is_valid_path(site_path):
		push_warning("NetCampfire: request_campfire_build 스키마 위반 — 폐기 sender=%d" % sender)
		return
	var avatar: Player = _avatar_of(_session.get_player_id_for_peer(sender))
	if avatar == null:
		return
	_host_build(avatar, _world_root.get_node_or_null(site_path) as CampfireSite)


## 호스트 권위 판정: 자리 점유·거리·재료를 검증하고 적용한 뒤 결과를 복제한다.
## 같은 프레임 동시 요청은 직렬 처리되어 두 번째가 자리 점유 검사에서 거부된다.
func _host_build(who: Player, site: CampfireSite) -> void:
	if site == null or site.campfire != null:
		return  # 이미 지어진 자리 — 동시 설치 경합에서 진 정상 경로.
	if who == null or not is_instance_valid(who):
		return
	if who.global_position.distance_to(site.global_position) > BUILD_MAX_DISTANCE_PX:
		push_warning("NetCampfire: 사거리 밖 설치 주장 거부 site=%s dist=%.0f" % [
			site.name, who.global_position.distance_to(site.global_position)])
		return
	if not site.consume_materials(who):
		return  # 재료 부족 — 변조이거나 이미 다른 곳에 써 버린 경합 패자.
	var site_path: String = String(_world_root.get_path_to(site))
	site.build_and_light()
	_site_paths_by_campfire[site.campfire] = site_path
	if multiplayer.get_peers().size() > 0:
		confirm_campfire_build.rpc(site_path, String(_player_id_of(who)))


## 호스트 → 클라이언트: 설치 확정 복제. 재료 소비와 모닥불 상태를 맞춘다.
@rpc("authority", "call_remote", "reliable")
func confirm_campfire_build(site_path: String, builder_id: String) -> void:
	if not _guard.check(&"confirm_campfire_build", multiplayer.get_remote_sender_id(),
			site_path.length() + builder_id.length(), _now_seconds):
		return
	if not _is_valid_path(site_path) or builder_id.is_empty() \
			or builder_id.length() > PLAYER_ID_MAX_LENGTH:
		push_warning("NetCampfire: confirm_campfire_build 스키마 위반 — 폐기")
		return
	var site: CampfireSite = _world_root.get_node_or_null(site_path) as CampfireSite
	if site == null or site.campfire != null:
		return
	# 재료 소비 복제 — 호스트가 이미 확정했으므로 복제본 부족이 설치를 막지 않는다.
	var builder: Player = _avatar_of(StringName(builder_id))
	if builder != null:
		site.consume_materials(builder)
	site.build_and_light()


## 호스트 → 클라이언트: 소등 확정 복제 (연료 소진은 호스트 타이머만 판정한다).
@rpc("authority", "call_remote", "reliable")
func confirm_campfire_extinguished(site_path: String) -> void:
	if not _guard.check(&"confirm_campfire_extinguished", multiplayer.get_remote_sender_id(),
			site_path.length(), _now_seconds):
		return
	if not _is_valid_path(site_path):
		push_warning("NetCampfire: confirm_campfire_extinguished 스키마 위반 — 폐기")
		return
	var site: CampfireSite = _world_root.get_node_or_null(site_path) as CampfireSite
	if site == null or site.campfire == null:
		return
	site.campfire.extinguish()


## 호스트 전용: 자기 월드의 모닥불이 꺼지면 (연료 소진 타이머) 소등을 복제한다.
func _on_campfire_extinguished(campfire: Node) -> void:
	if not multiplayer.is_server():
		return
	if not _site_paths_by_campfire.has(campfire):
		return  # 다른 기계의 불 (헤드리스 하네스) 또는 이 권위가 확정하지 않은 불.
	var site_path: String = String(_site_paths_by_campfire[campfire])
	_site_paths_by_campfire.erase(campfire)
	if multiplayer.get_peers().size() > 0:
		confirm_campfire_extinguished.rpc(site_path)


func _is_valid_path(path: String) -> bool:
	return RpcGuard.is_safe_relative_path(path, SITE_PATH_MAX_LENGTH)


func _host_id() -> StringName:
	return _session.get_player_id_for_peer(RpcGuard.HOST_PEER_ID)


## 아바타 이름 = PlayerId 는 NetMovement 의 스폰 관례다 (scripts/net/net_movement.gd).
func _avatar_of(player_id: StringName) -> Player:
	if player_id == _host_id():
		return _host_player
	return _container.get_node_or_null(NodePath(String(player_id))) as Player


func _player_id_of(who: Player) -> StringName:
	if who == _host_player:
		return _host_id()
	return StringName(who.name)
