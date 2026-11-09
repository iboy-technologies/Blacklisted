extends Node

signal state_changed(state: Dictionary)
signal status_changed(message: String)

const MAX_PLAYERS := 8
const CARS := ["Comet", "Rally", "Roadster"]
const MAPS := ["Harbor Circuit", "Dust Valley", "Neon Loop"]

var _peer: ENetMultiplayerPeer
var _hosting := false
var _player_name := "Driver"
var _state: Dictionary = {
	"phase": "lobby",
	"car": 0,
	"map": 0,
	"players": {}
}


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func is_host() -> bool:
	return _hosting


func get_state() -> Dictionary:
	return _state.duplicate(true)


func host_session(player_name: String, port: int) -> String:
	var clean_player_name := _clean_name(player_name)
	if port < 1 or port > 65535:
		return "Port must be between 1 and 65535."
	_close_peer()
	var new_peer := ENetMultiplayerPeer.new()
	var error := new_peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return "Could not host on port %d (error %d)." % [port, error]
	_peer = new_peer
	multiplayer.multiplayer_peer = _peer
	_hosting = true
	_player_name = name
	_state = {
		"phase": "lobby",
		"car": 0,
		"map": 0,
		"players": {1: clean_player_name}
	}
	_player_name = clean_player_name
	status_changed.emit("Hosting on port %d." % port)
	state_changed.emit(get_state())
	return ""


func join_session(player_name: String, address: String, port: int) -> String:
	if address.strip_edges().is_empty():
		return "Enter the host address."
	if port < 1 or port > 65535:
		return "Port must be between 1 and 65535."
	_close_peer()
	_hosting = false
	_player_name = _clean_name(player_name)
	var new_peer := ENetMultiplayerPeer.new()
	var error := new_peer.create_client(address.strip_edges(), port)
	if error != OK:
		return "Could not connect to %s:%d (error %d)." % [address, port, error]
	_peer = new_peer
	multiplayer.multiplayer_peer = _peer
	_state = {
		"phase": "lobby",
		"car": 0,
		"map": 0,
		"players": {}
	}
	status_changed.emit("Connecting to %s:%d..." % [address.strip_edges(), port])
	state_changed.emit(get_state())
	return ""


func set_shared_selection(category: String, index: int) -> void:
	if _hosting:
		_apply_selection(category, index)


func start_match() -> void:
	if not _hosting or _state.get("phase", "lobby") != "lobby":
		return
	_state["phase"] = "match"
	_publish_state()


func return_to_lobby() -> void:
	if not _hosting or _state.get("phase", "lobby") != "match":
		return
	_state["phase"] = "lobby"
	_publish_state()


@rpc("any_peer", "call_remote", "reliable")
func request_join(player_name: String) -> void:
	if not _hosting:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1:
		return
	if _state.get("phase", "lobby") != "lobby":
		reject_join.rpc_id(sender_id, "The host is already in a race.")
		return
	if _state["players"].size() >= MAX_PLAYERS:
		reject_join.rpc_id(sender_id, "The lobby is full.")
		return
	_state["players"][sender_id] = _clean_name(player_name)
	_publish_state()


@rpc("authority", "call_remote", "reliable")
func reject_join(reason: String) -> void:
	_close_peer()
	status_changed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func receive_state(new_state: Dictionary) -> void:
	_state = new_state.duplicate(true)
	state_changed.emit(get_state())


func _apply_selection(category: String, index: int) -> void:
	if _state.get("phase", "lobby") != "lobby":
		return
	if category == "car" and index >= 0 and index < CARS.size():
		_state["car"] = index
	elif category == "map" and index >= 0 and index < MAPS.size():
		_state["map"] = index
	else:
		return
	_publish_state()


func _publish_state() -> void:
	state_changed.emit(get_state())
	receive_state.rpc(get_state())


func _on_connected_to_server() -> void:
	status_changed.emit("Connected. Waiting for the host lobby...")
	request_join.rpc_id(1, _player_name)


func _on_connection_failed() -> void:
	_close_peer()
	_hosting = false
	status_changed.emit("Connection failed. Check the address and port.")


func _on_server_disconnected() -> void:
	_close_peer()
	_hosting = false
	_state = {"phase": "lobby", "car": 0, "map": 0, "players": {}}
	status_changed.emit("The host disconnected.")
	state_changed.emit(get_state())


func _on_peer_disconnected(peer_id: int) -> void:
	if not _hosting or not _state["players"].has(peer_id):
		return
	_state["players"].erase(peer_id)
	_publish_state()


func _close_peer() -> void:
	_hosting = false
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _clean_name(value: String) -> String:
	var clean := value.strip_edges().left(16)
	return clean if not clean.is_empty() else "Driver"
