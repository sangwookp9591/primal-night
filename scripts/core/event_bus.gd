extends Node

signal noise_emitted(position: Vector2, radius: float, source: Node)
signal smell_emitted(position: Vector2, strength: float, kind: StringName)
signal damage_taken(target: Node, amount: float, kind: StringName)
signal bleeding_started(target: Node)
signal bleeding_stopped(target: Node)
signal item_picked_up(item_id: StringName, by: Node)
signal campfire_lit(campfire: Node, position: Vector2, radius: float)
signal campfire_extinguished(campfire: Node)
