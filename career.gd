extends Node3D

const CARS := ["Comet GT", "Rally XR", "Roadster RS"]
const CAR_COLORS := [
	Color(0.2, 0.75, 0.68),
	Color(0.95, 0.48, 0.2),
	Color(0.42, 0.58, 0.95)
]
const CHECKPOINTS := [
	Vector3(0, 0.6, 15),
	Vector3(15, 0.6, 0),
	Vector3(0, 0.6, -15),
	Vector3(-15, 0.6, 0)
]
const CHECKPOINT_RADIUS := 5.0
const MAX_SPEED := 42.0
const BOOST_SPEED := 66.0
const REWARD := 500

var _car: Node3D
var _camera: Camera3D
var _speed_label: Label
var _score_label: Label
var _progress_label: Label
var _objective_label: Label
var _progress_bar: ProgressBar
var _boost_bar: ProgressBar
var _car_label: Label
var _speed := 0.0
var _boost := 100.0
var _score := 0
var _car_index := 0
var _checkpoint := 0
var _finished := false
var _camera_time := 0.0


func _ready() -> void:
	_build_world()
	_build_hud()


func _process(delta: float) -> void:
	if _car == null:
		return
	_camera_time += delta
	_drive(delta)
	_update_progress()
	_update_camera(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_1 or event.keycode == KEY_2 or event.keycode == KEY_3:
		_car_index = clampi(event.keycode - KEY_1, 0, CARS.size() - 1)
		_rebuild_car()
	if event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://main.tscn")


func _drive(delta: float) -> void:
	var throttle := Input.get_axis("ui_down", "ui_up")
	var steering := Input.get_axis("ui_left", "ui_right")
	var boosting := Input.is_action_pressed("ui_accept") and _boost > 0.0 and throttle > 0.0
	var target_speed := throttle * (BOOST_SPEED if boosting else MAX_SPEED)
	_speed = move_toward(_speed, target_speed, (32.0 if boosting else 18.0) * delta)
	if absf(throttle) < 0.01:
		_speed = move_toward(_speed, 0.0, 10.0 * delta)
	_boost = maxf(0.0, _boost - 28.0 * delta) if boosting else minf(100.0, _boost + 9.0 * delta)
	_car.rotate_y(-steering * (0.9 + minf(absf(_speed) / MAX_SPEED, 1.0) * 1.2) * delta)
	_car.position += -_car.basis.z * _speed * delta
	_car.position.x = clampf(_car.position.x, -29.0, 29.0)
	_car.position.z = clampf(_car.position.z, -29.0, 29.0)
	_car.position.y = 0.5
	_car.rotation.z = lerpf(_car.rotation.z, -steering * 0.08, delta * 5.0)
	_score += int(absf(_speed) * delta * (1.4 if boosting else 0.8))


func _build_world() -> void:
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(70, 70)
	var ground := _mesh_instance(ground_mesh, _material(Color(0.1, 0.16, 0.17)))
	ground.position.y = -0.15
	add_child(ground)
	var road_material := _material(Color(0.075, 0.085, 0.1))
	_add_road(Vector3(0, 0, -11), Vector3(24, 0.12, 3), road_material)
	_add_road(Vector3(0, 0, 11), Vector3(24, 0.12, 3), road_material)
	_add_road(Vector3(-11, 0, 0), Vector3(3, 0.12, 24), road_material)
	_add_road(Vector3(11, 0, 0), Vector3(3, 0.12, 24), road_material)
	_build_checkpoint_gates()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 7, 12)
	_camera.current = true
	add_child(_camera)
	_car = Node3D.new()
	_car.position = CHECKPOINTS[0]
	add_child(_car)
	_build_car_model()


func _build_checkpoint_gates() -> void:
	for index in range(CHECKPOINTS.size()):
		var gate := Node3D.new()
		gate.position = CHECKPOINTS[index]
		add_child(gate)
		for side in [-2.2, 2.2]:
			var post := BoxMesh.new()
			post.size = Vector3(0.35, 3.6, 0.35)
			var post_instance := _mesh_instance(post, _material(Color(0.12, 0.9, 0.78)))
			post_instance.position = Vector3(side, 1.8, 0)
			gate.add_child(post_instance)
		var beam := BoxMesh.new()
		beam.size = Vector3(4.4, 0.35, 0.35)
		var beam_instance := _mesh_instance(beam, _material(Color(0.12, 0.9, 0.78)))
		beam_instance.position.y = 3.6
		gate.add_child(beam_instance)
		var label := Label3D.new()
		label.text = "CHECKPOINT %02d" % (index + 1)
		label.position = Vector3(0, 4.15, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 24
		gate.add_child(label)


func _build_car_model() -> void:
	for child in _car.get_children():
		child.queue_free()
	var color: Color = CAR_COLORS[_car_index]
	var body_size := Vector3(1.6, 0.55, 2.8)
	if _car_index == 1:
		body_size = Vector3(1.75, 0.7, 2.55)
	elif _car_index == 2:
		body_size = Vector3(1.9, 0.45, 2.4)
	var body := BoxMesh.new()
	body.size = body_size
	_car.add_child(_mesh_instance(body, _material(color)))
	var cabin := BoxMesh.new()
	cabin.size = Vector3(body_size.x * 0.62, 0.5, body_size.z * 0.38)
	var cabin_instance := _mesh_instance(cabin, _material(color.lightened(0.2)))
	cabin_instance.position = Vector3(0, body_size.y * 0.75, -0.05)
	_car.add_child(cabin_instance)
	if _car_index == 1:
		var spoiler := BoxMesh.new()
		spoiler.size = Vector3(2.0, 0.12, 0.35)
		var spoiler_instance := _mesh_instance(spoiler, _material(Color(0.05, 0.06, 0.07)))
		spoiler_instance.position = Vector3(0, 0.7, 1.0)
		_car.add_child(spoiler_instance)
	for side in [-1.0, 1.0]:
		for axle in [-0.85, 0.85]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.28
			wheel.bottom_radius = 0.28
			wheel.height = 0.18
			var wheel_instance := _mesh_instance(wheel, _material(Color(0.025, 0.03, 0.035)))
			wheel_instance.rotation_degrees = Vector3(0, 0, 90)
			wheel_instance.position = Vector3(side * (body_size.x * 0.52), -0.2, axle)
			_car.add_child(wheel_instance)
	var label := Label3D.new()
	label.text = "YOU"
	label.position = Vector3(0, 1.35, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30
	_car.add_child(label)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(650, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.08, 0.95)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := Label.new()
	title.text = "CAREER  /  THE MIDNIGHT DOCKS"
	title.add_theme_font_size_override("font_size", 23)
	content.add_child(title)
	_objective_label = Label.new()
	_objective_label.text = "Your car was impounded. Win this underground sprint to start the climb toward your rival."
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	content.add_child(_objective_label)
	_car_label = Label.new()
	content.add_child(_car_label)
	var controls := Label.new()
	controls.text = "ARROWS DRIVE  /  SPACE BOOST  /  1-3 CHANGE CAR  /  ESC EXIT"
	controls.add_theme_color_override("font_color", Color(0.25, 0.78, 0.72))
	content.add_child(controls)
	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 30)
	content.add_child(_speed_label)
	_score_label = Label.new()
	content.add_child(_score_label)
	_boost_bar = ProgressBar.new()
	_boost_bar.max_value = 100.0
	_boost_bar.show_percentage = false
	content.add_child(_boost_bar)
	_progress_label = Label.new()
	content.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.max_value = 100.0
	_progress_bar.show_percentage = false
	content.add_child(_progress_bar)


func _update_progress() -> void:
	if _finished:
		return
	if _car.position.distance_to(CHECKPOINTS[_checkpoint]) <= CHECKPOINT_RADIUS:
		_checkpoint += 1
		_score += 250
		if _checkpoint >= CHECKPOINTS.size():
			_finished = true
			_speed = 0.0
			_score += REWARD
			_objective_label.text = "CLEAN WIN  /  +%d CREDITS  /  The revenge climb begins." % REWARD


func _update_camera(delta: float) -> void:
	var target := _car.global_position + Vector3.UP * 5.5 + _car.basis.z * 9.0
	_camera.global_position = _camera.global_position.lerp(target, minf(delta * 6.0, 1.0))
	_camera.look_at(_car.global_position + Vector3.UP * 0.5 - _car.basis.z * 8.0, Vector3.UP)
	_camera.fov = lerpf(_camera.fov, 68.0 + minf(absf(_speed) * 0.22, 14.0), delta * 4.0)


func _update_hud() -> void:
	_speed_label.text = "%03d KM/H" % int(absf(_speed) * 3.6)
	_score_label.text = "SCORE  %07d" % _score
	_car_label.text = "CAR  /  %s" % CARS[_car_index]
	_boost_bar.value = _boost
	_progress_label.text = "CHECKPOINT %d/%d" % [min(_checkpoint, CHECKPOINTS.size()), CHECKPOINTS.size()]
	_progress_bar.value = (float(_checkpoint) / float(CHECKPOINTS.size())) * 100.0


func _rebuild_car() -> void:
	_build_car_model()
	_car_label.text = "CAR  /  %s" % CARS[_car_index]


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
