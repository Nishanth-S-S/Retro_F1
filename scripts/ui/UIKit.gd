class_name UIKit
extends RefCounted
## Shared look for every screen: arcade-style pixel UI on white, with red and dark
## racing-green accents.
## Chunky bevelled buttons, black dot-matrix title bars, framed panels with a caption
## set into the border, and a tiled chequered-flag backdrop.

const BG := Color("f6f7f4")
const BG_DEEP := Color("e8ece7")
const PANEL := Color("ffffff")
const PANEL_LIGHT := Color("ffffff")
const GRID := Color("e6ebe5")
const GRID_BOLD := Color("cdd7cf")
const LINE := Color("14532d")          # bright green borders
const INK := Color("0a0a0a")           # black
const ACCENT := Color("1b6b3c")        # mint highlight
const WARM := Color("c8201e")          # primary red (fills)
const HOT := Color("c8201e")           # red that stays readable as text on dark green
const TEXT := Color("13231a")
const TEXT_DIM := Color("66786d")
const GOOD := Color("1e8a4a")
const BAD := Color("d32f2f")
const PURPLE := Color("9a1f1b")

static var _theme: Theme
static var _font: Font


static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 0, border_width: int = 2, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(maxi(border_width, 2) if border.a > 0.0 else 0)
	sb.set_corner_radius_all(0 if radius < 20 else radius)
	sb.set_content_margin_all(margin)
	return sb


## Button face with a thick lower lip, like an arcade cabinet key.
static func key(bg: Color, border: Color, pressed: bool = false) -> StyleBoxFlat:
	var sb := box(bg, border, 0, 2, 10)
	sb.border_width_bottom = 2 if pressed else 6
	sb.content_margin_top = 12.0 if pressed else 8.0
	sb.content_margin_bottom = 6.0 if pressed else 10.0
	return sb


## Bold monospace system font for body text; titles use PixelFont.
static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Menlo", "DejaVu Sans Mono", "Roboto Mono", "Courier New", "monospace"])
		f.font_weight = 700
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font = f
	return _font


static func money(amount_k: float) -> String:
	return Career.money_text(amount_k)


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "Button", key(PANEL_LIGHT, LINE))
	t.set_stylebox("hover", "Button", key(Color("eef5ef"), LINE))
	t.set_stylebox("pressed", "Button", key(WARM, TEXT, true))
	t.set_stylebox("disabled", "Button", key(BG_DEEP, GRID_BOLD))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.lightened(0.4))
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "CheckButton", box(Color(PANEL_LIGHT, 0.6), Color.TRANSPARENT, 0, 0, 8))
	for state: String in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		t.set_color(state, "CheckButton", TEXT)
	t.set_stylebox("normal", "LineEdit", box(PANEL, LINE, 0, 2, 10))
	t.set_stylebox("focus", "LineEdit", box(PANEL, WARM, 0, 2, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 0, 2, 12))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 0, 2, 12))
	t.set_stylebox("slider", "HSlider", box(GRID_BOLD, Color.TRANSPARENT, 0, 0, 4))
	t.set_stylebox("grabber_area", "HSlider", box(WARM, Color.TRANSPARENT, 0, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(WARM.lightened(0.15), Color.TRANSPARENT, 0, 0, 4))
	t.set_icon("grabber", "HSlider", _block_texture(Color.WHITE, 20))
	t.set_icon("grabber_highlight", "HSlider", _block_texture(Color.WHITE, 22))
	t.set_icon("grabber_disabled", "HSlider", _block_texture(GRID_BOLD, 20))
	t.set_stylebox("scroll", "VScrollBar", box(Color(GRID, 0.6), Color.TRANSPARENT, 0, 0, 3))
	t.set_stylebox("grabber", "VScrollBar", box(LINE, Color.TRANSPARENT, 0, 0, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(ACCENT, Color.TRANSPARENT, 0, 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, Color.TRANSPARENT, 0, 0, 3))
	_theme = t
	return t


static func _block_texture(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	for i in size:
		for edge: int in [0, 1, size - 2, size - 1]:
			img.set_pixel(i, edge, INK)
			img.set_pixel(edge, i, INK)
	return ImageTexture.create_from_image(img)


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, size: int = 18, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 46)
	if accent:
		b.add_theme_stylebox_override("normal", key(WARM, Color("7d1412")))
		b.add_theme_stylebox_override("hover", key(WARM.lightened(0.12), Color("7d1412")))
		b.add_theme_stylebox_override("pressed", key(WARM.darkened(0.3), Color.WHITE, true))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(state, Color.WHITE)
	b.pressed.connect(func() -> void: AudioManager.play("click", -12.0))
	return b


static func panel(bg: Color = PANEL, border: Color = LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 0, 2, 12))
	return p


static func spacer(height: float = 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## Black marquee bar with dot-matrix lettering, as at the top of every screen.
static func title_bar(text: String, height: float = 58.0) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_meta("title", text)
	bar.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, bar.size)
		bar.draw_rect(r, LINE)
		bar.draw_rect(Rect2(0, r.size.y - 5.0, r.size.x, 5.0), WARM)
		PixelArt.draw_checker(bar, Rect2(6, 6, 30, height - 12.0), 6.0, Color(1, 1, 1, 0.9), Color(0.16, 0.16, 0.16))
		PixelArt.draw_checker(bar, Rect2(bar.size.x - 36.0, 6, 30, height - 12.0), 6.0, Color(1, 1, 1, 0.9), Color(0.16, 0.16, 0.16))
		var title: String = bar.get_meta("title")
		var px := floorf(minf(4.0, (bar.size.x - 100.0) / maxf(title.length() * 6.0, 1.0)))
		PixelFont.draw_centered(bar, r, title, maxf(px, 2.0), Color.WHITE, Color(0, 0, 0, 0.45)))
	return bar


## Tiled dark-green backdrop with faint chequered flags.
static func draw_backdrop(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(rect, BG)
	var step := Vector2(320, 250)
	var row := 0
	var y := rect.position.y - 20.0
	while y < rect.end.y:
		var x := rect.position.x - 40.0 + (160.0 if row % 2 == 1 else 0.0)
		while x < rect.end.x:
			PixelArt.draw_flag(canvas, Vector2(x, y), 6.0, Color(GRID_BOLD, 0.35), Color(BG, 0.0), Color(GRID_BOLD, 0.35))
			x += step.x
		y += step.y
		row += 1


## Workshop grid used behind the garage car.
static func draw_blueprint_grid(canvas: CanvasItem, rect: Rect2, cell: float = 32.0) -> void:
	canvas.draw_rect(rect, BG)
	var x := rect.position.x
	var i := 0
	while x <= rect.end.x:
		canvas.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), GRID_BOLD if i % 4 == 0 else GRID, 1.0)
		x += cell
		i += 1
	var y := rect.position.y
	i = 0
	while y <= rect.end.y:
		canvas.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GRID_BOLD if i % 4 == 0 else GRID, 1.0)
		y += cell
		i += 1
