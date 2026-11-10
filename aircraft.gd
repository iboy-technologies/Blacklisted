extends Node3D

const MAX_HEALTH := 100.0
const MAX_SPEED := 34.0
const MISSILE_COOLDOWN := 1.0

var _aircraft: Node3D
var _camera: Camera3D
var _speed := 12.0
var _health := MAX_HEALTH
var _missile_timer := 0.0
var _machine_gun_timer := 0.0
var _speed_label: Label
var _health_bar: ProgressBar
var _status_label: Label


func _ready() -> void:
	_build_world()
	_build_hud()


func _process(delta: float) -> void:
	_missile_timer = maxf(0.0, _missile_timer - delta)
	_machine_gun_timer = maxf(0.0, _machine_gun_timer - delta)
	_fly(delta)
	_update_camera(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_fire_machine_gun()
		elif event.keycode == KEY_G:
			_fire_missile()
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://main.tscn")


func _fly(delta: float) -> void:
	var pitch := Input.get_axis("ui_down", "ui_up")
	var roll := Input.get_axis("ui_left", "ui_right")
	var boost := Input.is_action_pressed("ui_accept")
	var target_speed := 48.0 if boost else MAX_SPEED
	_speed = move_toward(_speed, target_speed, 16.0 * delta)
	_aircraft.rotate_x(pitch * delta)
	_aircraft.rotate_z(-roll * delta)
	_aircraft.position += -_aircraft.basis.z * _speed * delta
	_aircraft.position.y = clampf(_aircraft.position.y, 3.0, 24.0)
	_aircraft.position.x = clampf(_aircraft.position.x, -32.0, 32.0)
	_aircraft.position.z = clampf(_aircraft.position.z, -32.0, 32.0)


func _fire_machine_gun() -> void:
	if _machine_gun_timer > 0.0:
		return
	_machine_gun_timer = 0.12
	_spawn_projectile(48.0, Color(1.0, 0.85, 0.2), 0.7)


func _fire_missile() -> void:
	if _missile_timer > 0.0:
		return
	_missile_timer = MISSILE_COOLDOWN
	_spawn_projectile(28.0, Color(1.0, 0.2, 0.08), 1.4)


func _spawn_projectile(speed: float, color: Color, lifetime: float) -> void:
	var projectile := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.14
	mesh.height = 0.28
	projectile.mesh = mesh
	projectile.material_override = _material(color)
	projectile.position = _aircraft.global_position - _aircraft.basis.z * 2.0
	add_child(projectile)
	var direction := -_aircraft.basis.z
	var tween := create_tween()
	tween.tween_property(projectile, "position", projectile.position + direction * speed, lifetime)
	tween.finished.connect(func(): if is_instance_valid(projectile): projectile.queue_free())


func _build_world() -> void:
	var ground := _mesh_instance(_plane(Vector2(80, 80)), _material(Color(0.035, 0.07, 0.12)))
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_aircraft = Node3D.new()
	_aircraft.position = Vector3(0, 8, 8)
	add_child(_aircraft)
	var body := BoxMesh.new()
	body.size = Vector3(2.2, 0.45, 3.8)
	_aircraft.add_child(_mesh_instance(body, _material(Color(0.55, 0.62, 0.72))))
	var wing := BoxMesh.new()
	wing.size = Vector3(8.0, 0.12, 0.8)
	_aircraft.add_child(_mesh_instance(wing, _material(Color(0.2, 0.27, 0.35))))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.25, 1.0, 0.75)
	var tail_instance := _mesh_instance(tail, _material(Color(0.32, 0.4, 0.52)))
	tail_instance.position = Vector3(0, 0.55, 1.3)
	_aircraft.add_child(tail_instance)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 4, 11)
	_camera.current = true
	add_child(_camera)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(450, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.95)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	var title := Label.new()
	title.text = "AIRCRAFT ARCADE  /  SKY RAID"
	title.add_theme_font_size_override("font_size", 23)
	content.add_child(title)
	_status_label = Label.new()
	_status_label.text = "ARROWS FLY  /  SPACE BOOST  /  F MACHINE GUN  /  G MISSILE"
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
	content.add_child(_status_label)
	_speed_label = Label.new()
	content.add_child(_speed_label)
	_health_bar = ProgressBar.new()
	_health_bar.max_value = MAX_HEALTH
	_health_bar.show_percentage = false
	content.add_child(_health_bar)


func _update_camera(delta: float) -> void:
	var target := _aircraft.global_position + Vector3.UP * 4.0 + _aircraft.basis.z * 10.0
	_camera.global_position = _camera.global_position.lerp(target, minf(delta * 5.0, 1.0))
	_camera.look_at(_aircraft.global_position, Vector3.UP)
	_camera.fov = lerpf(_camera.fov, 72.0 + _speed * 0.2, delta * 4.0)


func _update_hud() -> void:
	_speed_label.text = "AIR SPEED  %03d KM/H" % int(_speed * 3.6)
	_health_bar.value = _health


func _plane(size: Vector2) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = size
	return mesh


func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
