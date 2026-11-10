extends Control

const MATCH_SCENE := preload("res://match.tscn")
const CAREER_SCENE := preload("res://career.tscn")
const AIRCRAFT_SCENE := preload("res://aircraft.tscn")
const PANEL_COLOR := Color(0.055, 0.075, 0.105, 0.94)
const ACCENT := Color(0.25, 0.78, 0.72)
const TEXT_COLOR := Color(0.9, 0.94, 0.97)

var _name_input: LineEdit
var _address_input: LineEdit
var _port_input: LineEdit
var _status_label: Label
var _roster: VBoxContainer
var _car_picker: OptionButton
var _map_picker: OptionButton
var _weapon_picker: OptionButton
var _start_button: Button


func _ready() -> void:
	_build_ui()
	LobbySession.state_changed.connect(_refresh_lobby)
	LobbySession.status_changed.connect(_show_status)
	_refresh_lobby(LobbySession.get_state())


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.025, 0.035, 0.055)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 20)
	margin.add_child(page)

	var title := Label.new()
	title.text = "BLACKLISTED"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	page.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "MULTIPLAYER RACING  /  HOST A LOBBY OR JOIN A FRIEND"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", ACCENT)
	page.add_child(subtitle)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	page.add_child(columns)
	columns.add_child(_build_connection_panel())
	columns.add_child(_build_lobby_panel())

	_status_label = Label.new()
	_status_label.text = "Not connected."
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.77, 0.82))
	page.add_child(_status_label)


func _build_connection_panel() -> Control:
	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := _panel_content(panel)
	_add_heading(content, "Connection", "Create a host lobby or connect to one.")
	_name_input = _line_input(content, "Driver name", "Driver")
	_address_input = _line_input(content, "Host address", "127.0.0.1")
	_port_input = _line_input(content, "Port", "8910")
	var host_button := _button("HOST LOBBY")
	host_button.pressed.connect(_on_host_pressed)
	content.add_child(host_button)
	var join_button := _button("JOIN LOBBY")
	join_button.pressed.connect(_on_join_pressed)
	content.add_child(join_button)
	var career_button := _button("CAREER MODE")
	career_button.pressed.connect(func(): get_tree().change_scene_to_packed(CAREER_SCENE))
	content.add_child(career_button)
	var aircraft_button := _button("AIRCRAFT ARCADE")
	aircraft_button.pressed.connect(func(): get_tree().change_scene_to_packed(AIRCRAFT_SCENE))
	content.add_child(aircraft_button)
	var note := Label.new()
	note.text = "Share your address and port with players on your network."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.65, 0.72, 0.78))
	content.add_child(note)
	return panel


func _build_lobby_panel() -> Control:
	var panel := _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := _panel_content(panel)
	_add_heading(content, "Lobby", "Host chooses the shared car and circuit.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	_build_picker_column(row, "CAR", LobbySession.CARS, true)
	_build_picker_column(row, "MAP", LobbySession.MAPS, false)
	_build_picker_column(content, "WEAPON", LobbySession.WEAPONS, false, true)

	var roster_title := Label.new()
	roster_title.text = "DRIVERS"
	roster_title.add_theme_color_override("font_color", ACCENT)
	roster_title.add_theme_font_size_override("font_size", 13)
	content.add_child(roster_title)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 8)
	content.add_child(_roster)
	_start_button = _button("START RACE")
	_start_button.pressed.connect(LobbySession.start_match)
	content.add_child(_start_button)
	return panel


func _build_picker_column(parent: Control, label_text: String, options: Array, is_car: bool, is_weapon: bool = false) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.68, 0.77, 0.82))
	column.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in options:
		picker.add_item(option)
	if is_car:
		_car_picker = picker
		picker.item_selected.connect(func(index: int): LobbySession.set_shared_selection("car", index))
	elif is_weapon:
		_weapon_picker = picker
		picker.item_selected.connect(func(index: int): LobbySession.set_shared_selection("weapon", index))
	else:
		_map_picker = picker
		picker.item_selected.connect(func(index: int): LobbySession.set_shared_selection("map", index))
	column.add_child(picker)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(14)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _panel_content(panel: PanelContainer) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	return content


func _add_heading(parent: VBoxContainer, title: String, caption: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(label)
	var detail := Label.new()
	detail.text = caption
	detail.add_theme_color_override("font_color", Color(0.68, 0.75, 0.8))
	parent.add_child(detail)


func _line_input(parent: VBoxContainer, hint: String, initial_value: String) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = hint
	input.text = initial_value
	input.custom_minimum_size.y = 42
	parent.add_child(input)
	return input


func _button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_color_override("font_color", TEXT_COLOR)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.16, 0.2)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.13, 0.27, 0.3)
	hover.set_corner_radius_all(8)
	button.add_theme_stylebox_override("hover", hover)
	return button


func _on_host_pressed() -> void:
	var result := LobbySession.host_session(_name_input.text, _read_port())
	if not result.is_empty():
		_show_status(result)


func _on_join_pressed() -> void:
	var result := LobbySession.join_session(_name_input.text, _address_input.text, _read_port())
	if not result.is_empty():
		_show_status(result)


func _read_port() -> int:
	if not _port_input.text.is_valid_int():
		_show_status("Enter a valid port number.")
		return 0
	return int(_port_input.text)


func _show_status(message: String) -> void:
	_status_label.text = message


func _refresh_lobby(state: Dictionary) -> void:
	if state.get("phase", "lobby") == "match":
		get_tree().change_scene_to_packed(MATCH_SCENE)
		return
	if _roster == null:
		return
	_car_picker.select(clampi(int(state.get("car", 0)), 0, LobbySession.CARS.size() - 1))
	_map_picker.select(clampi(int(state.get("map", 0)), 0, LobbySession.MAPS.size() - 1))
	_weapon_picker.select(clampi(int(state.get("weapon", 0)), 0, LobbySession.WEAPONS.size() - 1))
	_car_picker.disabled = not LobbySession.is_host()
	_map_picker.disabled = not LobbySession.is_host()
	_weapon_picker.disabled = not LobbySession.is_host()
	_start_button.disabled = not LobbySession.is_host()
	for child in _roster.get_children():
		child.queue_free()
	var players: Dictionary = state.get("players", {})
	var peer_ids: Array = players.keys()
	peer_ids.sort()
	if peer_ids.is_empty():
		_add_roster_label("No drivers connected yet.")
	else:
		for peer_id in peer_ids:
			var suffix := " (HOST)" if int(peer_id) == 1 else ""
			_add_roster_label("%s%s" % [str(players[peer_id]), suffix])


func _add_roster_label(caption: String) -> void:
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", TEXT_COLOR)
	_roster.add_child(label)
