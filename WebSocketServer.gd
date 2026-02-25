extends Mod_Base
class_name WebSocketServer

var ws_server = TCPServer.new()
var ws_clients: Array[WebSocketPeer] = []
var websocket_server_port: int = 8080

func _ready():
	add_tracked_setting("websocket_server_port", "Modifies the WebSocket RPC server port")
	update_settings_ui()

func _process(_delta: float):
	if ws_server.is_connection_available():
		var tcp_conn = ws_server.take_connection()
		var ws_conn = WebSocketPeer.new()

		ws_conn.accept_stream(tcp_conn)
		ws_clients.append(ws_conn)
		print("New client connected.")

	for conn_idx in range(ws_clients.size() - 1, -1, -1):
		var conn = ws_clients[conn_idx]
		conn.poll()

		var state = conn.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while conn.get_available_packet_count() > 0:
				var packet = conn.get_packet()
				var message = packet.get_string_from_utf8()
				print("Received raw JSON from: ", message)

				var data = JSON.parse_string(message)
				if data is Dictionary:
					_on_ws_callback(data)
					conn.send_text("OK")
				else:
					print("Unrecognized message from WS!")
					conn.send_text("NOT OK")
		elif state == WebSocketPeer.STATE_CLOSED:
			ws_clients.remove_at(conn_idx)
			print("Client disconnected.")

func _find_mod_from_mods(mods: Node, target_name: String) -> Mod_Base:
	print("Looking for ", target_name, " in mods")
	for mod in mods.get_children():
		if mod is not Mod_Base:
			continue

		var mod_name = mod.get_name()
		if mod_name != target_name:
			continue

		return mod
	print("Did not find " + target_name + " mod")
	return null

func _on_ws_callback(data: Dictionary):
	var command_name = data.get("command_name")
	var args = data.get("args")

	if command_name == null:
		print("command_name is empty")
		return

	if args == null:
		print("args is empty")
		return

	print("Received command '", command_name, "'")

	match command_name:
		"toggle_mod":
			var target_name = args.get("name")
			var mods: Node = get_app().get_node("Mods")
			var mod = _find_mod_from_mods(mods, target_name)
			if mod == null:
				return

			_toggle_mod(mods, mod, mod.get_index())

		"enable_mod":
			var target_name = args.get("name")
			var mods: Node = get_app().get_node("Mods")
			var mod = _find_mod_from_mods(mods, target_name)
			if mod == null:
				return

			var is_disabled: bool = mod.get_script().resource_path.contains("DisabledMod")
			if is_disabled:
				_enable_mod(mods, mod, mod.get_index())

		"disable_mod":
			var target_name = args.get("name")
			var mods: Node = get_app().get_node("Mods")
			var mod = _find_mod_from_mods(mods, target_name)
			if mod == null:
				return

			var is_disabled: bool = mod.get_script().resource_path.contains("DisabledMod")
			if not is_disabled:
				_disable_mod(mods, mod, mod.get_index())

func load_after(_settings_old : Dictionary, _settings_new : Dictionary):
	reconnect_server()

func reconnect_server():
	ws_server.stop()
	ws_server.listen(websocket_server_port)

func _enable_mod(mods: Node, mod: Mod_Base, index: int):
	# copied and pasted from ModsWindow.gd
	# This mod is already disabled. Re-enable it.

	# Re-create the mod instance.
	var loaded_mod = load(mod.saved_settings["scene_path"]).instantiate()
	loaded_mod.name = mod.get_name()

	# Remove the placeholder (but don't free it yet) so the names don't
	# collide.
	mods.remove_child(mod)

	# Add the new one to the scene and initialize it with the settings.
	mods.add_child(loaded_mod)
	mods.move_child(loaded_mod, index)
	loaded_mod.load_settings(mod.saved_settings["settings"])
	loaded_mod.update_settings_ui()
	loaded_mod.scene_init()

	# Free the old placeholder.
	mod.queue_free()

func _disable_mod(mods: Node, mod: Mod_Base, index: int):
	# copied and pasted from ModsWindow.gd
	var saved_settings: Dictionary = {}

	saved_settings["scene_path"] = mod.scene_file_path
	saved_settings["name"] = mod.get_name()
	saved_settings["settings"] = mod.save_settings()

	var placeholder: DisabledMod = load("res://Mods/DisabledMod/DisabledMod.tscn").instantiate()
	placeholder.name = saved_settings["name"]
	placeholder.saved_settings = saved_settings

	# Clear out the mod we just disabled. Do this first so the name doesn't
	# get clobbered with the placeholder mod.
	mod.scene_shutdown()
	mods.remove_child(mod)
	mod.queue_free()

	mods.add_child(placeholder)
	mods.move_child(placeholder, index)

func _toggle_mod(mods: Node, mod: Mod_Base, index: int):
	var is_disabled: bool = mod.get_script().resource_path.contains("DisabledMod")

	if is_disabled:
		_enable_mod(mods, mod, index)
	else:
		_disable_mod(mods, mod, index)
