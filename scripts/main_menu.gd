extends Control
## Title screen: pick vs computer, same-device, or online play.

const BATTLE_SCENE := "res://scenes/battle.tscn"
const UnitGuide = preload("res://scripts/ui/unit_guide.gd")
const OptionsMenu = preload("res://scripts/ui/options_menu.gd")

var address_edit: LineEdit
var port_edit: LineEdit
var status_label: Label
var guide: Control
var options: Control


func _ready() -> void:
	Net.status_changed.connect(_set_status)
	Net.game_started.connect(_on_game_started)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.15, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 380
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "TACTICAL MASTERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Turn-based tactics on a 3D battlefield"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())
	_add_button(box, "Play vs Computer", _start_local.bind("ai"))
	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 10)
	box.add_child(difficulty_row)
	var difficulty_label := Label.new()
	difficulty_label.text = "Computer difficulty:"
	difficulty_row.add_child(difficulty_label)
	var difficulty := OptionButton.new()
	difficulty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for level in ["easy", "medium", "hard"]:
		difficulty.add_item(level.capitalize())
	difficulty.select(["easy", "medium", "hard"].find(GameConfig.ai_difficulty))
	difficulty.item_selected.connect(func(i): GameConfig.ai_difficulty = ["easy", "medium", "hard"][i])
	difficulty_row.add_child(difficulty)
	_add_button(box, "Two Players (Same Device)", _start_local.bind("hotseat"))
	_add_button(box, "Unit Guide", _open_guide)
	_add_button(box, "Options", _open_options)

	box.add_child(HSeparator.new())
	var online := Label.new()
	online.text = "Online"
	online.add_theme_font_size_override("font_size", 22)
	box.add_child(online)

	address_edit = LineEdit.new()
	address_edit.placeholder_text = "Host address to join (e.g. 192.168.1.20)"
	box.add_child(address_edit)

	port_edit = LineEdit.new()
	port_edit.placeholder_text = "Port"
	port_edit.text = str(Net.DEFAULT_PORT)
	box.add_child(port_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var host_button := _add_button(row, "Host Game", _host)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var join_button := _add_button(row, "Join Game", _join)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(status_label)

	if not OS.has_feature("web") and not OS.has_feature("ios"):
		box.add_child(HSeparator.new())
		_add_button(box, "Quit", get_tree().quit)


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _open_guide() -> void:
	if guide == null:
		guide = UnitGuide.new()
		add_child(guide)
	guide.visible = true


func _open_options() -> void:
	if options == null:
		options = OptionsMenu.new()
		add_child(options)
	options.visible = true


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
	_set_status("Hosting on port %d. Waiting for an opponent...\nYour address: %s" % [
		port, ", ".join(PackedStringArray(addresses)) if not addresses.is_empty() else "unknown"])


func _join() -> void:
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
	status_label.text = text


func _on_game_started() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)
