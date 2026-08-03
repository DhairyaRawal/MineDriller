class_name UIKit
## UIKit: tiny factory for consistently styled, thumb-sized controls.
## All UI is built in code from these helpers, so the whole game keeps one
## look without any theme resources.

# Palette. Warm indigo rather than near-black, and high-chroma accents: the
# audience is children, so the UI should feel bright and inviting while keeping
# text contrast well above WCAG AA against every surface it sits on.
const BG := Color(0.12, 0.11, 0.19, 0.95)
const PANEL := Color(0.20, 0.18, 0.29, 0.98)
const PANEL_HI := Color(0.26, 0.23, 0.37, 0.98)
const ACCENT := Color(1.00, 0.60, 0.16)
const ACCENT_DARK := Color(0.62, 0.33, 0.07)
const TEXT := Color(0.98, 0.97, 0.94)
const TEXT_DIM := Color(0.78, 0.76, 0.83)
const GOOD := Color(0.38, 0.85, 0.52)
const BAD := Color(0.96, 0.36, 0.42)
const HEAT := Color(0.99, 0.42, 0.16)
const ETHER := Color(0.48, 0.88, 1.00)
const RADIUS := 18


static func flat_style(color: Color, radius := RADIUS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


## Raised surface: subtle top-light border + drop shadow. Buttons and panels
## use this so the UI reads as layered depth rather than flat rectangles.
static func raised_style(color: Color, radius := RADIUS, lift := 0.16) -> StyleBoxFlat:
	var sb := flat_style(color, radius)
	sb.border_width_top = 2
	sb.border_color = color.lightened(lift + 0.10)
	sb.shadow_color = Color(0, 0, 0, 0.40)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


## Outline + shadow so text stays legible over bright rock, dark caves and
## magma alike. Cheap insurance: HUD text sits directly on the world.
static func legible(l: Label, outline := 5) -> Label:
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	return l


## Round, thumb-sized touch pad. Far less visually intrusive than a filled
## rectangle sitting on top of the terrain.
static func touch_pad(glyph: String, diameter := 132) -> Button:
	var b := Button.new()
	b.text = glyph
	b.custom_minimum_size = Vector2(diameter, diameter)
	# Without this the parent container stretches the pad into an oval.
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	var r := diameter / 2
	var idle := flat_style(Color(0.10, 0.09, 0.13, 0.42), r)
	idle.border_width_bottom = 3
	idle.border_width_top = 3
	idle.border_width_left = 3
	idle.border_width_right = 3
	idle.border_color = Color(1, 1, 1, 0.20)
	var down := flat_style(ACCENT * Color(1, 1, 1, 0.72), r)
	down.border_width_bottom = 3
	down.border_width_top = 3
	down.border_width_left = 3
	down.border_width_right = 3
	down.border_color = Color(1, 1, 1, 0.45)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", idle)
	b.add_theme_stylebox_override("pressed", down)
	return b


static func button(text: String, font_size := 30, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 92)  # >= 48dp touch target with margin
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var base := ACCENT if accent else Color(0.24, 0.22, 0.30)
	b.add_theme_stylebox_override("normal", raised_style(base))
	b.add_theme_stylebox_override("hover", raised_style(base.lightened(0.10)))
	b.add_theme_stylebox_override("pressed", flat_style(base.darkened(0.18)))
	b.add_theme_stylebox_override("disabled", flat_style(Color(0.18, 0.17, 0.22)))
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.pressed.connect(func() -> void: AudioManager.play("click", -8.0))
	return b


static func label(text: String, font_size := 26, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, font_size := 46) -> Label:
	var l := label(text, font_size, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func panel(color := PANEL, radius := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_style(color, radius))
	return p


static func vbox(separation := 14) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func progress(fg: Color, bg := Color(0.1, 0.1, 0.12, 0.8)) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 26)
	p.add_theme_stylebox_override("background", flat_style(bg, 8))
	p.add_theme_stylebox_override("fill", flat_style(fg, 8))
	return p


## Full-screen dim + centered panel; returns the content VBox.
static func modal(parent: Node, title_text: String) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.name = "Modal"
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var pan := panel()
	pan.custom_minimum_size = Vector2(600, 0)
	center.add_child(pan)
	var content := vbox(18)
	pan.add_child(content)
	if title_text != "":
		content.add_child(title(title_text, 40))
	return content
