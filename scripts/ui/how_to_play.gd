extends Control
## How to Play: short illustrated pages explaining the rules. Opened from the
## main menu and the in-game menu. Key names follow the player's bindings.

signal closed

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const GameState = preload("res://scripts/core/game_state.gd")

var _pages: Array = []
var _text: RichTextLabel
var _nav: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build()
	_pages = _build_pages()

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Close (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(130, 44)
	close.pressed.connect(close_page)
	header.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 250
	nav.add_theme_constant_override("separation", 6)
	body.add_child(nav)
	var group := ButtonGroup.new()
	for i in _pages.size():
		var b := Button.new()
		b.text = _pages[i][0]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 42
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_show_page.bind(i))
		nav.add_child(b)
		_nav.append(b)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_font_size_override("bold_font_size", 16)
	panel.add_child(_text)
	_show_page(0)


func _show_page(i: int) -> void:
	for j in _nav.size():
		_nav[j].set_pressed_no_signal(j == i)
	_text.text = "[font_size=24][color=#ffd15a]%s[/color][/font_size]\n\n%s" % [_pages[i][0], _pages[i][1]]


func close_page() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_page()
		get_viewport().set_input_as_handled()


func _key(id: String) -> String:
	return "[b]%s[/b]" % Keybinds.key_name(id)


func _build_pages() -> Array:
	var tuning: Dictionary = GameConfig.tuning
	var wits_mult: float = tuning.get("wits_multiplier", 1.0)
	var turn_seconds := GameState.TG_MAX / (10.0 * GameState.TG_PER_WITS * wits_mult) / GameState.TICKS_PER_SECOND
	return [
		["Turns and the Turn Gauge",
			"Time keeps running. Every unit has a [b]Turn Gauge (TG)[/b] that fills at a speed set by its [b]Wits[/b] "
			+ "(a Wits-10 unit gets a turn about every %d seconds).\n\n" % roundi(turn_seconds)
			+ "When the gauge is full the unit is [color=#ffd15a][b]READY[/b][/color]: it can act right away, even while "
			+ "enemies act too. Each ready unit has its own countdown (longer with more [b]Patience[/b]). If it runs out, "
			+ "that unit loses its turn.\n\nThe [b]turn order strip[/b] at the top shows who is ready and who is next. "
			+ "Click a chip, click the unit, or press %s to pick one of your ready units." % _key("next_unit")],
		["Moving and acting",
			"On its turn a unit can [b]walk once[/b] and [b]use one ability[/b], in either order.\n\n"
			+ "Press %s (Move is on by default): the blue area shows where it can walk; dots show the path. " % _key("move")
			+ "Units walk around water, cliffs and enemies, and can climb at most 2 height levels at a time.\n\n"
			+ "[b]Sprint[/b] (%s) walks 125%% of the unit's Move, but it counts as its action: no ability that turn.\n\n" % _key("sprint")
			+ "Press %s to end the turn early. Skipping the move or the ability keeps some TG, so the next turn comes " % _key("end_turn")
			+ "sooner, and a turn that used no ability at all fills the gauge 25% faster until the next one."],
		["Abilities and casting",
			"Every job has 4 abilities (%s-%s). The 4th is an [b]Ultimate[/b]: it unlocks when the orange Ultimate bar is full "
			% [_key("ability_1"), _key("ability_4")]
			+ "(it fills when you act, when you're hit, and a little every turn).\n\n"
			+ "Basic attacks and most melee are [b]instant[/b], and you can still walk afterwards. Stronger abilities have a "
			+ "[color=#c08cff][b]cast time[/b][/color]: move first, because once a cast starts the unit can't move, and the "
			+ "spell goes off when the cast finishes. A purple circle shows where it will land. If the caster is knocked out, "
			+ "the spell fizzles.\n\nOpen the [b]Unit Guide[/b] (%s) for every job's numbers." % _key("unit_guide")],
		["Targeting",
			"Pick an ability, then click a target. Orange rings show its range; a red circle shows the area it hits.\n\n"
			+ "[b]Click a unit[/b] and a cast follows that unit. [b]Click the ground[/b] and it lands on that spot, hitting "
			+ "whoever is there when it goes off: use it to catch enemies where they're about to walk.\n\n"
			+ "[b]Out of range?[/b] Click anyway: the unit walks as far as it needs to and uses the ability when it "
			+ "arrives, aimed at the spot its target was standing on. Time runs on while it walks, so a target that "
			+ "moves away in the meantime is missed entirely.\n\n"
			+ "Ranged abilities need [b]line of sight[/b]: a hill between you and the target blocks the shot. Hover a target "
			+ "to see the damage forecast before you commit."],
		["Height, facing and statuses",
			"[b]Height:[/b] attacking from higher ground deals +10% per level (up to 30%).\n\n"
			+ "[b]Evasion and critical hits:[/b] every unit has [b]A-Eva[/b] (chance to evade a physical ability) and "
			+ "[b]M-Eva[/b] (harmful magic), and a [b]Crit[/b] chance that multiplies its damage. A miss shows as MISS.\n\n"
			+ "[b]Facing:[/b] units face where they last walked or aimed. Hits from the [b]side[/b] deal +10%, from "
			+ "[b]behind[/b] +25%.\n\n[b]Statuses[/b] show as tags over a unit's head:\n"
			+ "  [color=#ff8033]BRN Burn[/color]: loses 10% of max HP on each of its turns (Fire)\n"
			+ "  [color=#73ff8c]RGN Regen[/color]: recovers 10% of max HP on each of its turns (Chakra, Sanctuary)\n"
			+ "  [color=#80bfff]SLW Slow[/color]: Turn Gauge fills at half speed (Blizzard)\n"
			+ "  [color=#ffe64d]STN Stun[/color]: the turn it just earned is lost; its gauge still fills (Shield Bash)\n"
			+ "  [color=#b3e0ff]SHD Shield[/color]: soaks damage before HP, and breaks when it is used up\n"
			+ "  [color=#a8895c]ROT Root[/color]: can't walk, can still act\n"
			+ "  [color=#c78cff]SIL Silence[/color]: can't use abilities, can still walk\n"
			+ "  [color=#ff8f6b]TNT Taunt[/color]: must attack whoever taunted it, while that one is in reach\n\n"
			+ "A status lasts a number of the unit's own [b]turns[/b]: it acts and counts down when that unit's turn comes.\n\n"
			+ "[b]Engagement:[/b] an enemy engages the ground within 1.8 m of it. Walking in is free; stepping back "
			+ "out costs 1 m of movement.\n\n"
			+ "[b]The ground:[/b] embers burn and springs heal a unit that starts its turn on them; rocks can't be "
			+ "walked through and hide what is behind them.\n\n"
			+ "[b]Fog of war:[/b] you only see what your units can see."],
		["Knock-outs and winning",
			"A unit at 0 HP is [b]knocked out[/b]: it lies on the field with a [b]KO[/b] countdown (%d s). " % roundi(tuning.get("ko_seconds", GameState.KO_SECONDS))
			+ "The White Mage's [b]Raise[/b] can revive it with 30% HP before the countdown ends; after that it's gone.\n\n"
			+ "A team with no units standing loses. Battle Setup can add two more ways to finish: a [b]time limit[/b], "
			+ "where the side with more of its health left wins and level shares are a [b]draw[/b], and [b]holding the "
			+ "middle[/b], where standing alone inside the gold ring long enough wins. The line under the turn bars "
			+ "shows whichever is on. The game menu also has [b]Surrender[/b].\n\n"
			+ "The victory screen shows each unit's damage, healing and KOs, "
			+ "and lets you [b]rematch[/b] or [b]watch a replay[/b] of the battle."],
		["Controls",
			"%s  select or move / target\n" % "[b]Left-click[/b]"
			+ "%s  next ready unit     %s  move     %s-%s  abilities\n" % [_key("next_unit"), _key("move"), _key("ability_1"), _key("ability_4")]
			+ "%s  end turn     %s  cancel     %s  pause     %s  Unit Guide\n\n" % [_key("end_turn"), _key("cancel"), _key("pause"), _key("unit_guide")]
			+ "[b]Camera:[/b] %s%s%s%s pan, %s/%s up/down, %s/%s or right-drag to rotate, mouse wheel to zoom, "
			% [_key("cam_forward"), _key("cam_left"), _key("cam_back"), _key("cam_right"), _key("cam_up"), _key("cam_down"),
				_key("cam_rotate_left"), _key("cam_rotate_right")]
			+ "middle-drag to pan, %s to center on your unit. The camera only moves when you move it.\n\n" % _key("center_camera")
			+ "Every key can be changed in [b]Options[/b]."],
	]
