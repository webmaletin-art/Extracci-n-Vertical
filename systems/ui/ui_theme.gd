class_name UiTheme
extends RefCounted
## Estilo común de los menús: blanco con líneas de tinta (como el juego).

const BG := Color(0.97, 0.97, 0.96)
const PANEL := Color(1, 1, 1, 0.97)
const PANEL_HI := Color(1, 1, 1, 1.0)
const ACCENT := Color(0.07, 0.07, 0.09)
const ACCENT_DIM := Color(0.86, 0.86, 0.85)
const TEXT := Color(0.07, 0.07, 0.09)
const MUTED := Color(0.42, 0.42, 0.45)

static func box(c: Color, radius := 8, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

static func make() -> Theme:
	var t := Theme.new()
	t.set_font_size("font_size", "Label", 20)
	t.set_color("font_color", "Label", TEXT)
	for cls in ["Button", "OptionButton"]:
		t.set_stylebox("normal", cls, box(PANEL_HI, 10, TEXT, 2))
		t.set_stylebox("hover", cls, box(Color(0.93, 0.93, 0.92), 10, TEXT, 2))
		t.set_stylebox("pressed", cls, box(ACCENT_DIM, 10, TEXT, 3))
		t.set_stylebox("focus", cls, box(Color(0, 0, 0, 0), 10, ACCENT, 2))
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, TEXT)
		t.set_color("font_pressed_color", cls, TEXT)
		t.set_font_size("font_size", cls, 22)
	t.set_stylebox("panel", "PopupMenu", box(PANEL, 8, ACCENT_DIM, 1))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT_DIM, 4))
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 14, Color(1, 1, 1, 0.06), 1))
	# deslizador: carril fino y perilla naranja grande (fácil de tocar)
	var track := box(Color(0.2, 0.23, 0.28), 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT_DIM, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 4))
	var knob := GradientTexture2D.new()
	knob.width = 34
	knob.height = 34
	knob.fill = GradientTexture2D.FILL_RADIAL
	knob.fill_from = Vector2(0.5, 0.5)
	knob.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.8, 0.84, 1.0])
	g.colors = PackedColorArray([ACCENT, ACCENT, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	knob.gradient = g
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	t.set_icon("grabber_disabled", "HSlider", knob)
	t.set_font_size("font_size", "CheckBox", 20)
	t.set_constant("h_separation", "CheckBox", 12)
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0), 0))
	return t
