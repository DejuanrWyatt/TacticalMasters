extends Node3D
## 3D stand-in for one unit: a team-colored body with a job-colored hat,
## three bars over its head (HP, TG, Ultimate) that always face the camera,
## a status line above them (READY countdown or TG %), a name label, and a
## ring at its feet while it's ready (white when selected).
## Animations: walking a path, lunging at a target, casting, flinching when
## hit, and collapsing when defeated. Its collision body carries a "unit"
## meta so clicks on it can be picked.

const GameState = preload("res://scripts/core/game_state.gd")

const WALK_SPEED := 4.5
const BAR_WIDTH := 1.1
const BAR_HEIGHT := 0.1
const HP_COLOR := Color(0.35, 0.85, 0.35)
const HP_LOW_COLOR := Color(0.95, 0.3, 0.25)
const TG_COLOR := Color(0.4, 0.65, 1.0)
const TG_READY_COLOR := Color(1.0, 0.85, 0.3)
const ULT_COLOR := Color(0.95, 0.55, 0.15)
const ULT_FULL_COLOR := Color(1.0, 0.95, 0.6)
const CAST_COLOR := Color(0.75, 0.4, 1.0)

var unit_id := -1
var _model: Node3D
var _body_material: StandardMaterial3D
var _team_color: Color
var _label: Label3D
var _status: Label3D
var _bars: Node3D
var _fills: Array[MeshInstance3D] = []
var _fill_materials: Array[StandardMaterial3D] = []
var _ring: MeshInstance3D
var _ring_ready: StandardMaterial3D
var _ring_selected: StandardMaterial3D
var _body: StaticBody3D
var _move_tween: Tween
var _dead := false
## The death animation has finished; stay hidden.
var _gone := false


func setup(unit, team_color: Color) -> void:
	unit_id = unit.id
	_team_color = team_color
	_model = Node3D.new()
	add_child(_model)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.1
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.55
	_body_material = _material(team_color, false)
	body_mesh.material_override = _body_material
	_model.add_child(body_mesh)

	# A small "face" marker so you can tell which way the unit faces.
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.14, 0.08, 0.12)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.85, -0.28)
	nose.material_override = _material(team_color.lightened(0.5), false)
	_model.add_child(nose)

	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.26
	cone.height = 0.4
	var hat := MeshInstance3D.new()
	hat.mesh = cone
	hat.position.y = 1.28
	hat.material_override = _material(unit.job_data().color, false)
	_model.add_child(hat)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.5
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position.y = 0.05
	_ring_ready = _material(TG_READY_COLOR, true)
	_ring_selected = _material(Color.WHITE, true)
	_ring.material_override = _ring_ready
	_ring.visible = false
	add_child(_ring)

	_bars = Node3D.new()
	_bars.position.y = 1.8
	add_child(_bars)
	for i in 3:
		var y := -i * (BAR_HEIGHT + 0.03)
		var back := _bar_quad(Color(0.05, 0.05, 0.07, 0.85), 0)
		back.scale = Vector3(BAR_WIDTH + 0.04, BAR_HEIGHT + 0.03, 1)
		back.position.y = y
		var fill_material := _material(HP_COLOR, true)
		fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fill_material.no_depth_test = true
		fill_material.render_priority = 2
		var fill := MeshInstance3D.new()
		fill.mesh = QuadMesh.new()
		fill.material_override = fill_material
		fill.position = Vector3(0, y, 0.001)
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bars.add_child(fill)
		_fills.append(fill)
		_fill_materials.append(fill_material)

	_status = _label3d(36, 2.15)
	_label = _label3d(32, 2.42)
	_label.modulate = team_color.lightened(0.5)

	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.32
	capsule_shape.height = 1.2
	shape.shape = capsule_shape
	shape.position.y = 0.6
	_body = StaticBody3D.new()
	_body.add_child(shape)
	_body.set_meta("unit", unit.id)
	add_child(_body)


func _bar_quad(color: Color, priority: int) -> MeshInstance3D:
	var m := _material(color, true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = priority + 1
	var q := MeshInstance3D.new()
	q.mesh = QuadMesh.new()
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bars.add_child(q)
	return q


func _label3d(font_size: int, y: float) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	l.font_size = font_size
	l.outline_size = 10
	l.position.y = y
	add_child(l)
	return l


func _process(_delta: float) -> void:
	# Keep the bars flat to the screen, like a billboard.
	var camera := get_viewport().get_camera_3d()
	if camera != null and _bars.visible:
		_bars.global_basis = camera.global_basis


# --- State -----------------------------------------------------------------

func refresh(unit, is_selected: bool, shown: bool) -> void:
	visible = shown and (unit.is_alive() or (_dead and not _gone))
	# Hidden units must not block or reveal themselves to mouse picking.
	_body.collision_layer = 1 if shown and unit.is_alive() else 0
	_ring.visible = unit.ready and unit.is_alive()
	_ring.material_override = _ring_selected if is_selected else _ring_ready
	if _label.text != unit.job_name():
		_label.text = unit.job_name()


## Updates the bars and the status line; called every frame.
func set_status(unit, seconds_left: float) -> void:
	if not unit.is_alive():
		return
	var hp: float = float(unit.hp) / unit.max_hp()
	_set_bar(0, hp, HP_COLOR if hp > 0.3 else HP_LOW_COLOR)
	if unit.is_casting():
		# The TG bar becomes a cast bar filling up until the spell goes off.
		_set_bar(1, 1.0 - float(unit.casting.ticks) / unit.casting.total, CAST_COLOR)
	else:
		_set_bar(1, unit.tg / float(GameState.TG_MAX), TG_READY_COLOR if unit.ready else TG_COLOR)
	_set_bar(2, unit.ult / 100.0, ULT_FULL_COLOR if unit.ult >= 100 else ULT_COLOR)
	var cast_left: float = unit.casting.ticks / 10.0 if unit.is_casting() else 0.0
	var text: String
	var color: Color
	if unit.ready and unit.is_casting():
		text = "READY %d · %s %.1fs" % [ceili(seconds_left), unit.casting.name, cast_left]
		color = TG_READY_COLOR
	elif unit.is_casting():
		text = "%s %.1fs" % [unit.casting.name, cast_left]
		color = CAST_COLOR.lightened(0.3)
	elif unit.ready:
		text = "READY %d" % ceili(seconds_left)
		color = Color(1, 0.35, 0.3) if seconds_left <= 5.0 else TG_READY_COLOR
	else:
		text = "%.1fs" % seconds_left
		color = Color(0.75, 0.85, 1.0, 0.75)
	# Changing a Label3D's text rebuilds its mesh, so only do it when needed.
	if _status.text != text:
		_status.text = text
	_status.modulate = color


func _set_bar(i: int, fraction: float, color: Color) -> void:
	fraction = clampf(fraction, 0.0, 1.0)
	var fill := _fills[i]
	fill.visible = fraction > 0.0
	fill.scale = Vector3(BAR_WIDTH * maxf(fraction, 0.001), BAR_HEIGHT, 1)
	fill.position.x = -BAR_WIDTH * (1.0 - fraction) * 0.5
	_fill_materials[i].albedo_color = color


# --- Animation -------------------------------------------------------------

func place(target: Vector3) -> void:
	position = target


func face(target: Vector3) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	if flat.distance_to(global_position) > 0.01:
		_model.look_at(flat, Vector3.UP)


## Walks along world points; returns how long it takes.
func walk(points: Array[Vector3]) -> float:
	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()
	var total := 0.0
	var from := position
	for p in points:
		var seconds := from.distance_to(p) / WALK_SPEED
		if seconds <= 0.0:
			continue
		_move_tween.tween_callback(face.bind(p))
		_move_tween.tween_property(self, "position", p, seconds)
		total += seconds
		from = p
	if total == 0.0:
		_move_tween.kill()
		return 0.0
	# A little bob while walking.
	var bob := create_tween().set_loops(maxi(1, ceili(total / 0.3)))
	bob.tween_property(_model, "position:y", 0.08, 0.15)
	bob.tween_property(_model, "position:y", 0.0, 0.15)
	return total


## Steps toward a target and back (melee swing).
func lunge(target: Vector3, distance := 0.5) -> void:
	face(target)
	var dir := (target - global_position)
	dir.y = 0
	dir = dir.normalized() * distance
	var t := create_tween()
	t.tween_property(_model, "position", Vector3(dir.x, 0.1, dir.z), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_model, "position", Vector3.ZERO, 0.22).set_delay(0.08)


## Crouches and springs up (spell casting).
func cast(target: Vector3) -> void:
	face(target)
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3(1.1, 0.85, 1.1), 0.12)
	t.tween_property(_model, "scale", Vector3(0.95, 1.15, 0.95), 0.12)
	t.tween_property(_model, "scale", Vector3.ONE, 0.15)


## Flashes and shakes after `delay` seconds.
func flinch(delay: float, color := Color(1, 0.25, 0.2)) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(_body_material, "albedo_color", color, 0.05)
	t.parallel().tween_property(_model, "position:x", 0.12, 0.05)
	t.tween_property(_model, "position:x", -0.12, 0.06)
	t.tween_property(_model, "position:x", 0.0, 0.06)
	t.tween_property(_body_material, "albedo_color", _team_color, 0.2)


## Topples over and sinks out of sight after `delay` seconds.
func die(delay: float) -> void:
	_dead = true
	_ring.visible = false
	_bars.visible = false
	_status.visible = false
	var t := create_tween()
	t.tween_interval(delay + 0.2)
	t.tween_property(_model, "rotation:x", -PI / 2, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_property(_model, "position:y", -1.2, 0.8).set_delay(0.3)
	t.tween_callback(func():
		_gone = true
		visible = false)


static func _material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
