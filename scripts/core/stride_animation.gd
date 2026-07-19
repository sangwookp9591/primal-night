class_name StrideAnimation
extends RefCounted

## 발 미끄러짐 방지 공통 법칙: 보행 FPS = 속도 × 보행 프레임 수 ÷ 한 주기 보폭 거리.
## 스프라이트별로 달라지는 것은 프레임 수·보폭뿐이므로 공식은 여기 한 곳만 소유한다.


static func walk_fps(speed: float, frame_count: int, stride_distance: float) -> float:
	return maxf(speed, 0.0) * float(frame_count) / stride_distance
