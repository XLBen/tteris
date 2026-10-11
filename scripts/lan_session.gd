extends Node
## Two players on one local network. Registered as the LanSession autoload.
##
## One machine hosts (it runs the battle), the other joins it by address. The
## link carries four things: the host's match settings while both sit in the
## lobby, the start of a match, the battle as the host sees it (a
## VersusBattle.snapshot() and the events since the last one, every frame),
## and the joining player's keys going the other way. Nothing here knows the
## rules of the game; scenes/menus/mode_select and scripts/versus.gd do the
## talking.

const PORT: int = 24642
const ROLE_NONE: StringName = &""
const ROLE_HOST: StringName = &"host"
const ROLE_CLIENT: StringName = &"client"
## Key messages of the joining player.
const INPUT_PRESS: int = 0
const INPUT_RELEASE: int = 1
const INPUT_TAP: int = 2

## The other player arrived (host) / the host was reached (client).
signal peer_joined
## The other player is gone, or the host could not be reached.
signal peer_left
signal settings_received(settings: Dictionary)
signal start_received(settings: Dictionary)
signal state_received(snapshot: Dictionary, events: Array)
signal input_received(action: StringName, kind: int)

var _role: StringName = ROLE_NONE
var _peer_id: int = 0


func role() -> StringName:
	return _role


## True while the other player is on the line.
func has_peer() -> bool:
	return _peer_id != 0


## Opens this machine for one other player.
func host(port: int = PORT) -> Error:
	close()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, 1)
	if error != OK:
		return error
	_adopt(peer, ROLE_HOST)
	return OK


## Reaches for the host at `address`. peer_joined or peer_left tells how it went.
func join(address: String, port: int = PORT) -> Error:
	close()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address.strip_edges(), port)
	if error != OK:
		return error
	_adopt(peer, ROLE_CLIENT)
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_role = ROLE_NONE
	_peer_id = 0


## The addresses another machine on the network can join this one by.
func local_addresses() -> Array[String]:
	var found: Array[String] = []
	for address: String in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			found.append(address)
	return found


func send_settings(settings: Dictionary) -> void:
	if _role == ROLE_HOST and has_peer():
		_settings.rpc_id(_peer_id, settings)


func send_start(settings: Dictionary) -> void:
	if _role == ROLE_HOST and has_peer():
		_start.rpc_id(_peer_id, settings)


func send_state(snapshot: Dictionary, events: Array) -> void:
	if _role == ROLE_HOST and has_peer():
		_state.rpc_id(_peer_id, snapshot, events)


func send_input(action: StringName, kind: int) -> void:
	if _role == ROLE_CLIENT and has_peer():
		_input_message.rpc_id(_peer_id, action, kind)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connection_failed.connect(_on_peer_gone.bind(0))
	multiplayer.server_disconnected.connect(_on_peer_gone.bind(0))


func _adopt(peer: ENetMultiplayerPeer, new_role: StringName) -> void:
	multiplayer.multiplayer_peer = peer
	_role = new_role


func _on_peer_connected(id: int) -> void:
	_peer_id = id
	peer_joined.emit()


func _on_peer_gone(_id: int) -> void:
	if _role == ROLE_NONE:
		return
	var had_role: StringName = _role
	_peer_id = 0
	if had_role == ROLE_CLIENT:
		# Nothing to go back to: the client's line is the host.
		close()
	peer_left.emit()


@rpc("authority", "call_remote", "reliable")
func _settings(settings: Dictionary) -> void:
	settings_received.emit(settings)


@rpc("authority", "call_remote", "reliable")
func _start(settings: Dictionary) -> void:
	start_received.emit(settings)


@rpc("authority", "call_remote", "reliable")
func _state(snapshot: Dictionary, events: Array) -> void:
	state_received.emit(snapshot, events)


@rpc("any_peer", "call_remote", "reliable")
func _input_message(action: StringName, kind: int) -> void:
	if _role == ROLE_HOST and multiplayer.get_remote_sender_id() == _peer_id:
		input_received.emit(action, kind)
