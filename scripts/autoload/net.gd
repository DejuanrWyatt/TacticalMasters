extends Node
## Online play over ENet (UDP). The host plays Blue and is the authority:
##   - The client sends each command to the host as a request.
##   - The host checks it, applies it, and sends it back to the client.
##   - The host's own commands (including turn-clock timeouts) are applied
##     on the host, then sent to the client.
## So both sides apply the same commands in the same order, and the rules are
## deterministic, which keeps the two games identical.

signal status_changed(text: String)
signal game_started
## Host -> client: a command to apply (queued in `inbox`).
signal command_received
## Client -> host: a command the client wants to play (queued in `requests`).
signal request_received
## Host -> client: the host refused the client's last request.
signal request_rejected(reason: String)
signal opponent_left

const DEFAULT_PORT := 7777

var inbox: Array[Dictionary] = []
var requests: Array[Dictionary] = []
var opponent_id := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func join(address: String, port: int) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func close() -> void:
	opponent_id = 0
	inbox.clear()
	requests.clear()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_host() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server()


## Host: send an applied command to the client.
func broadcast(cmd: Dictionary) -> void:
	if opponent_id != 0:
		_receive_command.rpc_id(opponent_id, cmd)


## Client: ask the host to play a command.
func send_request(cmd: Dictionary) -> void:
	_receive_request.rpc_id(1, cmd)


## Host: tell the client its request was refused.
func reject(reason: String) -> void:
	if opponent_id != 0:
		_receive_reject.rpc_id(opponent_id, reason)


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return  # clients wait for the host's _start_game
	opponent_id = id
	GameConfig.start_online(0)
	_start_game.rpc_id(id, 1)
	game_started.emit()


func _on_peer_disconnected(id: int) -> void:
	if id == opponent_id:
		opponent_left.emit()


func _on_connected_to_server() -> void:
	status_changed.emit("Connected! Waiting for the host to start...")


func _on_connection_failed() -> void:
	close()
	status_changed.emit("Could not connect to the host.")


func _on_server_disconnected() -> void:
	opponent_left.emit()


@rpc("authority", "call_remote", "reliable")
func _start_game(team: int) -> void:
	opponent_id = 1
	GameConfig.start_online(team)
	game_started.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_command(cmd: Dictionary) -> void:
	inbox.append(cmd)
	command_received.emit()


@rpc("any_peer", "call_remote", "reliable")
func _receive_request(cmd: Dictionary) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != opponent_id:
		return
	requests.append(cmd)
	request_received.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_reject(reason: String) -> void:
	request_rejected.emit(reason)
