class_name ArrowProjectile
extends Node2D

var direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	queue_redraw()

func advance(distance: float) -> void:
	position += direction * distance

func _draw() -> void:
	draw_line(-direction * 10.0, direction * 10.0, Color(0.83, 0.68, 0.35), 3.0)
	draw_circle(direction * 10.0, 2.5, Color(0.72, 0.75, 0.78))
