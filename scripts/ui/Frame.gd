class_name Frame
extends PanelContainer
## A bordered group box with its caption set into the top border ("MODES", "ON THE GRID").

var caption := ""
var body: VBoxContainer


static func make(title: String, separation: int = 8) -> Frame:
	var f := Frame.new()
	f.caption = title
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.set_content_margin_all(14)
	sb.content_margin_top = 22
	f.add_theme_stylebox_override("panel", sb)
	f.body = VBoxContainer.new()
	f.body.add_theme_constant_override("separation", separation)
	f.add_child(f.body)
	return f


func _draw() -> void:
	var r := Rect2(Vector2(2, 9), size - Vector2(4, 11))
	draw_rect(r, Color(UIKit.PANEL, 0.96))
	draw_rect(r, UIKit.LINE, false, 2.0)
	if caption == "":
		return
	var f := UIKit.font()
	var w := f.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16.0
	var x := (size.x - w) * 0.5
	draw_rect(Rect2(x, 0, w, 18), UIKit.PANEL)
	draw_string(f, Vector2(x + 8.0, 14), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.TEXT)
