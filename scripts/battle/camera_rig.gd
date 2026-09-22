extends Node3D
## Free tactics camera. The rig sits on the point being looked at, with a
## pitch pivot and the camera hanging off it.
##   WASD / arrow keys   pan              R / F         raise / lower
##   Q / E               rotate           right-drag    rotate and tilt
##   middle-drag         pan              mouse wheel   zoom
## Keys are the defaults; they follow the player's bindings (Keybinds).

const PAN_SPEED := 8.0
const RAISE_SPEED := 4.0
const ROTATE_SPEED := 1.8
const DRAG_ROTATE := 0.006
const MIN_PITCH := -1.48  # about -85 degrees
const MAX_PITCH := -0.17  # about -10 degrees
const MIN_DISTANCE := 4.0
const MAX_DISTANCE := 60.0

var camera: Camera3D
var target_position := Vector3.ZERO
var yaw := deg_to_rad(45.0)
var pitch := deg_to_rad(-40.0)
var distance := 22.0
var _target_distance := 22.0
var _pivot: Node3D
var _rotating := false
## Off while a menu is open, so typing there doesn't move the camera.
var keys_enabled := true
var _panning := false


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	camera = Camera3D.new()
	camera.fov = 40.0
	_pivot.add_child(camera)
	camera.current = true
	_apply_transform()


func snap_to(p: Vector3) -> void:
	target_position = p
	position = p


func focus_on(p: Vector3) -> void:
	target_position = p


func _right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func _process(delta: float) -> void:
	if keys_enabled:
		var move := Vector3.ZERO
		if Input.is_action_pressed("tm_cam_forward"):
			move += _forward()
		if Input.is_action_pressed("tm_cam_back"):
			move -= _forward()
		if Input.is_action_pressed("tm_cam_right"):
			move += _right()
		if Input.is_action_pressed("tm_cam_left"):
			move -= _right()
		target_position += move.normalized() * PAN_SPEED * Settings.camera_speed * delta * (distance / 22.0)
		if Input.is_action_pressed("tm_cam_up"):
			target_position.y += RAISE_SPEED * delta
		if Input.is_action_pressed("tm_cam_down"):
			target_position.y -= RAISE_SPEED * delta
		if Input.is_action_pressed("tm_cam_rotate_left"):
			yaw += ROTATE_SPEED * Settings.camera_speed * delta
		if Input.is_action_pressed("tm_cam_rotate_right"):
			yaw -= ROTATE_SPEED * Settings.camera_speed * delta
	distance = lerpf(distance, _target_distance, minf(1.0, delta * 10.0))
	position = position.lerp(target_position, minf(1.0, delta * 8.0))
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_target_distance = maxf(MIN_DISTANCE, _target_distance * 0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_target_distance = minf(MAX_DISTANCE, _target_distance * 1.1)
	elif event is InputEventMouseMotion:
		if _rotating:
			yaw -= event.relative.x * DRAG_ROTATE
			pitch = clampf(pitch - event.relative.y * DRAG_ROTATE, MIN_PITCH, MAX_PITCH)
		if _panning:
			var k := distance * 0.0015
			target_position += (-_right() * event.relative.x + _forward() * event.relative.y) * k


func _apply_transform() -> void:
	rotation = Vector3(0, yaw, 0)
	_pivot.rotation = Vector3(pitch, 0, 0)
	camera.position = Vector3(0, 0, distance)
