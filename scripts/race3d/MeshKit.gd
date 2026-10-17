class_name MeshKit
extends RefCounted
## Builds chunky, vertex-coloured meshes out of boxes and flat quads - the blocky, toy-like
## look (think Crossy Road) of the 3D race. Everything added to one kit becomes one mesh and
## one draw call, which keeps twenty detailed cars cheap.

var _st := SurfaceTool.new()
var _empty := true


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## An axis-aligned box (in the kit's space, or rotated by `basis`), each face slightly shaded
## so the blocks read without any texture.
func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)], 1.0],
		[Vector3.DOWN, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)], 0.62],
		[Vector3.RIGHT, [Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)], 0.9],
		[Vector3.LEFT, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z)], 0.84],
		[Vector3.BACK, [Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z)], 0.8],
		[Vector3.FORWARD, [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)], 0.76],
	]
	for face: Array in faces:
		var n: Vector3 = basis * (face[0] as Vector3)
		var shade: float = face[2]
		var c := Color(color.r * shade, color.g * shade, color.b * shade, color.a)
		var v: Array = face[1]
		quad(center + basis * (v[0] as Vector3), center + basis * (v[1] as Vector3), center + basis * (v[2] as Vector3), center + basis * (v[3] as Vector3), c, n)


## A quad a-b-c-d (counter-clockwise seen from the side the normal points to).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal: Vector3 = Vector3.UP) -> void:
	_empty = false
	for p: Vector3 in [a, c, b, a, d, c]:
		_st.set_color(color)
		_st.set_normal(normal)
		_st.add_vertex(p)


## A ring of boxes approximating a cylinder along X (wheels).
func cylinder_x(center: Vector3, radius: float, width: float, color: Color, sides: int = 8) -> void:
	for i in sides:
		var a := TAU * i / sides
		var p := center + Vector3(0, cos(a), sin(a)) * radius * 0.82
		box(p, Vector3(width, radius * 0.72, radius * 0.72), color, Basis(Vector3.RIGHT, a))


func is_empty() -> bool:
	return _empty


func commit() -> ArrayMesh:
	return _st.commit()


## The shared material: vertex colours, lit, a little sheen - toy blocks under real light.
static func material(alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.75
	m.metallic_specular = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, alpha)
	return m
