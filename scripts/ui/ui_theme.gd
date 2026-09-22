extends RefCounted
## The shared look for every screen: dark translucent rounded panels, a gold
## accent for hover and selection, and matching buttons. Apply it with
## `control.theme = UiTheme.build()` on a screen's root control.

const TEXT := Color(0.92, 0.94, 1.0)
const DIM := Color(0.92, 0.94, 1.0, 0.55)
const GOLD := Color(1.0, 0.82, 0.35)
const PANEL_BG := Color(0.06, 0.08, 0.12, 0.78)

static var _cached: Theme


static func box(bg: Color, border := Color(0, 0, 0, 0), border_width := 0, radius := 8, pad := Vector2(10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	t.default_font_size = 14
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, Color(1, 1, 1, 0.07), 1, 10, Vector2(12, 10)))
	t.set_stylebox("panel", "Panel", box(PANEL_BG, Color(1, 1, 1, 0.07), 1, 10))

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(Color(0.12, 0.15, 0.21, 0.92), Color(1, 1, 1, 0.08), 1, 8))
		t.set_stylebox("hover", type, box(Color(0.17, 0.21, 0.29, 0.95), Color(GOLD, 0.7), 1, 8))
		t.set_stylebox("pressed", type, box(Color(0.32, 0.25, 0.09, 0.95), GOLD, 2, 8))
		t.set_stylebox("hover_pressed", type, box(Color(0.36, 0.28, 0.1, 0.95), GOLD, 2, 8))
		t.set_stylebox("disabled", type, box(Color(0.09, 0.11, 0.15, 0.7), Color(1, 1, 1, 0.04), 1, 8))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, GOLD)
		t.set_color("font_hover_pressed_color", type, GOLD)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.3))
		t.set_font_size("font_size", type, 13)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.06), 1, 4, Vector2.ZERO))

	t.set_stylebox("normal", "LineEdit", box(Color(0.05, 0.07, 0.1, 0.9), Color(1, 1, 1, 0.1), 1, 6, Vector2(8, 6)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), Color(GOLD, 0.8), 1, 6))
	t.set_color("font_color", "LineEdit", TEXT)

	t.set_stylebox("panel", "TabContainer", box(Color(0.05, 0.07, 0.1, 0.6), Color(1, 1, 1, 0.06), 1, 8))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.2, 0.17, 0.08, 0.95), GOLD, 1, 6, Vector2(12, 5)))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.1, 0.12, 0.17, 0.9), Color(1, 1, 1, 0.06), 1, 6, Vector2(12, 5)))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.16, 0.19, 0.26, 0.95), Color(GOLD, 0.6), 1, 6, Vector2(12, 5)))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", DIM)

	t.set_stylebox("panel", "PopupMenu", box(Color(0.07, 0.09, 0.13, 0.98), Color(1, 1, 1, 0.1), 1, 8))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.25, 0.2, 0.08, 0.95), Color(0, 0, 0, 0), 0, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	_cached = t
	return t
