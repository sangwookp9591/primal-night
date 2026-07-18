class_name NetConfig
extends Resource

## 네트워크 규칙 수치 (설계서 7.x / 성능 문서 4.6).
## 수치는 노드에 흩뿌리지 않고 이 리소스로 관리한다.

## 로컬 개발 세션이 여는 포트.
@export var port: int = 8910

## 호스트 외 클라이언트 수. 최대 4인 = 호스트 + 3.
@export var max_clients: int = 3

## --- 이동 동기화 (설계서 7.2: 이동·방향 비신뢰 최신값) ---

## 텔레포트 검사 여유 배수 (설계서 7.4: 좌표를 그대로 신뢰하지 않음).
@export var move_tolerance: float = 1.25

## 이동 예산 최소 바닥 (px) — 틱 지터로 정직한 첫 이동이 거부되는 것을 막는다.
@export var min_move_allowance_px: float = 12.0

## 의도 간 경과시간 상한 (초) — 오래 쉬었다 움직여도 이동 예산이 누적되지 않게 자른다.
@export var intent_elapsed_cap_seconds: float = 0.25

## 클라이언트 이동 의도 초당 상한 (성능 문서 14: 연결별 초당 명령 수 제한).
@export var intent_max_per_second: int = 90

## 위치 스냅샷 주기 (물리 틱). 6틱 = 10Hz (성능 문서 4.6: 월드 스냅샷 10Hz 이하).
@export var snapshot_interval_ticks: int = 6

## 자기 아바타가 서버 확정 위치에서 이만큼 벗어나면 서버 위치로 스냅(보정)한다.
@export var correction_snap_px: float = 48.0

## 클라이언트 아바타 스폰 위치 (호스트 아바타 기준 오프셋).
@export var client_spawn_offset: Vector2 = Vector2(64.0, 0.0)

## RPC 페이로드 상한 (성능 문서 4.6: 일반 RPC 4KB 이하).
@export var intent_max_payload_bytes: int = 64
@export var spawn_max_payload_bytes: int = 256
@export var snapshot_max_payload_bytes: int = 4096
