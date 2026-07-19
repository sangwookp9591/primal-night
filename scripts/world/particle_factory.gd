class_name ParticleFactory
extends RefCounted

## gl_compatibility에서도 동일하게 동작하는 저비용 CPU 입자 프리셋.
## 모든 수치는 시각 전용이며 게임플레이 충돌/판정에는 참여하지 않는다.


static func make_soft_texture(inner: Color, outer: Color = Color.TRANSPARENT) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, inner)
	gradient.set_color(1, outer)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 16
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


static func add_particles(parent: Node, particle_name: StringName, amount: int,
		lifetime: float, texture: Texture2D) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = particle_name
	particles.amount = maxi(amount, 1)
	particles.lifetime = maxf(lifetime, 0.05)
	particles.texture = texture
	particles.emitting = false
	parent.add_child(particles)
	return particles


static func set_burst(particles: CPUParticles2D, direction: Vector2, spread: float,
		speed: Vector2, gravity: Vector2, scale_range: Vector2) -> void:
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.direction = direction
	particles.spread = spread
	particles.initial_velocity_min = speed.x
	particles.initial_velocity_max = speed.y
	particles.gravity = gravity
	particles.scale_amount_min = scale_range.x
	particles.scale_amount_max = scale_range.y

