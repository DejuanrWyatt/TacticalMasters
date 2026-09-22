extends Node
## Online play over ENet (UDP). The host plays Blue and is the authority:
##   - The client sends each command to the host as a request.
##   - The host checks it, applies it, and sends it back to the client.
##   - The host's own commands (including turn-clock timeouts) are applied
##     on the host, then sent to the client.
## So both sides apply the same commands in the same order, and the rules are
## deterministic, which keeps the two games identical.
##
## Connecting: the client says hello with its PROTOCOL_VERSION; the host
## refuses a different version, otherwise starts the game and sends its map
## and teams. The host also tries to open its port on the router (UPnP).
## During a game both sides can chat, and after it both can ask for a
## rematch, which restarts with the same settings without reconnecting.

signal status_changed(text: String)
signal game_started
## Host -> client: a command to apply (queued in `inbox`).
signal command_received
## Client -> host: a command the client wants to play (queued in `requests`).
signal request_received
## Host -> client: the host refused the client's last request.
signal request_rejected(reason: String)
signal opponent_left
signal chat_received(text: String)
## The opponent asked for a rematch (they're waiting for us).
signal rematch_requested

const DEFAULT_PORT := 7777
## Bump when the rules or the network messages change: players on different
## versions can't play each other (their games would drift apart).
const PROTOCOL_VERSION := 3
const MAX_CHAT_LENGTH := 120

var inbox: Array[Dictionary] = []
var requests: Array[Dictionary] = []
var opponent_id := 0
## The version this build sends when joining (a variable so tests can fake an old build).
var protocol_version := PROTOCOL_VERSION
var _want_rematch := false
var _opponent_wants_rematch := false
var _upnp: UPNP
var _upnp_port := 0
var _upnp_task := -1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int, try_upnp := true) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	if try_upnp:
		_open_router_port(port)
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
	_want_rematch = false
	_opponent_wants_rematch = false
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_close_router_port()


func is_host() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server()


func is_online() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and opponent_id != 0


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


func send_chat(text: String) -> void:
	text = text.strip_edges().left(MAX_CHAT_LENGTH)
	if text != "" and opponent_id != 0:
		_receive_chat.rpc_id(opponent_id, text)


## Ask for a rematch; it starts once both players have asked.
func request_rematch() -> void:
	_want_rematch = true
	if opponent_id != 0:
		_receive_rematch.rpc_id(opponent_id)
	_maybe_start_rematch()


# --- Connecting ------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return  # clients say hello once connected (see _on_connected_to_server)
	if opponent_id != 0:
		return
	status_changed.emit("An opponent is connecting...")


func _on_connected_to_server() -> void:
	status_changed.emit("Connected! Checking versions...")
	_hello.rpc_id(1, protocol_version)


## Client -> host, right after connecting.
@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_refuse.rpc_id(id, "Version mismatch: the host runs version %d, you run %d. Both players need the same build." % [PROTOCOL_VERSION, version])
		status_changed.emit("Refused a player on a different version (%d)." % version)
		# Give the refusal time to arrive before dropping the connection.
		var drop := func() -> void:
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				multiplayer.multiplayer_peer.disconnect_peer(id)
		get_tree().create_timer(0.5).timeout.connect(drop)
		return
	opponent_id = id
	_start_as_host()


func _start_as_host() -> void:
	_want_rematch = false
	_opponent_wants_rematch = false
	GameConfig.start_online(0)
	_start_game.rpc_id(opponent_id, 1, {"map_id": GameConfig.map_id, "rosters": GameConfig.rosters})
	game_started.emit()


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	status_changed.emit(reason)
	close()


func _on_peer_disconnected(id: int) -> void:
	if id == opponent_id:
		opponent_left.emit()


func _on_connection_failed() -> void:
	close()
	status_changed.emit("Could not connect to the host.")


func _on_server_disconnected() -> void:
	opponent_left.emit()


@rpc("authority", "call_remote", "reliable")
func _start_game(team: int, settings: Dictionary) -> void:
	opponent_id = 1
	_want_rematch = false
	_opponent_wants_rematch = false
	GameConfig.start_online(team)
	# Play on the host's map with the host's chosen teams.
	GameConfig.map_id = settings.get("map_id", GameConfig.map_id)
	var rosters = settings.get("rosters")
	if rosters is Array and rosters.size() == 2:
		GameConfig.rosters = rosters
	game_started.emit()


# --- In game ---------------------------------------------------------------

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


@rpc("any_peer", "call_remote", "reliable")
func _receive_chat(text: String) -> void:
	if multiplayer.get_remote_sender_id() != opponent_id:
		return
	chat_received.emit(text.left(MAX_CHAT_LENGTH))


@rpc("any_peer", "call_remote", "reliable")
func _receive_rematch() -> void:
	if multiplayer.get_remote_sender_id() != opponent_id:
		return
	_opponent_wants_rematch = true
	rematch_requested.emit()
	_maybe_start_rematch()


## The host restarts once both players want a rematch (same map and teams).
func _maybe_start_rematch() -> void:
	if _want_rematch and _opponent_wants_rematch and is_host():
		_start_as_host()


# --- Router port (UPnP) ----------------------------------------------------

## Tries to forward the port on the router, in the background (discovery
## can take a few seconds), and reports the result and the public address.
func _open_router_port(port: int) -> void:
	status_changed.emit("Hosting on port %d. Trying to open the port on your router..." % port)
	var upnp := UPNP.new()
	var work := func() -> void:
		var result := upnp.discover(2000, 2)
		var message: String
		if result == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() != null and upnp.get_gateway().is_valid_gateway():
			var mapped := upnp.add_port_mapping(port, port, "Tactical Masters", "UDP")
			if mapped == UPNP.UPNP_RESULT_SUCCESS:
				message = "Router port %d opened automatically. Players on the internet can join at %s:%d." % [
					port, upnp.query_external_address(), port]
				_upnp = upnp
				_upnp_port = port
			else:
				message = "Couldn't open the router port automatically: forward UDP port %d manually (or use a VPN such as Tailscale)." % port
		else:
			message = "No UPnP router found: for internet play, forward UDP port %d manually (or use a VPN such as Tailscale)." % port
		call_deferred("_report_upnp", message)
	_upnp_task = WorkerThreadPool.add_task(work, false, "UPnP")


func _report_upnp(message: String) -> void:
	if _upnp_task != -1:
		WorkerThreadPool.wait_for_task_completion(_upnp_task)
		_upnp_task = -1
	if is_host():
		status_changed.emit(message)


func _close_router_port() -> void:
	if _upnp_task != -1:
		WorkerThreadPool.wait_for_task_completion(_upnp_task)
		_upnp_task = -1
	if _upnp != null and _upnp_port != 0:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	_upnp_port = 0


func _exit_tree() -> void:
	_close_router_port()
