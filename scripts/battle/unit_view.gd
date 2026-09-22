extends Node3D
## One unit on the battlefield: an animated 3D character (KayKit Adventurers,
## CC0, in assets/characters; a colored capsule if the model is missing) with
## its job's gear and a team-colored cape and ring,
## three bars over its head (HP, TG, Ultimate) that always face the camera,
## a status line above them (READY countdown or TG %), a name label, and a
## ring at its feet while it's ready (white when selected).
## Status effects show as small colored tags above the bars. Animations:
## walking a path, lunging at a target, casting, flinching when hit,
## toppling when knocked out, standing back up when revived, and sinking
## away when gone. Its collision body carries a "unit"
## meta so clicks on it can be picked.

const GameState = preload("res://scripts/core/game_state.gd")
const Jobs = preload("res://scripts/core/jobs.gd")

const WALK_SPEED := 4.5
const BAR_WIDTH := 1.1
const TAG_SPACING := 0.55
const BAR_HEIGHT := 0.1
const HP_COLOR := Color(0.35, 0.85, 0.35)
const HP_LOW_COLOR := Color(0.95, 0.3, 0.25)
const TG_COLOR := Color(0.4, 0.65, 1.0)
const TG_READY_COLOR := Color(1.0, 0.85, 0.3)
const ULT_COLOR := Color(0.95, 0.55, 0.15)
const ULT_FULL_COLOR := Color(1.0, 0.95, 0.6)
const CAST_COLOR := Color(0.75, 0.4, 1.0)
const CHARACTER_DIR := "res://assets/characters/"
## Characters are about 2.5 units tall; this makes them ~1.3 m.
const CHARACTER_SCALE := 0.52
## Per job: model, the gear meshes to show (others are hidden), animations,
## and an optional tint for the whole model.
const JOB_LOOKS := {
	"knight": {"model": "Knight.glb", "gear": ["1H_Sword", "Badge_Shield"],
		"attack": "1H_Melee_Attack_Chop", "shoot": "1H_Melee_Attack_Slice_Diagonal", "cast": "Block"},
	"squire": {"model": "Rogue.glb", "gear": ["Knife", "Knife_Offhand"],
		"attack": "Dualwield_Melee_Attack_Stab", "shoot": "Throw", "cast": "Cheer"},
	"archer": {"model": "Rogue_Hooded.glb", "gear": ["2H_Crossbow"],
		"attack": "2H_Ranged_Shoot", "shoot": "2H_Ranged_Shoot", "cast": "2H_Ranged_Aiming"},
	"monk": {"model": "Barbarian.glb", "gear": [], "idle": "Unarmed_Idle",
		"attack": "Unarmed_Melee_Attack_Punch_A", "shoot": "Unarmed_Melee_Attack_Kick", "cast": "Cheer"},
	"black_mage": {"model": "Mage.glb", "gear": ["2H_Staff"], "tint": Color(0.42, 0.34, 0.55),
		"attack": "1H_Melee_Attack_Chop", "shoot": "Spellcast_Shoot", "cast": "Spellcast_Long"},
	"white_mage": {"model": "Mage.glb", "gear": ["1H_Wand", "Spellbook_open"], "tint": Color(1.35, 1.3, 1.2),
		"attack": "1H_Melee_Attack_Chop", "shoot": "Spellcast_Shoot", "cast": "Spellcast_Raise"},
}

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
## Knocked out (lying down) / gone for good (sunk out of sight).
var _down := false
var _gone := false
var _tags: Array[Label3D] = []
## The animated character (null when using the capsule fallback).
var _character: Node3D
var _anim: AnimationPlayer
var _look: Dictionary = {}
var _team_ring: MeshInstance3D


func setup(unit, team_color: Color) -> void:
	unit_id = unit.id
	_team_color = team_color
	_model = Node3D.new()
	add_child(_model)
	_body_material = _material(team_color, false)
	if not _load_character(unit.job, team_color):
		_build_capsule(unit, team_color)

	# Thin team-colored ring always under the unit.
	var team_torus := TorusMesh.new()
	team_torus.inner_radius = 0.36
	team_torus.outer_radius = 0.42
	_team_ring = MeshInstance3D.new()
	_team_ring.mesh = team_torus
	_team_ring.position.y = 0.03
	_team_ring.material_override = _material(team_color, true)
	add_child(_team_ring)
	_finish_setup(unit, team_color)


## Loads the job's animated character; false if the model isn't available.
func _load_character(job: String, team_color: Color) -> bool:
	_look = JOB_LOOKS.get(job, {})
	if _look.is_empty() and Jobs.has_job(job):
		# An imported class borrows a built-in look, tinted with its color.
		var data := Jobs.job(job)
		_look = JOB_LOOKS.get(data.get("look", "black_mage"), JOB_LOOKS.black_mage).duplicate()
		_look["tint"] = Color.WHITE.lerp(data.color, 0.6)
	if _look.is_empty() or not ResourceLoader.exists(CHARACTER_DIR + _look.model):
		push_warning("No character model for job '%s': using the simple stand-in." % job)
		return false
	var scene: PackedScene = load(CHARACTER_DIR + _look.model)
	_character = scene.instantiate()
	# The models face +Z; units face -Z (look_at's forward).
	_character.rotation.y = PI
	_character.scale = Vector3.ONE * CHARACTER_SCALE
	_model.add_child(_character)
	var tint: Color = _look.get("tint", Color.WHITE)
	for mesh in _character.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var parent_name := String(mi.get_parent().name)
		# Only this job's gear is shown in the hands.
		if parent_name.begins_with("handslot"):
			mi.visible = _look.gear.has(String(mi.name))
		if String(mi.name).ends_with("_Cape"):
			_tint_mesh(mi, team_color.lerp(Color.WHITE, 0.15))
		elif tint != Color.WHITE:
			_tint_mesh(mi, tint)
	var players := _character.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for name in [_idle_anim(), "Walking_A", "Running_A", "Spellcasting", "Lie_Idle"]:
			if _anim.has_animation(name):
				_anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR
		_anim.animation_finished.connect(_on_animation_finished)
		_play(_idle_anim())
	return true


## Multiplies a mesh's own colors by `color` (keeps its texture).
static func _tint_mesh(mi: MeshInstance3D, color: Color) -> void:
	for i in mi.get_surface_override_material_count():
		var base := mi.get_active_material(i)
		if base is StandardMaterial3D:
			var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = m.albedo_color * color
			mi.set_surface_override_material(i, m)


func _idle_anim() -> String:
	return _look.get("idle", "Idle")


func _play(name: String, blend := 0.2) -> void:
	if _anim != null and _anim.has_animation(name):
		_anim.play(name, blend)


## One-shot actions (attacks, hits...) return to idle when they finish;
## the knocked-out pose stays.
func _on_animation_finished(name: StringName) -> void:
	if _down:
		return
	if String(name) != _idle_anim() and not (_move_tween and _move_tween.is_running()):
		_play(_idle_anim())


func _build_capsule(unit, team_color: Color) -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.1
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.55
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


func _finish_setup(unit, team_color: Color) -> void:
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

	# Up to 4 status tags in a row just above the bars (they face the camera with the bars).
	for i in 4:
		var tag := Label3D.new()
		tag.no_depth_test = true
		tag.pixel_size = 0.006
		tag.font_size = 40
		tag.outline_size = 12
		tag.position = Vector3(0, 0.24, 0)
		tag.visible = false
		_bars.add_child(tag)
		_tags.append(tag)

	_status = _label3d(36, 2.36)
	_label = _label3d(32, 2.62)
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
	visible = shown and not _gone and (unit.is_alive() or unit.is_ko() or _down)
	# Hidden units must not block or reveal themselves to mouse picking.
	# Knocked-out units stay pickable so Raise can target them.
	_body.collision_layer = 1 if shown and (unit.is_alive() or unit.is_ko()) else 0
	_ring.visible = unit.ready and unit.is_alive()
	_ring.material_override = _ring_selected if is_selected else _ring_ready
	if _label.text != unit.job_name():
		_label.text = unit.job_name()
	# Keep the model turned the way the unit faces (unless it's mid-walk).
	if unit.is_alive() and not (_move_tween and _move_tween.is_running()):
		face(global_position + Vector3(unit.facing.x, 0, unit.facing.y))


## Updates the bars and the status line; called every frame.
func set_status(unit, seconds_left: float) -> void:
	if unit.is_ko():
		var ko_text := "KO %d" % ceili(unit.ko_ticks / 10.0)
		if _status.text != ko_text:
			_status.text = ko_text
		_status.modulate = Color(0.8, 0.8, 0.85, 0.9)
		return
	if not unit.is_alive():
		return
	_set_tags(unit)
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


## Shows one colored tag per active status (e.g. BRN, SLW), centered in a row.
func _set_tags(unit) -> void:
	var count := mini(unit.statuses.size(), _tags.size())
	for i in _tags.size():
		var tag := _tags[i]
		tag.position.x = (i - (count - 1) / 2.0) * TAG_SPACING
		if i < count:
			var info: Dictionary = Jobs.STATUSES[unit.statuses[i].id]
			if tag.text != info.tag:
				tag.text = info.tag
			tag.modulate = info.color
			tag.visible = true
		else:
			tag.visible = false


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
	# Footsteps every ~0.4 s along the way.
	if visible:
		var steps := create_tween()
		for i in maxi(1, floori(total / 0.4)):
			steps.tween_interval(0.4 if i > 0 else 0.05)
			steps.tween_callback(func(): Audio.play_at("step", global_position, -8.0))
	if _anim != null:
		_play("Walking_A")
		_move_tween.tween_callback(_play.bind(_idle_anim()))
	else:
		# A little bob while walking.
		var bob := create_tween().set_loops(maxi(1, ceili(total / 0.3)))
		bob.tween_property(_model, "position:y", 0.08, 0.15)
		bob.tween_property(_model, "position:y", 0.0, 0.15)
	return total


## Steps toward a target and back (melee swing).
func lunge(target: Vector3, distance := 0.5) -> void:
	face(target)
	_play(_look.get("attack", ""), 0.1)
	var dir := (target - global_position)
	dir.y = 0
	dir = dir.normalized() * distance
	var t := create_tween()
	t.tween_property(_model, "position", Vector3(dir.x, 0.1, dir.z), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_model, "position", Vector3.ZERO, 0.22).set_delay(0.08)


## Crouches and springs up (spell casting).
func cast(target: Vector3) -> void:
	face(target)
	if _anim != null:
		_play(_look.get("shoot", ""), 0.1)
		return
	var t := create_tween()
	t.tween_property(_model, "scale", Vector3(1.1, 0.85, 1.1), 0.12)
	t.tween_property(_model, "scale", Vector3(0.95, 1.15, 0.95), 0.12)
	t.tween_property(_model, "scale", Vector3.ONE, 0.15)


## Charging a spell with a cast time: the job's casting pose.
func channel() -> void:
	if _anim != null:
		_play(_look.get("cast", ""), 0.15)
	else:
		cast(global_position + _model.global_basis.z * -1.0)


## Flashes and shakes after `delay` seconds.
func flinch(delay: float, color := Color(1, 0.25, 0.2)) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	if _anim != null:
		# Damage plays the hit reaction; healing just a light shake.
		if color.r > color.g:
			t.tween_callback(_play.bind("Hit_A", 0.05))
		t.tween_property(_model, "position:x", 0.06, 0.05)
		t.tween_property(_model, "position:x", 0.0, 0.08)
		return
	t.tween_property(_body_material, "albedo_color", color, 0.05)
	t.parallel().tween_property(_model, "position:x", 0.12, 0.05)
	t.tween_property(_model, "position:x", -0.12, 0.06)
	t.tween_property(_model, "position:x", 0.0, 0.06)
	t.tween_property(_body_material, "albedo_color", _team_color, 0.2)


## Shows the ready/selected ring once so its shader compiles during loading.
func prewarm() -> void:
	_ring.visible = true


## Knocked out: topples over after `delay` seconds and lies there (it can
## still be revived).
func knock_out(delay: float) -> void:
	_down = true
	_ring.visible = false
	_bars.visible = false
	for tag in _tags:
		tag.visible = false
	_team_ring.visible = false
	var t := create_tween()
	t.tween_interval(delay + 0.2)
	if _anim != null:
		t.tween_callback(_play.bind("Death_A", 0.1))
		return
	t.tween_property(_model, "rotation:x", -PI / 2, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_body_material, "albedo_color", _team_color.darkened(0.5), 0.35)


## Revived: stands back up after `delay` seconds.
func revive(delay: float) -> void:
	_down = false
	_team_ring.visible = true
	var t := create_tween()
	t.tween_interval(delay)
	if _anim != null:
		t.tween_callback(_play.bind("Lie_StandUp", 0.1))
		t.tween_callback(func(): _bars.visible = true)
		return
	t.tween_property(_model, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_body_material, "albedo_color", _team_color, 0.4)
	t.tween_callback(func(): _bars.visible = true)


## Gone for good: sinks out of sight.
func vanish() -> void:
	_status.visible = false
	var t := create_tween()
	t.tween_property(_model, "position:y", -1.2, 0.8)
	var hide_it := func() -> void:
		_gone = true
		visible = false
	t.tween_callback(hide_it)


static func _material(color: Color, unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
