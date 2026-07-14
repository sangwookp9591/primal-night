class_name NetConfig
extends Resource

## 네트워크 규칙 수치 (설계서 7.x / 성능 문서 4.6).
## 수치는 노드에 흩뿌리지 않고 이 리소스로 관리한다.

## ENet 개발 세션이 여는 포트.
@export var port: int = 8910

## 호스트 외 클라이언트 수. 출시 2인 = 호스트 + 1 (설계서 7.1).
@export var max_clients: int = 1
