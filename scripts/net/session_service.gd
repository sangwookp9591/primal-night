@abstract
class_name SessionService
extends Node

## 세션 어댑터 경계 (설계서 9.1: 네트워크 백엔드를 어댑터 뒤에 캡슐화).
## 게임 코드는 이 인터페이스와 Godot 표준 MultiplayerAPI 에만 의존한다.
## 백엔드(ENet 개발용 / Steam 출시용)는 이 뒤에 숨는다 — 교체 시 게임 코드 불변.
##
## PlayerId 는 StringName 이다. int peer id 가 아니다:
## Steam 은 64비트 SteamID 라 int peer id 로 담을 수 없고,
## 재접속 슬롯(설계서 7.3: 동일 계정 120초)도 이 PlayerId 로 식별한다.
## ENet 구현은 peer id 문자열, Steam 구현은 SteamID64 문자열을 쓴다.

signal player_joined(player_id: StringName)
signal player_left(player_id: StringName)
## 세션이 끝났다 (자발적 이탈 또는 호스트 이탈, 설계서 7.3).
signal session_ended


@abstract func host_session() -> Error

## invite 는 백엔드별 초대장이다. ENet: "ip:port" String / Steam: 로비 ID.
@abstract func join_session(invite: Variant) -> Error

@abstract func leave_session() -> void

@abstract func get_local_player_id() -> StringName

@abstract func get_players() -> Array[StringName]

## MultiplayerAPI 수준(peer id)과 세션 수준(PlayerId) 사이의 변환.
@abstract func get_player_id_for_peer(peer_id: int) -> StringName

@abstract func get_peer_for_player(player_id: StringName) -> int
