class_name UIKit
## UIKit: tiny factory for consistently styled controls. All UI is built in
## code from these helpers, so the whole game keeps one look without any theme
## resources.
##
## Sized for the web build: a 1280x720 landscape canvas driven by a mouse. The
## kit started out thumb-sized for portrait phones (92px buttons), which on a
## landscape screen pushed every page into a scroll list. Cursor targets can be
## half that, and the freed space goes to showing a whole page at once.

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
const RADIUS := 12

# Type scale. Screens should reach for these rather than inventing sizes, so
# one page never ends up visibly larger than the next.
const FONT_TITLE := 34
const FONT_HEADING := 21
const FONT_BODY := 17
const FONT_SMALL := 14
const FONT_BUTTON := 18


static func flat_style(color: Color, radius := RADIUS, margin_h := 16, margin_v := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


## Raised surface: subtle top-light border + drop shadow. Buttons and panels
## use this so the UI reads as layered depth rather than flat rectangles.
static func raised_style(color: Color, radius := 10, lift := 0.16) -> StyleBoxFlat:
	var sb := flat_style(color, radius, 14, 5)
	sb.border_width_top = 2
	sb.border_color = color.lightened(lift + 0.10)
	sb.shadow_color = Color(0, 0, 0, 0.40)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb


## Outline + shadow so text stays legible over bright rock, dark caves and
## magma alike. Cheap insurance: HUD text sits directly on the world.
static func legible(l: Label, outline := 4) -> Label:
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	return l


## Round, thumb-sized touch pad. Far less visually intrusive than a filled
## rectangle sitting on top of the terrain. Unused by the web build (keyboard
## and mouse), kept for a touch build.
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


static func button(text: String, font_size := FONT_BUTTON, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	# Height follows the text: an 18px label gets a 44px button. Comfortable for
	# a cursor, and a row of them no longer costs a fifth of the screen.
	b.custom_minimum_size = Vector2(0, maxi(34, roundi(font_size * 2.2) + 4))
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var base := ACCENT if accent else Color(0.24, 0.22, 0.30)
	b.add_theme_stylebox_override("normal", raised_style(base))
	b.add_theme_stylebox_override("hover", raised_style(base.lightened(0.10)))
	b.add_theme_stylebox_override("pressed", flat_style(base.darkened(0.18), 10, 14, 5))
	b.add_theme_stylebox_override("disabled", flat_style(Color(0.18, 0.17, 0.22), 10, 14, 5))
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)
	b.pressed.connect(func() -> void: AudioManager.play("click", -8.0))
	return b


## Fixed-width button for footers and dialogs, where a full-width bar would
## read as a banner rather than something to click.
static func action_button(text: String, accent := true, width := 220, font_size := 20) -> Button:
	var b := button(text, font_size, accent)
	b.custom_minimum_size.x = width
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


## A left-aligned list entry that stays highlighted while selected. Used by the
## list-and-detail pages (codex, guide), which replace long scrolling lists.
static func list_button(text: String, group: ButtonGroup) -> Button:
	var b := button(text, 15)
	b.custom_minimum_size.y = 32
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_stylebox_override("pressed", raised_style(ACCENT_DARK))
	b.add_theme_stylebox_override("hover_pressed", raised_style(ACCENT_DARK.lightened(0.08)))
	return b


static func label(text: String, font_size := FONT_BODY, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrapped(text: String, font_size := FONT_BODY, color := TEXT) -> Label:
	var l := label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, font_size := FONT_TITLE) -> Label:
	var l := label(text, font_size, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func panel(color := PANEL, radius := RADIUS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat_style(color, radius))
	return p


static func vbox(separation := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func progress(fg: Color, bg := Color(0.1, 0.1, 0.12, 0.8)) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 16)
	p.add_theme_stylebox_override("background", flat_style(bg, 6, 0, 0))
	p.add_theme_stylebox_override("fill", flat_style(fg, 6, 0, 0))
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
	var pan := PanelContainer.new()
	pan.add_theme_stylebox_override("panel", flat_style(PANEL, 16, 28, 22))
	pan.custom_minimum_size = Vector2(520, 0)
	center.add_child(pan)
	var content := vbox(12)
	pan.add_child(content)
	if title_text != "":
		content.add_child(title(title_text, 28))
	return content


## Full-screen page (shop, depot, map, ...): opaque backdrop, page margins and
## a title. Returns the content column for the page to fill.
static func screen(parent: Node, title_text: String) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 56)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	parent.add_child(margin)
	var col := vbox(10)
	margin.add_child(col)
	if title_text != "":
		col.add_child(title(title_text))
	return col


## Centered row for a page's closing buttons.
static func footer() -> HBoxContainer:
	var row := hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	return row


## Pushes everything after it to the bottom of a VBox (or the end of an HBox).
static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
