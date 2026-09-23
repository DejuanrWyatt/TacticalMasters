extends Node3D
## 3D battlefield: one block per ground tile (TILE_SIZE meters, raised by its
## height level) with a textured top and darker cliff sides, water, trees
## and rocks for decoration (visual only, placed the same way every time for
## a map), fog-of-war quads, and the targeting visuals: the shaded area a
## unit can walk to, the path dots to the cursor, range rings and
## area-of-effect circles. Tile collision bodies let the battle raycast
## clicks to a ground point.

const GameState = preload("res://scripts/core/game_state.gd")

const HEIGHT_STEP := GameState.LEVEL_HEIGHT
const BASE_DEPTH := 0.6
## A rock standing on a tile: tall enough to hide a unit behind it.
const ROCK_HEIGHT := 2.6
const ROCK_COLOR := Color(0.31, 0.29, 0.28)
## Tops of ground that burns, and of a healing spring.
const EMBER_COLOR := Color(0.42, 0.15, 0.11)
const SPRING_COLOR := Color(0.18, 0.5, 0.48)
const WATER_TOP := -0.25
const GROUND_COLORS := [
	Color(0.2, 0.38, 0.62),   # 0: water
	Color(0.36, 0.52, 0.26),  # 1: grass
	Color(0.45, 0.52, 0.28),  # 2: high grass
	Color(0.52, 0.43, 0.29),  # 3: dirt
	Color(0.47, 0.45, 0.42),  # 4: rock
	Color(0.58, 0.57, 0.55),  # 5: peak
]
const FOG_COLOR := Color(0.05, 0.07, 0.12, 0.6)
const MOVE_AREA_COLOR := Color(0.35, 0.65, 1.0, 0.3)
## Where a clicked enemy could walk, and how far it could reach from there.
const THREAT_AREA_COLOR := Color(1.0, 0.35, 0.3, 0.2)

## Colors of the cliff sides per level (the tops use GROUND_COLORS).
const SIDE_COLORS := [
	Color(0.16, 0.3, 0.5),
	Color(0.36, 0.28, 0.2),
	Color(0.38, 0.3, 0.21),
	Color(0.42, 0.34, 0.24),
	Color(0.36, 0.35, 0.33),
	Color(0.44, 0.43, 0.41),
]

var state
var _fog := {}
var _noise: NoiseTexture2D
var _materials := {}
var _move_area: MultiMeshInstance3D
var _threat_area: MultiMeshInstance3D
var _threat_ring: MeshInstance3D
var _path_dots: MultiMeshInstance3D
var _path_ok: StandardMaterial3D
var _path_bad: StandardMaterial3D
var _range_ring: MeshInstance3D
var _min_ring: MeshInstance3D
var _aoe_disc: MeshInstance3D
var _patch: MeshInstance3D
var _aoe_ok: StandardMaterial3D
var _aoe_bad: StandardMaterial3D


func build(p_state, seed_text := "") -> void:
	state = p_state
	_noise = NoiseTexture2D.new()
	_noise.width = 256
	_noise.height = 256
	_noise.seamless = true
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.025
	fnl.fractal_octaves = 3
	_noise.noise = fnl
	# Subtle variation only: map the noise to 85-100% brightness.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.85, 0.85))
	ramp.set_color(1, Color(1, 1, 1))
	_noise.color_ramp = ramp
	for y in state.tiles_y:
		for x in state.tiles_x:
			_build_tile(Vector2i(x, y))
	_decorate(seed_text)

	_move_area = _multimesh(_plane(Vector2(0.5, 0.5)), _material(MOVE_AREA_COLOR, true, false))
	_threat_area = _multimesh(_plane(Vector2(0.5, 0.5)), _material(THREAT_AREA_COLOR, true, false))
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	_path_ok = _material(Color(0.5, 1.0, 0.6), true, true)
	_path_bad = _material(Color(1.0, 0.4, 0.35), true, true)
	_path_dots = _multimesh(dot, _path_ok)
	# The middle of the map is marked out when it can be held to win.
	if state.tune("capture_seconds") > 0.0:
		var point := _ring_mesh(Color(1.0, 0.9, 0.4, 0.7))
		_place_ring(point, state.capture_point(), state.CAPTURE_RADIUS)
	_threat_ring = _ring_mesh(Color(1.0, 0.4, 0.35, 0.7))
	_range_ring = _ring_mesh(Color(1.0, 0.6, 0.2, 0.9))
	_min_ring = _ring_mesh(Color(1.0, 0.3, 0.2, 0.6))
	var disc := CylinderMesh.new()
	disc.height = 0.04
	disc.rings = 1
	_aoe_disc = MeshInstance3D.new()
	_aoe_disc.mesh = disc
	_aoe_ok = _material(Color(1.0, 0.25, 0.15, 0.4), true, true)
	_aoe_bad = _material(Color(0.6, 0.6, 0.6, 0.3), true, true)
	_aoe_disc.visible = false
	add_child(_aoe_disc)


func _build_tile(t: Vector2i) -> void:
	var level: int = state.tile_level(t)
	var center := Vector2((t.x + 0.5) * state.TILE_SIZE, (t.y + 0.5) * state.TILE_SIZE)
	var rock: bool = state.is_cover(center)
	var hazard: int = state.hazard_at(center)
	if rock:
		level = 1  # the rock stands on ordinary ground; it is drawn on top
	var top := _level_top(level)
	var depth := top + BASE_DEPTH + 0.3
	var size: float = state.TILE_SIZE
	var box := BoxMesh.new()
	box.size = Vector3(size, depth, size)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	var lv := mini(level, GROUND_COLORS.size() - 1)
	# The block's sides are cliff/dirt; its top gets the ground color.
	mesh.material_override = _ground_material(SIDE_COLORS[lv], 0.8)
	mesh.position = Vector3((t.x + 0.5) * size, top - depth / 2.0, (t.y + 0.5) * size)
	add_child(mesh)
	var top_face := MeshInstance3D.new()
	top_face.mesh = _plane(Vector2(size, size))
	var color: Color = GROUND_COLORS[lv]
	if hazard < 0:
		color = EMBER_COLOR
	elif hazard > 0:
		color = SPRING_COLOR
	if (t.x + t.y) % 2 == 1:
		color = color.darkened(0.04)
	top_face.material_override = _water_material() if level == 0 else _ground_material(color, 0.9)
	top_face.position = Vector3(mesh.position.x, top + 0.002, mesh.position.z)
	add_child(top_face)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	var body := StaticBody3D.new()
	body.add_child(shape)
	body.position = mesh.position
	add_child(body)

	var fog := MeshInstance3D.new()
	fog.mesh = _plane(Vector2(size, size))
	fog.material_override = _material(FOG_COLOR, true, false)
	fog.position = Vector3(mesh.position.x, top + 0.04, mesh.position.z)
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog.visible = false
	add_child(fog)

	if rock:
		var stone := MeshInstance3D.new()
		var stone_box := BoxMesh.new()
		stone_box.size = Vector3(size * 0.82, ROCK_HEIGHT, size * 0.82)
		stone.mesh = stone_box
		stone.material_override = _ground_material(ROCK_COLOR, 0.75)
		stone.position = Vector3(mesh.position.x, top + ROCK_HEIGHT / 2.0, mesh.position.z)
		add_child(stone)
	_fog[t] = fog


## Lit ground material with a subtle noise pattern (world-space, so it flows
## across tiles).
func _ground_material(color: Color, roughness: float) -> StandardMaterial3D:
	var key := "ground/%s" % color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.albedo_texture = _noise
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.12, 0.12, 0.12)
		m.roughness = roughness
		_materials[key] = m
	return _materials[key]


func _water_material() -> StandardMaterial3D:
	if not _materials.has("water"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.22, 0.45, 0.72, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _noise
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.3, 0.3, 0.3)
		m.metallic = 0.3
		m.roughness = 0.15
		_materials["water"] = m
	return _materials["water"]


## Trees and rocks, placed deterministically from the map id and mirrored
## like the map, on low ground away from the starting areas. Visual only:
## they don't block movement or line of sight.
func _decorate(seed_text: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text if seed_text != "" else "map")
	var size: Vector2 = state.size_meters()
	var trunk_mat := _plain_material(Color(0.35, 0.24, 0.15))
	var leaf_mats := [_plain_material(Color(0.2, 0.42, 0.2)), _plain_material(Color(0.26, 0.48, 0.22)), _plain_material(Color(0.3, 0.44, 0.18))]
	var rock_mat := _plain_material(Color(0.36, 0.35, 0.34))
	for y in state.tiles_y / 2:
		for x in state.tiles_x:
			if rng.randf() > 0.16:
				continue
			var p := Vector2((x + rng.randf_range(0.15, 0.85)) * state.TILE_SIZE, (y + rng.randf_range(0.15, 0.85)) * state.TILE_SIZE)
			var is_tree := rng.randf() < 0.6
			var scale := rng.randf_range(0.75, 1.25)
			var leaf: Material = leaf_mats[rng.randi_range(0, leaf_mats.size() - 1)]
			for spot in [p, size - p]:  # mirrored, like the map
				var level: int = state.level_at(spot)
				if level < 1 or level > 3 or _near_spawn(spot):
					continue
				var base := ground(spot)
				if is_tree:
					_tree(base, scale, trunk_mat, leaf)
				else:
					_rock(base, scale, rock_mat)


func _near_spawn(p: Vector2) -> bool:
	for u in state.units:
		if u.pos.distance_to(p) < 3.0:
			return true
	return false


func _plain_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


func _tree(base: Vector3, scale: float, trunk_mat: Material, leaf_mat: Material) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.07 * scale
	trunk.bottom_radius = 0.11 * scale
	trunk.height = 0.7 * scale
	var t := MeshInstance3D.new()
	t.mesh = trunk
	t.material_override = trunk_mat
	t.position = base + Vector3(0, 0.35 * scale, 0)
	add_child(t)
	for i in 2:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = (0.55 - i * 0.15) * scale
		cone.height = 0.8 * scale
		var c := MeshInstance3D.new()
		c.mesh = cone
		c.material_override = leaf_mat
		c.position = base + Vector3(0, (0.9 + i * 0.4) * scale, 0)
		add_child(c)


func _rock(base: Vector3, scale: float, mat: Material) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.3 * scale
	sphere.height = 0.36 * scale
	var r := MeshInstance3D.new()
	r.mesh = sphere
	r.material_override = mat
	r.scale = Vector3(1.2, 0.8, 1.0)
	r.position = base + Vector3(0, 0.08 * scale, 0)
	add_child(r)


func _level_top(level: int) -> float:
	return WATER_TOP if level == 0 else level * HEIGHT_STEP


## World position on the ground surface at a map point (meters).
func ground(p: Vector2) -> Vector3:
	var level := 0
	if state.in_bounds(p):
		level = state.level_at(p)
	return Vector3(p.x, maxf(0.0, _level_top(level)), p.y)


func _plane(size: Vector2) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = size
	return plane


func _multimesh(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst


func _ring_mesh(color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.mesh = TorusMesh.new()
	ring.material_override = _material(color, true, true)
	ring.visible = false
	add_child(ring)
	return ring


func _material(color: Color, unshaded: bool, on_top: bool) -> StandardMaterial3D:
	var key := "%s/%s/%s" % [color.to_html(), unshaded, on_top]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if color.a < 1.0 or on_top:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if on_top:
			m.no_depth_test = true
			m.render_priority = 1
		_materials[key] = m
	return _materials[key]


## Darkens every tile not in `visible_set`. Disabled shows everything.
func set_fog(visible_set: Dictionary, enabled: bool) -> void:
	for t in _fog:
		_fog[t].visible = enabled and not visible_set.has(t)


## Shades the navigation nodes a unit can walk to (empty hides it).
func show_move_area(nodes: Array) -> void:
	var mm := _move_area.multimesh
	mm.instance_count = nodes.size()
	for i in nodes.size():
		var p: Vector2 = state.node_pos(nodes[i])
		mm.set_instance_transform(i, Transform3D(Basis(), ground(p) + Vector3(0, 0.03, 0)))


## What a clicked enemy threatens: the ground it could walk to, and a ring
## for how far it could reach from where it stands. No nodes hides it.
func show_threat(nodes: Array, center: Vector2, radius: float) -> void:
	var mm := _threat_area.multimesh
	mm.instance_count = nodes.size()
	for i in nodes.size():
		var p: Vector2 = state.node_pos(nodes[i])
		mm.set_instance_transform(i, Transform3D(Basis(), ground(p) + Vector3(0, 0.035, 0)))
	_place_ring(_threat_ring, center, radius if not nodes.is_empty() else 0.0)


## Dots along a walking path; red when the destination is out of reach.
func show_path(points: Array, ok: bool) -> void:
	var dots: Array[Vector3] = []
	for i in range(1, points.size()):
		var a: Vector3 = ground(points[i - 1])
		var b: Vector3 = ground(points[i])
		var steps := maxi(1, ceili(a.distance_to(b) / 0.25))
		for s in steps:
			dots.append(a.lerp(b, float(s + 1) / steps) + Vector3(0, 0.12, 0))
	var mm := _path_dots.multimesh
	mm.instance_count = dots.size()
	for i in dots.size():
		mm.set_instance_transform(i, Transform3D(Basis(), dots[i]))
	_path_dots.material_override = _path_ok if ok else _path_bad


## Range rings around a caster (0 radius hides a ring).
func show_range(center: Vector2, min_radius: float, max_radius: float) -> void:
	_place_ring(_range_ring, center, max_radius)
	_place_ring(_min_ring, center, min_radius)


func _place_ring(ring: MeshInstance3D, center: Vector2, radius: float) -> void:
	ring.visible = radius > 0.0
	if not ring.visible:
		return
	var torus: TorusMesh = ring.mesh
	torus.inner_radius = maxf(0.01, radius - 0.05)
	torus.outer_radius = radius + 0.05
	ring.position = ground(center) + Vector3(0, 0.1, 0)


## Area-of-effect circle at a point; grey when the point isn't a legal target.
## The patch an ability would cover: a circle, a line from the caster, or a
## cone. `points` are the corners for a line or cone (in meters).
func show_patch(points: PackedVector2Array, ok: bool) -> void:
	if _patch == null:
		_patch = MeshInstance3D.new()
		_patch.mesh = ImmediateMesh.new()
		add_child(_patch)
	_patch.visible = points.size() >= 3
	if not _patch.visible:
		return
	_patch.material_override = _aoe_ok if ok else _aoe_bad
	var mesh: ImmediateMesh = _patch.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size() - 1):
		for p in [points[0], points[i], points[i + 1]]:
			mesh.surface_add_vertex(ground(p) + Vector3(0, 0.09, 0))
	mesh.surface_end()


func hide_patch() -> void:
	if _patch != null:
		_patch.visible = false


func show_aoe(center: Vector2, radius: float, ok: bool) -> void:
	_aoe_disc.visible = radius > 0.0
	if not _aoe_disc.visible:
		return
	var disc: CylinderMesh = _aoe_disc.mesh
	disc.top_radius = radius
	disc.bottom_radius = radius
	_aoe_disc.material_override = _aoe_ok if ok else _aoe_bad
	_aoe_disc.position = ground(center) + Vector3(0, 0.08, 0)


## Shows every targeting visual once (for a moment, at `center`) so their
## shaders compile during loading rather than the first time they're needed.
func prewarm(center: Vector2) -> void:
	show_move_area([state.node_of(center)])
	show_path([center, center + Vector2(1, 0)], true)
	show_range(center, 1.0, 2.0)
	show_aoe(center, 1.0, true)
	show_patch(PackedVector2Array([center, center + Vector2(1, 0), center + Vector2(1, 1)]), true)


func clear_targeting() -> void:
	show_move_area([])
	show_path([], true)
	show_range(Vector2.ZERO, 0.0, 0.0)
	_aoe_disc.visible = false
	hide_patch()
