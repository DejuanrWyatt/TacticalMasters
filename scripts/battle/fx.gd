extends Node3D
## Ability animations, built from simple shapes: projectiles, bursts,
## shockwave rings, light pillars, falling rain and sparkles.
##
## play() starts the animation for one ability and returns the number of
## seconds until it "lands", so the battle can show damage numbers and hit
## reactions in sync with it.

const UnitView = preload("res://scripts/battle/unit_view.gd")

const WHITE := Color(1, 1, 1)
const STEEL := Color(0.9, 0.92, 1.0)
const GOLD := Color(1.0, 0.85, 0.35)
const FIRE := Color(1.0, 0.45, 0.1)
const ICE := Color(0.6, 0.9, 1.0)
const HOLY := Color(1.0, 0.97, 0.75)
const HEAL := Color(0.45, 1.0, 0.55)
const EARTH := Color(0.6, 0.45, 0.3)
const CHI := Color(1.0, 0.7, 0.3)
const HASTE := Color(0.45, 0.75, 1.0)
const STONE := Color(0.55, 0.55, 0.55)


## `caster` is the caster's view; `from` its chest position; `target` the
## ground point aimed at; `radius` the ability's area radius in meters.
func play(ability_id: String, caster: UnitView, from: Vector3, target: Vector3, radius: float) -> float:
	var up := Vector3(0, 0.8, 0)
	match ability_id:
		"attack", "staff", "punch":
			caster.lunge(target)
			burst(target + up, 0.45, STEEL if ability_id != "punch" else CHI, 0.3, 0.15)
			return 0.15
		"shield_bash":
			caster.lunge(target, 0.7)
			burst(target + up, 0.6, HASTE, 0.35, 0.15)
			ring(target + Vector3(0, 0.1, 0), 1.2, HASTE, 0.4, 0.15)
			return 0.15
		"brave_slash":
			caster.lunge(target, 0.9)
			slash(target + up, GOLD, 0.15)
			burst(target + up, 1.0, GOLD, 0.45, 0.2)
			ring(target + Vector3(0, 0.1, 0), 2.0, GOLD, 0.5, 0.2)
			return 0.2
		"throw_stone":
			caster.lunge(target, 0.2)
			var t := projectile(from, target + up, STONE, 0.12, 1.5, 0.5, false)
			burst(target + up, 0.35, STONE, 0.25, t)
			return t
		"bow_shot", "aimed_shot", "pin_shot":
			caster.cast(target)
			var color := GOLD if ability_id == "aimed_shot" else (Color(0.75, 0.5, 1.0) if ability_id == "pin_shot" else WHITE)
			var t := projectile(from, target + up, color, 0.06, 0.8, 0.4, true)
			burst(target + up, 0.3, color, 0.25, t)
			return t
		"arrow_rain":
			caster.cast(target)
			projectile(from, from + Vector3(0, 6, 0), GOLD, 0.06, 0.0, 0.3, true)
			return rain(target, radius, GOLD, 18, 0.45, true)
		"wave_fist":
			caster.lunge(target, 0.4)
			var t := projectile(from, target + up, CHI, 0.25, 0.0, 0.35, false)
			burst(target + up, 0.6, CHI, 0.3, t)
			return t
		"chakra":
			caster.cast(target)
			ring(target + Vector3(0, 0.1, 0), radius, HEAL, 0.7, 0.0)
			sparkles(target, radius, HEAL, 0.1)
			return 0.3
		"earth_slash":
			caster.lunge(target, 0.01)
			ring(target + Vector3(0, 0.1, 0), radius, EARTH, 0.6, 0.1)
			ring(target + Vector3(0, 0.3, 0), radius * 0.7, CHI, 0.5, 0.2)
			burst(target + Vector3(0, 0.3, 0), 1.2, EARTH, 0.4, 0.05)
			return 0.35
		"fire":
			caster.cast(target)
			var t := projectile(from, target + up, FIRE, 0.22, 1.0, 0.55, false)
			burst(target + up, 0.9, FIRE, 0.45, t)
			return t
		"blizzard":
			caster.cast(target)
			var t := rain(target, radius, ICE, 14, 0.5, false)
			burst(target + Vector3(0, 0.4, 0), radius, ICE, 0.5, t)
			return t
		"meteor":
			caster.cast(target)
			var t := projectile(target + Vector3(4, 14, 3), target, FIRE, 0.8, 0.0, 0.9, false)
			burst(target + Vector3(0, 0.3, 0), radius, FIRE, 0.7, t)
			ring(target + Vector3(0, 0.1, 0), radius * 1.3, GOLD, 0.7, t)
			return t
		"holy_blade":
			caster.lunge(target, 0.6)
			pillar(target, HOLY, radius, 0.1)
			burst(target + up, radius, HOLY, 0.5, 0.25)
			return 0.25
		"raise":
			caster.cast(target)
			pillar(target, HOLY, 0.8, 0.05)
			sparkles(target, 0.8, HOLY, 0.15)
			ring(target + Vector3(0, 0.1, 0), 1.4, HOLY, 0.6, 0.2)
			return 0.3
		"cure":
			caster.cast(target)
			sparkles(target, 0.6, HEAL, 0.15)
			burst(target + up, 0.5, HEAL, 0.4, 0.2)
			return 0.3
		"haste":
			caster.cast(target)
			ring(target + Vector3(0, 0.1, 0), 0.9, HASTE, 0.5, 0.1)
			ring(target + Vector3(0, 1.0, 0), 0.7, HASTE, 0.5, 0.25)
			sparkles(target, 0.5, HASTE, 0.1)
			return 0.3
		"sanctuary":
			caster.cast(target)
			burst(target + Vector3(0, 0.2, 0), radius, HOLY, 0.9, 0.1)
			sparkles(target, radius, HEAL, 0.2)
			return 0.4
		"focus":
			caster.cast(target)
			ring(target + Vector3(0, 0.1, 0), 0.9, Color(1, 0.35, 0.25), 0.5, 0.0)
			sparkles(target, 0.5, Color(1, 0.4, 0.3), 0.05)
			return 0.3
		"guard":
			caster.cast(target)
			burst(target + Vector3(0, 0.7, 0), 0.8, HASTE, 0.6, 0.05, 0.35)
			return 0.3
	burst(target + up, 0.5, WHITE, 0.3, 0.1)
	return 0.1


## A glowing, pulsing circle and rising motes around a caster for the whole
## cast time.
func charge(caster: UnitView, seconds: float) -> void:
	caster.cast(caster.global_position + Vector3(0, 0, -1))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.68
	var inst := _spawn(torus, Color(0.75, 0.4, 1.0, 0.8), caster.global_position + Vector3(0, 0.08, 0))
	inst.reparent(caster)  # follow the caster if it walks while casting
	var pulse := inst.create_tween().set_loops()
	pulse.tween_property(inst, "scale", Vector3(1.15, 1, 1.15), 0.35)
	pulse.tween_property(inst, "scale", Vector3.ONE, 0.35)
	var spin := inst.create_tween().set_loops()
	spin.tween_property(inst, "rotation:y", TAU, 1.5).from(0.0)
	var motes := CPUParticles3D.new()
	motes.amount = 16
	motes.lifetime = 0.8
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_radius = 0.6
	motes.emission_ring_inner_radius = 0.5
	motes.emission_ring_height = 0.05
	motes.emission_ring_axis = Vector3.UP
	motes.direction = Vector3.UP
	motes.spread = 5.0
	motes.gravity = Vector3(0, 1.0, 0)
	motes.initial_velocity_min = 0.6
	motes.initial_velocity_max = 1.2
	var dot := SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	motes.mesh = dot
	motes.material_override = _material(Color(0.85, 0.6, 1.0))
	inst.add_child(motes)
	get_tree().create_timer(seconds).timeout.connect(inst.queue_free)


## Draws one of every effect material/mesh combination for a couple of
## frames, nearly invisible, so their shaders are compiled at the start of
## the battle instead of stalling the game the first time an ability is used.
func prewarm(at: Vector3) -> void:
	var meshes: Array[Mesh] = [SphereMesh.new(), BoxMesh.new(), TorusMesh.new(), CylinderMesh.new(), QuadMesh.new()]
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = at + Vector3(0, 0.5, 0)
	for mesh in meshes:
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _material(Color(1, 1, 1, 0.01))
		inst.scale = Vector3.ONE * 0.05
		holder.add_child(inst)
	var p := CPUParticles3D.new()
	p.amount = 1
	p.lifetime = 0.2
	var dot := SphereMesh.new()
	dot.radius = 0.01
	dot.height = 0.02
	p.mesh = dot
	p.material_override = _material(Color(1, 1, 1, 0.01))
	holder.add_child(p)
	var label := Label3D.new()
	label.text = "0"
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 1, 1, 0.01)
	label.pixel_size = 0.0005
	holder.add_child(label)
	get_tree().create_timer(0.3).timeout.connect(holder.queue_free)


# --- Building blocks -------------------------------------------------------

func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _spawn(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _material(color)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	inst.global_position = pos
	return inst


## Sends a sphere (or an arrow) from `from` to `to` along an arc of the
## given height. Returns the flight time.
func projectile(from: Vector3, to: Vector3, color: Color, size: float, arc: float, duration: float, arrow: bool) -> float:
	var mesh: Mesh
	if arrow:
		var box := BoxMesh.new()
		box.size = Vector3(size, size, 0.7)
		mesh = box
	else:
		var sphere := SphereMesh.new()
		sphere.radius = size
		sphere.height = size * 2
		mesh = sphere
	var inst := _spawn(mesh, color, from)
	var fly := func(t: float) -> void:
		var p := from.lerp(to, t) + Vector3(0, arc * 4.0 * t * (1.0 - t), 0)
		var dir := p - inst.global_position
		if arrow and dir.length() > 0.001:
			# look_at needs an "up" that isn't parallel to the flight direction.
			var up := Vector3.RIGHT if absf(dir.normalized().y) > 0.95 else Vector3.UP
			inst.look_at(p, up)
		inst.global_position = p
	var tween := inst.create_tween()
	tween.tween_method(fly, 0.0, 1.0, duration)
	tween.tween_callback(inst.queue_free)
	return duration


## An expanding, fading sphere after `delay` seconds.
func burst(pos: Vector3, radius: float, color: Color, duration: float, delay: float, hold := 0.0) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var inst := _spawn(sphere, Color(color, 0.6), pos)
	inst.scale = Vector3.ONE * 0.01
	inst.visible = false
	var tween := inst.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func(): inst.visible = true)
	tween.tween_property(inst, "scale", Vector3.ONE * radius, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if hold > 0.0:
		tween.tween_interval(hold)
	tween.tween_property(inst.material_override, "albedo_color:a", 0.0, duration * 0.5)
	tween.tween_callback(inst.queue_free)


## A flat shockwave ring growing to `radius`.
func ring(pos: Vector3, radius: float, color: Color, duration: float, delay: float) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	var inst := _spawn(torus, Color(color, 0.85), pos)
	inst.scale = Vector3(0.05, 0.3, 0.05)
	inst.visible = false
	var tween := inst.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func(): inst.visible = true)
	tween.tween_property(inst, "scale", Vector3(radius, 0.3, radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(inst.material_override, "albedo_color:a", 0.0, duration)
	tween.tween_callback(inst.queue_free)


## A column of light coming down on a point.
func pillar(pos: Vector3, color: Color, radius: float, delay: float) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = maxf(0.4, radius * 0.6)
	cylinder.bottom_radius = maxf(0.4, radius * 0.6)
	cylinder.height = 8.0
	var inst := _spawn(cylinder, Color(color, 0.7), pos + Vector3(0, 12, 0))
	inst.visible = false
	var tween := inst.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func(): inst.visible = true)
	tween.tween_property(inst, "global_position", pos + Vector3(0, 4, 0), 0.15)
	tween.tween_property(inst.material_override, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(inst.queue_free)


## A diagonal flash across a point (a big sword swing).
func slash(pos: Vector3, color: Color, delay: float) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1.6, 0.08, 0.08)
	var inst := _spawn(box, Color(color, 0.9), pos)
	inst.rotation = Vector3(0, randf() * TAU, PI / 4)
	inst.visible = false
	var tween := inst.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func(): inst.visible = true)
	tween.tween_property(inst, "scale", Vector3(1.4, 3, 3), 0.15)
	tween.tween_property(inst.material_override, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(inst.queue_free)


## Many small things falling from above onto an area. Returns the time
## until most of them have landed.
func rain(center: Vector3, radius: float, color: Color, count: int, delay: float, arrows: bool) -> float:
	for i in count:
		var angle := TAU * i / count + randf() * 0.5
		var r := radius * sqrt(randf())
		var land := center + Vector3(cos(angle) * r, 0.2, sin(angle) * r)
		var start := land + Vector3(0.8, 7.0, 0.4)
		var d := delay + randf() * 0.35
		var drop := func() -> void:
			if is_inside_tree():
				projectile(start, land, color, 0.06 if arrows else 0.12, 0.0, 0.35, arrows)
		get_tree().create_timer(d).timeout.connect(drop)
	return delay + 0.5


## Particles rising from the ground around a point.
func sparkles(center: Vector3, radius: float, color: Color, delay: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 40
	p.lifetime = 0.9
	p.explosiveness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(0.3, radius)
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var quad := SphereMesh.new()
	quad.radius = 0.05
	quad.height = 0.1
	p.mesh = quad
	p.material_override = _material(color)
	add_child(p)
	p.global_position = center + Vector3(0, 0.3, 0)
	var tween := p.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func(): p.emitting = true)
	tween.tween_interval(p.lifetime + 0.3)
	tween.tween_callback(p.queue_free)
