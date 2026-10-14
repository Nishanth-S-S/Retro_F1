class_name NightLights
extends CanvasLayer
## Night races: the world is darkened by a CanvasModulate and this layer, which moves with
## the camera, adds warm pools of light under every floodlight and around the grandstands.

var lamps := PackedVector2Array()
var stands := PackedVector2Array()
var _canvas: Node2D
var _glow: Texture2D


func _ready() -> void:
	layer = 1
	follow_viewport_enabled = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	_glow = texture
	_canvas = Node2D.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_canvas.material = material
	_canvas.draw.connect(_paint)
	add_child(_canvas)


func _paint() -> void:
	var ppm := VehiclePhysicsConfig.PPM
	for p in lamps:
		var r := 30.0 * ppm
		_canvas.draw_texture_rect(_glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1.0, 0.86, 0.6, 0.55))
	for p in stands:
		var r := 46.0 * ppm
		_canvas.draw_texture_rect(_glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.75, 0.85, 1.0, 0.45))
