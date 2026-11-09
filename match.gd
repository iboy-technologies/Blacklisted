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


func _ready() -> void:
	_build_world()
	_build_hud()
	LobbySession.state_changed.connect(_on_state_changed)


func _exit_tree() -> void:
	if LobbySession.state_changed.is_connected(_on_state_changed):
		LobbySession.state_changed.disconnect(_on_state_changed)


func _build_world() -> void:
	var state := LobbySession.get_state()
	var map_index := clampi(int(state.get("map", 0)), 0, LobbySession.MAPS.size() - 1)
	var car_index := clampi(int(state.get("car", 0)), 0, LobbySession.CARS.size() - 1)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(70, 70)
	var ground := _mesh_instance(ground_mesh, _material(MAP_COLORS[map_index]))
	ground.position.y = -0.15
	add_child(ground)

	var road_material := _material(Color(0.075, 0.085, 0.1))
	_add_road(Vector3(0, 0, -11), Vector3(24, 0.12, 3), road_material)
	_add_road(Vector3(0, 0, 11), Vector3(24, 0.12, 3), road_material)
	_add_road(Vector3(-11, 0, 0), Vector3(3, 0.12, 24), road_material)
	_add_road(Vector3(11, 0, 0), Vector3(3, 0.12, 24), road_material)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(23, 26, 29)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	add_child(camera)

	var players: Dictionary = state.get("players", {})
	var peer_ids: Array = players.keys()
	peer_ids.sort()
	if peer_ids.is_empty():
		peer_ids.append(1)
	for index in range(peer_ids.size()):
		var angle := TAU * float(index) / float(maxi(peer_ids.size(), 1))
		var position := Vector3(cos(angle) * 8.5, 0.55, sin(angle) * 8.5)
		var player_name := str(players.get(peer_ids[index], "Driver"))
		_add_car(position, player_name, car_index, index)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(370, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.08, 0.94)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var state := LobbySession.get_state()
	var map_index := clampi(int(state.get("map", 0)), 0, LobbySession.MAPS.size() - 1)
	var car_index := clampi(int(state.get("car", 0)), 0, LobbySession.CARS.size() - 1)
	var title := Label.new()
	title.text = LobbySession.MAPS[map_index]
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.9, 0.94, 0.97))
	content.add_child(title)
	var details := Label.new()
	details.text = "Shared car: %s  /  %d drivers" % [LobbySession.CARS[car_index], state.get("players", {}).size()]
	details.add_theme_color_override("font_color", Color(0.25, 0.78, 0.72))
	content.add_child(details)
	var note := Label.new()
	note.text = "Prototype match scene — multiplayer lobby selections are active."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.7, 0.77, 0.82))
	content.add_child(note)
	if LobbySession.is_host():
		var back_button := Button.new()
		back_button.text = "RETURN TO LOBBY"
		back_button.pressed.connect(LobbySession.return_to_lobby)
		content.add_child(back_button)
	else:
		var waiting := Label.new()
		waiting.text = "The host controls the lobby."
		content.add_child(waiting)


func _add_car(position: Vector3, player_name: String, car_index: int, variation: int) -> void:
	var color := CAR_COLORS[(car_index + variation) % CAR_COLORS.size()]
	var body := BoxMesh.new()
	body.size = Vector3(1.5, 0.65, 2.4)
	var car := _mesh_instance(body, _material(color))
	car.position = position
	add_child(car)
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.05, 0.5, 1.1)
	var top := _mesh_instance(cabin, _material(color.lightened(0.2)))
	top.position = position + Vector3(0, 0.55, 0)
	add_child(top)
	var label := Label3D.new()
	label.text = player_name
	label.position = position + Vector3(0, 1.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	add_child(label)


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
