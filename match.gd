extends Node3D

const MAP_COLORS := [
	Color(0.12, 0.3, 0.34),
	Color(0.36, 0.27, 0.16),
	Color(0.19, 0.15, 0.34)
]
const CAR_COLORS := [
	Color(0.2, 0.75, 0.68),
	Color(0.95, 0.48, 0.2),
	Color(0.42, 0.58, 0.95)
]
const MAX_SPEED := 42.0
const BOOST_SPEED := 66.0

var _local_car: Node3D
var _camera: Camera3D
var _speed_label: Label
var _score_label: Label
var _boost_bar: ProgressBar
var _camera_label: Label
var _speed := 0.0
var _score := 0
var _boost := 100.0
var _camera_mode := 0
var _camera_time := 0.0
var _map_index := 0
var _car_index := 0


func _ready() -> void:
	var state := LobbySession.get_state()
	_map_index = clampi(int(state.get("map", 0)), 0, LobbySession.MAPS.size() - 1)
	_car_index = clampi(int(state.get("car", 0)), 0, LobbySession.CARS.size() - 1)
	_build_world()
	_build_hud()
	LobbySession.state_changed.connect(_on_state_changed)


func _exit_tree() -> void:
	if LobbySession.state_changed.is_connected(_on_state_changed):
		LobbySession.state_changed.disconnect(_on_state_changed)


func _process(delta: float) -> void:
	if _local_car == null:
		return
	_camera_time += delta
	_drive_local_car(delta)
	_update_camera(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		_camera_mode = (_camera_mode + 1) % 3
		_camera_label.text = _camera_mode_name()


func _drive_local_car(delta: float) -> void:
	var throttle := Input.get_axis("ui_down", "ui_up")
	var steering := Input.get_axis("ui_left", "ui_right")
	var boosting := Input.is_action_pressed("ui_accept") and _boost > 0.0 and throttle > 0.0
	var target_speed := throttle * (BOOST_SPEED if boosting else MAX_SPEED)
	_speed = move_toward(_speed, target_speed, (32.0 if boosting else 18.0) * delta)
	if absf(throttle) < 0.01:
		_speed = move_toward(_speed, 0.0, 10.0 * delta)
	if boosting:
		_boost = maxf(0.0, _boost - 28.0 * delta)
	else:
		_boost = minf(100.0, _boost + 9.0 * delta)
	var steering_strength := (0.9 + minf(absf(_speed) / MAX_SPEED, 1.0) * 1.2) * delta
	_local_car.rotate_y(-steering * steering_strength)
	_local_car.position += -_local_car.basis.z * _speed * delta
	_local_car.position.x = clampf(_local_car.position.x, -29.0, 29.0)
	_local_car.position.z = clampf(_local_car.position.z, -29.0, 29.0)
	_local_car.position.y = 0.5
	_local_car.rotation.x = lerpf(_local_car.rotation.x, steering * 0.06, delta * 5.0)
	_local_car.rotation.z = lerpf(_local_car.rotation.z, -steering * 0.08, delta * 5.0)
	_score += int(absf(_speed) * delta * (1.4 if boosting else 0.8))


func _update_camera(delta: float) -> void:
	var target_position: Vector3
	var look_target := _local_car.global_position + Vector3.UP * 0.5
	if _camera_mode == 1:
		target_position = _local_car.global_position + Vector3.UP * 1.0 - _local_car.basis.z * 0.5
		look_target += -_local_car.basis.z * 12.0
	elif _camera_mode == 2:
		var orbit := Vector3(cos(_camera_time * 0.55) * 13.0, 7.0, sin(_camera_time * 0.55) * 13.0)
		target_position = _local_car.global_position + orbit
	else:
		target_position = _local_car.global_position + Vector3.UP * 5.5 + _local_car.basis.z * 9.0
		look_target += -_local_car.basis.z * 8.0
	_camera.global_position = _camera.global_position.lerp(target_position, minf(delta * 6.0, 1.0))
	_camera.look_at(look_target, Vector3.UP)
	_camera.fov = lerpf(_camera.fov, 68.0 + minf(absf(_speed) * 0.22, 14.0), delta * 4.0)


func _build_world() -> void:
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(70, 70)
	var ground := _mesh_instance(ground_mesh, _material(MAP_COLORS[_map_index]))
	ground.position.y = -0.15
	add_child(ground)

	var road_material := _material(Color(0.075, 0.085, 0.1))
	_add_road(Vector3(0, 0, -11), Vector3(24, 0.12, 3), road_material)
	_add_road(Vector3(0, 0, 11), Vector3(24, 0.12, 3), road_material)
	_add_road(Vector3(-11, 0, 0), Vector3(3, 0.12, 24), road_material)
	_add_road(Vector3(11, 0, 0), Vector3(3, 0.12, 24), road_material)
	for marker in range(-3, 4):
		_add_road(Vector3(marker * 5.0, 0.08, 0), Vector3(1.6, 0.03, 0.25), _material(Color(0.95, 0.78, 0.25)))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 7, 12)
	_camera.current = true
	add_child(_camera)

	var players: Dictionary = LobbySession.get_state().get("players", {})
	var peer_ids: Array = players.keys()
	peer_ids.sort()
	if peer_ids.is_empty():
		peer_ids.append(1)
	for index in range(peer_ids.size()):
		var angle := TAU * float(index) / float(maxi(peer_ids.size(), 1))
		var position := Vector3(cos(angle) * 8.5, 0.5, sin(angle) * 8.5)
		var player_name := str(players.get(peer_ids[index], "Driver"))
		var car := _add_car(position, player_name, _car_index, index)
		if int(peer_ids[index]) == multiplayer.get_unique_id() or (not multiplayer.has_multiplayer_peer() and index == 0):
			_local_car = car


func _add_car(position: Vector3, player_name: String, car_index: int, variation: int) -> Node3D:
	var root := Node3D.new()
	root.position = position
	root.rotation.y = TAU * float(variation) / 8.0
	add_child(root)
	var color: Color = CAR_COLORS[(car_index + variation) % CAR_COLORS.size()]
	_build_car_model(root, car_index, color)
	var label := Label3D.new()
	label.text = player_name
	label.position = Vector3(0, 1.35, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	root.add_child(label)
	return root


func _build_car_model(parent: Node3D, car_index: int, color: Color) -> void:
	var body_size := Vector3(1.6, 0.55, 2.8)
	if car_index == 1:
		body_size = Vector3(1.75, 0.7, 2.55)
	elif car_index == 2:
		body_size = Vector3(1.9, 0.45, 2.4)
	var body := BoxMesh.new()
	body.size = body_size
	var body_instance := _mesh_instance(body, _material(color))
	parent.add_child(body_instance)

	var cabin := BoxMesh.new()
	cabin.size = Vector3(body_size.x * 0.62, 0.42 if car_index == 2 else 0.58, body_size.z * 0.38)
	var cabin_instance := _mesh_instance(cabin, _material(color.lightened(0.2)))
	cabin_instance.position = Vector3(0, body_size.y * 0.75, -0.05)
	parent.add_child(cabin_instance)

	if car_index == 1:
		var spoiler := BoxMesh.new()
		spoiler.size = Vector3(2.0, 0.12, 0.35)
		var spoiler_instance := _mesh_instance(spoiler, _material(Color(0.05, 0.06, 0.07)))
		spoiler_instance.position = Vector3(0, 0.7, 1.0)
		parent.add_child(spoiler_instance)
	elif car_index == 2:
		var nose := BoxMesh.new()
		nose.size = Vector3(1.4, 0.18, 0.6)
		var nose_instance := _mesh_instance(nose, _material(color.lightened(0.12)))
		nose_instance.position = Vector3(0, -0.05, -1.35)
		parent.add_child(nose_instance)

	for side in [-1.0, 1.0]:
		for axle in [-0.85, 0.85]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.28
			wheel.bottom_radius = 0.28
			wheel.height = 0.18
			var wheel_instance := _mesh_instance(wheel, _material(Color(0.025, 0.03, 0.035)))
			wheel_instance.rotation_degrees = Vector3(0, 0, 90)
			wheel_instance.position = Vector3(side * (body_size.x * 0.52), -0.2, axle)
			parent.add_child(wheel_instance)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 20
	top.offset_bottom = 150
	canvas.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := Label.new()
	title.text = LobbySession.MAPS[_map_index].to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 0.97))
	info.add_child(title)
	var hint := Label.new()
	hint.text = "ARROWS DRIVE  /  SPACE BOOST  /  C CAMERA"
	hint.add_theme_color_override("font_color", Color(0.25, 0.78, 0.72))
	info.add_child(hint)
	_camera_label = Label.new()
	_camera_label.text = _camera_mode_name()
	_camera_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(_camera_label)

	var metrics := VBoxContainer.new()
	metrics.custom_minimum_size.x = 250
	row.add_child(metrics)
	_speed_label = Label.new()
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.add_theme_font_size_override("font_size", 32)
	metrics.add_child(_speed_label)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	metrics.add_child(_score_label)
	_boost_bar = ProgressBar.new()
	_boost_bar.max_value = 100.0
	_boost_bar.show_percentage = false
	_boost_bar.custom_minimum_size.y = 12
	metrics.add_child(_boost_bar)


func _update_hud() -> void:
	if _speed_label == null:
		return
	_speed_label.text = "%03d KM/H" % int(absf(_speed) * 3.6)
	_score_label.text = "SCORE  %07d" % _score
	_boost_bar.value = _boost


func _camera_mode_name() -> String:
	return ["CHASE CAM", "HOOD CAM", "CINEMATIC ORBIT"][_camera_mode]


func _add_road(position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var road := _mesh_instance(mesh, material)
	road.position = position
	add_child(road)


func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _on_state_changed(state: Dictionary) -> void:
	if state.get("phase", "lobby") == "lobby":
		get_tree().change_scene_to_file("res://main.tscn")
