extends Node3D
## 3D battlefield: one box per ground tile (TILE_SIZE meters, raised by its
## height level), fog-of-war quads, and the targeting visuals: the shaded
## area a unit can walk to, the path dots to the cursor, range rings and
## area-of-effect circles. Tile collision bodies let the battle raycast
## clicks to a ground point.

const HEIGHT_STEP := 0.7
const BASE_DEPTH := 0.6
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

var state
var _fog := {}
var _materials := {}
var _move_area: MultiMeshInstance3D
var _path_dots: MultiMeshInstance3D
var _path_ok: StandardMaterial3D
var _path_bad: StandardMaterial3D
var _range_ring: MeshInstance3D
var _min_ring: MeshInstance3D
var _aoe_disc: MeshInstance3D
var _aoe_ok: StandardMaterial3D
var _aoe_bad: StandardMaterial3D


func build(p_state) -> void:
	state = p_state
	for y in state.tiles_y:
		for x in state.tiles_x:
			_build_tile(Vector2i(x, y))

	_move_area = _multimesh(_plane(Vector2(0.5, 0.5)), _material(MOVE_AREA_COLOR, true, false))
	var dot := SphereMesh.new()
	dot.radius = 0.07
	dot.height = 0.14
	_path_ok = _material(Color(0.5, 1.0, 0.6), true, true)
	_path_bad = _material(Color(1.0, 0.4, 0.35), true, true)
	_path_dots = _multimesh(dot, _path_ok)
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
	var top := _level_top(level)
	var depth := top + BASE_DEPTH + 0.3
	var size: float = state.TILE_SIZE
	var box := BoxMesh.new()
	box.size = Vector3(size, depth, size)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	var color: Color = GROUND_COLORS[mini(level, GROUND_COLORS.size() - 1)]
	if (t.x + t.y) % 2 == 1:
		color = color.darkened(0.06)
	mesh.material_override = _material(color, false, false)
	mesh.position = Vector3((t.x + 0.5) * size, top - depth / 2.0, (t.y + 0.5) * size)
	add_child(mesh)

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
	_fog[t] = fog


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
func show_aoe(center: Vector2, radius: float, ok: bool) -> void:
	_aoe_disc.visible = radius > 0.0
	if not _aoe_disc.visible:
		return
	var disc: CylinderMesh = _aoe_disc.mesh
	disc.top_radius = radius
	disc.bottom_radius = radius
	_aoe_disc.material_override = _aoe_ok if ok else _aoe_bad
	_aoe_disc.position = ground(center) + Vector3(0, 0.08, 0)


func clear_targeting() -> void:
	show_move_area([])
	show_path([], true)
	show_range(Vector2.ZERO, 0.0, 0.0)
	_aoe_disc.visible = false
