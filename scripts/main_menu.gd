extends Control
## Title screen: play vs the computer, two players on one device, or online;
## plus the Unit Guide and Options. Play modes go through Battle Setup first.

const BATTLE_SCENE := "res://scenes/battle.tscn"
const UnitGuide = preload("res://scripts/ui/unit_guide.gd")
const OptionsMenu = preload("res://scripts/ui/options_menu.gd")
const BattleSetup = preload("res://scripts/ui/battle_setup.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const HowToPlay = preload("res://scripts/ui/how_to_play.gd")

var address_edit: LineEdit
var port_edit: LineEdit
var status_label: Label
var guide: Control
var options: Control
var setup: Control
var how_to: Control
## While hosting: the host's address line, kept above network status messages.
var _host_info := ""


func _ready() -> void:
	theme = UiTheme.build()
	Net.status_changed.connect(_set_status)
	Net.game_started.connect(_on_game_started)
	_build_ui()
	# "-- autostart" on the command line jumps straight into a battle vs the computer.
	if OS.get_cmdline_user_args().has("autostart"):
		_start_local.call_deferred("ai")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 400
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "TACTICAL MASTERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Real-time tactics on a 3D battlefield"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", UiTheme.DIM)
	box.add_child(subtitle)
	box.add_child(_spacer(12))

	_add_button(box, "Play vs Computer", _open_setup.bind("ai"), true)
	_add_button(box, "Two Players (Same Device)", _open_setup.bind("hotseat"), true)
	var row_tools := HBoxContainer.new()
	row_tools.add_theme_constant_override("separation", 10)
	box.add_child(row_tools)
	_add_button(row_tools, "How to Play", _open_how_to).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button(row_tools, "Unit Guide", _open_guide).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button(row_tools, "Options", _open_options).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	box.add_child(_spacer(8))
	var online_panel := PanelContainer.new()
	box.add_child(online_panel)
	var online := VBoxContainer.new()
	online.add_theme_constant_override("separation", 8)
	online_panel.add_child(online)
	var online_title := Label.new()
	online_title.text = "Online"
	online_title.add_theme_font_size_override("font_size", 18)
	online_title.add_theme_color_override("font_color", UiTheme.GOLD)
	online.add_child(online_title)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 8)
	online.add_child(fields)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Host address to join"
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(address_edit)
	port_edit = LineEdit.new()
	port_edit.placeholder_text = "Port"
	port_edit.text = str(Net.DEFAULT_PORT)
	port_edit.custom_minimum_size.x = 80
	fields.add_child(port_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	online.add_child(row)
	_add_button(row, "Host Game", _open_setup.bind("host")).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button(row, "Join Game", _join).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", UiTheme.DIM)
	online.add_child(status_label)

	if not OS.has_feature("web") and not OS.has_feature("ios"):
		box.add_child(_spacer(4))
		_add_button(box, "Quit", get_tree().quit)


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


func _add_button(parent: Control, text: String, action: Callable, big := false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 52 if big else 42
	if big:
		button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _open_guide() -> void:
	if guide == null:
		guide = UnitGuide.new()
		add_child(guide)
	guide.visible = true


func _open_how_to() -> void:
	if how_to == null:
		how_to = HowToPlay.new()
		add_child(how_to)
	how_to.visible = true


func _open_options() -> void:
	if options == null:
		options = OptionsMenu.new()
		add_child(options)
	options.visible = true


## Battle Setup for a mode ("ai", "hotseat" or "host"); starts or hosts on confirm.
func _open_setup(mode: String) -> void:
	if setup != null:
		setup.queue_free()
	setup = BattleSetup.new()
	setup.setup_mode = mode
	add_child(setup)
	var on_confirm := func() -> void:
		setup.visible = false
		if mode == "host":
			_host()
		else:
			_start_local(mode)
	setup.confirmed.connect(on_confirm)


func _start_local(mode: String) -> void:
	Net.close()
	GameConfig.mode = mode
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _port() -> int:
	var port := port_edit.text.strip_edges().to_int()
	return port if port > 0 and port < 65536 else Net.DEFAULT_PORT


func _host() -> void:
	var port := _port()
	var err := Net.host(port)
	if err != OK:
		_set_status("Couldn't host on port %d (error %d)." % [port, err])
		return
	var addresses: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			addresses.append(ip)
	_host_info = "Hosting %s on port %d. Waiting for an opponent...\nOn your network: %s" % [
		GameConfig.build_map().name, port, ", ".join(PackedStringArray(addresses)) if not addresses.is_empty() else "unknown"]
	_set_status("Trying to open the port on your router...")


func _join() -> void:
	_host_info = ""
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		_set_status("Enter the host's address first.")
		return
	var err := Net.join(address, _port())
	if err != OK:
		_set_status("Couldn't start connecting (error %d)." % err)
		return
	_set_status("Connecting to %s..." % address)


func _set_status(text: String) -> void:
	status_label.text = _host_info + "\n" + text if _host_info != "" and Net.is_host() else text


func _on_game_started() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)
