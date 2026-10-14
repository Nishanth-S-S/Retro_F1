class_name PixelArt
extends RefCounted
## Pixel-art people, helmets, flags, cars, phone and team emblems, all drawn from data
## on a 16x16 grid - no image assets.

const SKIN: PackedStringArray = ["f6d3b3", "e3b08a", "c98d62", "9a6642", "6b4429"]
const HAIR_COLORS: PackedStringArray = ["2b2118", "6b4423", "c9973f", "b5382a", "d9d9d9", "3a3f5c"]
const HAIR_STYLES: PackedStringArray = ["SHORT", "SWEPT", "LONG", "BUZZ", "BALD", "CURLY", "MOHAWK"]
const ACCESSORIES: PackedStringArray = ["NONE", "HEADSET", "GLASSES", "SHADES", "CAP", "BEARD", "MOUSTACHE"]
const OUTFITS: PackedStringArray = ["TEAM POLO", "SUIT", "RACE JACKET", "HOODIE"]
const GRID := 16
const INK := Color("101418")


static func default_look() -> Dictionary:
	return {"skin": 1, "hair": 0, "hair_color": 0, "accessory": 1, "outfit": 0}


static func random_look(seed_value: int, outfit: int = 2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var extras := [0, 0, 0, 2, 3, 5, 6, 4]
	return {"skin": rng.randi() % SKIN.size(), "hair": rng.randi() % HAIR_STYLES.size(), "hair_color": rng.randi() % HAIR_COLORS.size(), "accessory": extras[rng.randi() % extras.size()], "outfit": outfit}


static func _px(canvas: CanvasItem, origin: Vector2, cell: float, x: int, y: int, w: int, h: int, color: Color) -> void:
	canvas.draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(w, h) * cell), color)


## Half-cell pixel: coordinates on a 32x32 grid, for fine detail on top of the 16x16 base.
static func _hp(canvas: CanvasItem, origin: Vector2, cell: float, x: int, y: int, w: int, h: int, color: Color) -> void:
	canvas.draw_rect(Rect2(origin + Vector2(x, y) * cell * 0.5, Vector2(w, h) * cell * 0.5), color)


static func _fit(rect: Rect2) -> Array:
	var cell := maxf(1.0, floorf(minf(rect.size.x, rect.size.y) / GRID))
	return [cell, rect.position + (rect.size - Vector2(cell, cell) * GRID) * 0.5]


## Draws a shaded 16x16 bust inside `rect`.
static func draw_portrait(canvas: CanvasItem, rect: Rect2, look: Dictionary, team_color: Color, background: Color) -> void:
	var fit := _fit(rect)
	var cell: float = fit[0]
	var o: Vector2 = fit[1]
	canvas.draw_rect(Rect2(o, Vector2(cell, cell) * GRID), background)
	# Two-tone backdrop stripe gives the card some depth.
	_px(canvas, o, cell, 0, 10, 16, 6, background.darkened(0.18))
	var skin := Color(SKIN[int(look.get("skin", 0)) % SKIN.size()])
	var shade := skin.darkened(0.16)
	var hair := Color(HAIR_COLORS[int(look.get("hair_color", 0)) % HAIR_COLORS.size()])
	var hair_hi := hair.lightened(0.22)
	var outfit := int(look.get("outfit", 0)) % OUTFITS.size()
	# --- torso
	var cloth := team_color
	if outfit == 1:
		cloth = Color("23262e")
	elif outfit == 3:
		cloth = Color("3a3f48")
	_px(canvas, o, cell, 3, 12, 10, 1, cloth)
	_px(canvas, o, cell, 2, 13, 12, 3, cloth)
	_px(canvas, o, cell, 2, 13, 1, 3, cloth.darkened(0.25))
	_px(canvas, o, cell, 13, 13, 1, 3, cloth.darkened(0.25))
	match outfit:
		0:
			_px(canvas, o, cell, 6, 12, 4, 1, Color.WHITE)
			_px(canvas, o, cell, 7, 13, 2, 1, Color.WHITE)
			_px(canvas, o, cell, 10, 14, 2, 1, cloth.lightened(0.35))
		1:
			_px(canvas, o, cell, 7, 12, 2, 4, Color.WHITE)
			_px(canvas, o, cell, 7, 13, 2, 3, team_color)
			_px(canvas, o, cell, 6, 12, 1, 3, Color("3b404b"))
			_px(canvas, o, cell, 9, 12, 1, 3, Color("3b404b"))
		2:
			_px(canvas, o, cell, 2, 14, 12, 1, Color.WHITE)
			_px(canvas, o, cell, 7, 12, 2, 4, cloth.darkened(0.3))
			_px(canvas, o, cell, 4, 13, 2, 1, Color.WHITE)
		3:
			_px(canvas, o, cell, 5, 11, 6, 1, cloth.lightened(0.15))
			_px(canvas, o, cell, 7, 13, 1, 2, Color.WHITE)
			_px(canvas, o, cell, 9, 13, 1, 2, Color.WHITE)
			_px(canvas, o, cell, 4, 14, 3, 1, team_color)
	# --- neck and head
	_px(canvas, o, cell, 6, 10, 4, 2, shade)
	_px(canvas, o, cell, 4, 3, 8, 8, skin)
	_px(canvas, o, cell, 5, 10, 6, 1, skin)
	_px(canvas, o, cell, 11, 4, 1, 6, shade)             # side shading
	_px(canvas, o, cell, 3, 6, 1, 2, skin)               # ears
	_px(canvas, o, cell, 12, 6, 1, 2, shade)
	# --- face
	_px(canvas, o, cell, 5, 6, 2, 1, Color.WHITE)
	_px(canvas, o, cell, 9, 6, 2, 1, Color.WHITE)
	_px(canvas, o, cell, 6, 6, 1, 1, INK)
	_px(canvas, o, cell, 10, 6, 1, 1, INK)
	_px(canvas, o, cell, 5, 5, 2, 1, hair.darkened(0.2))  # brows
	_px(canvas, o, cell, 9, 5, 2, 1, hair.darkened(0.2))
	_px(canvas, o, cell, 8, 7, 1, 2, shade)              # nose
	_px(canvas, o, cell, 6, 9, 4, 1, Color("8a3b34"))    # mouth
	_px(canvas, o, cell, 7, 9, 2, 1, Color("f3e9e2"))
	# --- fine detail (half pixels): rounded jaw, eye shine, lids, blush, nostrils, lip light
	var lower_bg := background.darkened(0.18)
	_hp(canvas, o, cell, 8, 20, 1, 2, lower_bg)
	_hp(canvas, o, cell, 23, 20, 1, 2, lower_bg)
	_hp(canvas, o, cell, 9, 21, 1, 1, shade)
	_hp(canvas, o, cell, 22, 21, 1, 1, shade)
	_hp(canvas, o, cell, 10, 22, 1, 1, lower_bg)
	_hp(canvas, o, cell, 21, 22, 1, 1, lower_bg)
	_hp(canvas, o, cell, 12, 12, 1, 1, Color.WHITE)
	_hp(canvas, o, cell, 20, 12, 1, 1, Color.WHITE)
	_hp(canvas, o, cell, 13, 13, 1, 1, Color("5a3a22"))
	_hp(canvas, o, cell, 21, 13, 1, 1, Color("5a3a22"))
	_hp(canvas, o, cell, 10, 14, 4, 1, shade)
	_hp(canvas, o, cell, 18, 14, 4, 1, shade)
	_hp(canvas, o, cell, 9, 16, 2, 2, Color(0.95, 0.45, 0.4, 0.28))
	_hp(canvas, o, cell, 21, 16, 2, 2, Color(0.95, 0.45, 0.4, 0.28))
	_hp(canvas, o, cell, 15, 17, 1, 1, skin.darkened(0.4))
	_hp(canvas, o, cell, 18, 17, 1, 1, skin.darkened(0.4))
	_hp(canvas, o, cell, 13, 20, 6, 1, Color(1, 1, 1, 0.18))
	_hp(canvas, o, cell, 12, 22, 8, 1, skin.darkened(0.3))
	_hp(canvas, o, cell, 6, 13, 1, 2, shade)
	_hp(canvas, o, cell, 9, 7, 1, 12, Color(1, 1, 1, 0.12))
	# Shirt detail: seams and a team patch.
	_hp(canvas, o, cell, 6, 27, 1, 5, cloth.darkened(0.35))
	_hp(canvas, o, cell, 25, 27, 1, 5, cloth.darkened(0.35))
	_hp(canvas, o, cell, 20, 27, 3, 2, Color.WHITE)
	_hp(canvas, o, cell, 21, 27, 1, 2, team_color.darkened(0.2) if outfit != 0 else INK)
	# --- hair
	match int(look.get("hair", 0)) % HAIR_STYLES.size():
		0:
			_px(canvas, o, cell, 4, 2, 8, 2, hair)
			_px(canvas, o, cell, 5, 1, 6, 1, hair)
			_px(canvas, o, cell, 4, 4, 1, 2, hair)
			_px(canvas, o, cell, 11, 4, 1, 2, hair)
			_px(canvas, o, cell, 6, 2, 3, 1, hair_hi)
		1:
			_px(canvas, o, cell, 4, 2, 9, 2, hair)
			_px(canvas, o, cell, 6, 1, 7, 1, hair)
			_px(canvas, o, cell, 10, 0, 3, 1, hair)
			_px(canvas, o, cell, 4, 4, 1, 2, hair)
			_px(canvas, o, cell, 7, 2, 4, 1, hair_hi)
		2:
			_px(canvas, o, cell, 4, 1, 8, 3, hair)
			_px(canvas, o, cell, 3, 3, 1, 9, hair)
			_px(canvas, o, cell, 12, 3, 1, 9, hair)
			_px(canvas, o, cell, 2, 8, 1, 4, hair)
			_px(canvas, o, cell, 13, 8, 1, 4, hair)
			_px(canvas, o, cell, 6, 2, 3, 1, hair_hi)
		3:
			_px(canvas, o, cell, 4, 2, 8, 2, Color(hair, 0.75))
			_px(canvas, o, cell, 5, 2, 6, 1, hair)
		4:
			_px(canvas, o, cell, 5, 2, 6, 1, skin)
			_px(canvas, o, cell, 6, 3, 2, 1, skin.lightened(0.25))
		5:
			_px(canvas, o, cell, 3, 1, 10, 3, hair)
			_px(canvas, o, cell, 4, 0, 8, 1, hair)
			_px(canvas, o, cell, 3, 4, 1, 2, hair)
			_px(canvas, o, cell, 12, 4, 1, 2, hair)
			for hx: int in [4, 7, 10]:
				_px(canvas, o, cell, hx, 1, 1, 1, hair_hi)
		6:
			_px(canvas, o, cell, 7, 0, 2, 4, hair)
			_px(canvas, o, cell, 6, 1, 4, 2, hair)
			_px(canvas, o, cell, 7, 0, 1, 2, hair_hi)
	if int(look.get("hair", 0)) % HAIR_STYLES.size() != 4:
		# Strand highlights break up the flat hair block.
		for hx: int in [10, 14, 18]:
			_hp(canvas, o, cell, hx, 5, 1, 2, hair_hi)
		_hp(canvas, o, cell, 21, 4, 1, 2, hair.darkened(0.25))
	# --- accessory
	match int(look.get("accessory", 0)) % ACCESSORIES.size():
		1:
			_px(canvas, o, cell, 3, 2, 10, 1, INK)
			_px(canvas, o, cell, 2, 3, 1, 4, INK)
			_px(canvas, o, cell, 13, 3, 1, 4, INK)
			_px(canvas, o, cell, 1, 5, 2, 3, team_color)
			_px(canvas, o, cell, 13, 5, 2, 3, team_color)
			_px(canvas, o, cell, 2, 8, 1, 2, INK)
			_px(canvas, o, cell, 3, 10, 3, 1, INK)
		2:
			_px(canvas, o, cell, 4, 6, 8, 1, INK)
			_px(canvas, o, cell, 5, 6, 2, 1, Color("cfe8ff"))
			_px(canvas, o, cell, 9, 6, 2, 1, Color("cfe8ff"))
			_px(canvas, o, cell, 4, 5, 3, 1, INK)
			_px(canvas, o, cell, 9, 5, 3, 1, INK)
			_px(canvas, o, cell, 4, 7, 3, 1, INK)
			_px(canvas, o, cell, 9, 7, 3, 1, INK)
		3:
			_px(canvas, o, cell, 3, 6, 10, 1, INK)
			_px(canvas, o, cell, 4, 5, 4, 3, INK)
			_px(canvas, o, cell, 9, 5, 3, 3, INK)
			_px(canvas, o, cell, 5, 5, 1, 1, Color(1, 1, 1, 0.6))
		4:
			_px(canvas, o, cell, 4, 1, 8, 3, team_color)
			_px(canvas, o, cell, 5, 0, 6, 1, team_color)
			_px(canvas, o, cell, 3, 4, 11, 1, team_color.darkened(0.3))
			_px(canvas, o, cell, 7, 2, 2, 1, Color.WHITE)
		5:
			_px(canvas, o, cell, 4, 8, 8, 3, hair)
			_px(canvas, o, cell, 5, 11, 6, 1, hair)
			_px(canvas, o, cell, 6, 9, 4, 1, Color("8a3b34"))
		6:
			_px(canvas, o, cell, 5, 8, 6, 1, hair)
			_px(canvas, o, cell, 5, 9, 1, 1, hair)
			_px(canvas, o, cell, 10, 9, 1, 1, hair)
	canvas.draw_rect(Rect2(o, Vector2(cell, cell) * GRID), INK, false, maxf(2.0, cell * 0.35))


## Side-on racing helmet with visor reflection and a livery pattern.
static func draw_helmet(canvas: CanvasItem, rect: Rect2, color: Color, color2: Color, seed_value: int) -> void:
	var fit := _fit(rect)
	var cell: float = fit[0]
	var o: Vector2 = fit[1]
	var dark := color.darkened(0.3)
	_px(canvas, o, cell, 5, 2, 7, 1, color)
	_px(canvas, o, cell, 3, 3, 10, 1, color)
	_px(canvas, o, cell, 2, 4, 12, 2, color)
	_px(canvas, o, cell, 1, 6, 14, 5, color)
	_px(canvas, o, cell, 2, 11, 13, 1, color)
	_px(canvas, o, cell, 3, 12, 11, 1, dark)
	_px(canvas, o, cell, 5, 13, 8, 1, dark)
	_px(canvas, o, cell, 1, 6, 1, 5, dark)
	_px(canvas, o, cell, 5, 2, 4, 1, color.lightened(0.3))           # crown highlight
	_px(canvas, o, cell, 3, 4, 2, 1, color.lightened(0.3))
	# Visor.
	_px(canvas, o, cell, 7, 6, 8, 4, INK)
	_px(canvas, o, cell, 8, 5, 6, 1, INK)
	_px(canvas, o, cell, 9, 6, 4, 1, Color("7fb6d9"))
	_px(canvas, o, cell, 13, 7, 1, 2, Color("7fb6d9"))
	_px(canvas, o, cell, 8, 7, 2, 1, Color(1, 1, 1, 0.75))
	_px(canvas, o, cell, 7, 10, 8, 1, Color("d7dbe0"))                # visor strip
	# Chin vents.
	_px(canvas, o, cell, 10, 11, 1, 1, INK)
	_px(canvas, o, cell, 12, 11, 1, 1, INK)
	# Fine detail: rounded shell, visor gradient, air intake, number roundel.
	_hp(canvas, o, cell, 9, 4, 1, 1, color)
	_hp(canvas, o, cell, 24, 4, 2, 1, color)
	_hp(canvas, o, cell, 5, 6, 1, 1, color)
	_hp(canvas, o, cell, 26, 6, 2, 2, color)
	_hp(canvas, o, cell, 3, 8, 1, 2, color)
	_hp(canvas, o, cell, 16, 15, 12, 1, Color("3b6f93"))
	_hp(canvas, o, cell, 16, 18, 13, 1, Color(0, 0, 0, 0.45))
	_hp(canvas, o, cell, 27, 13, 1, 5, Color(1, 1, 1, 0.35))
	_hp(canvas, o, cell, 6, 23, 3, 1, INK)
	_hp(canvas, o, cell, 12, 5, 6, 1, Color(1, 1, 1, 0.45))
	_hp(canvas, o, cell, 5, 14, 5, 5, Color.WHITE)
	_hp(canvas, o, cell, 6, 15, 3, 3, color2)
	match seed_value % 4:
		0:
			_px(canvas, o, cell, 2, 4, 5, 1, color2)
			_px(canvas, o, cell, 1, 8, 6, 1, color2)
		1:
			_px(canvas, o, cell, 6, 2, 2, 4, color2)
			_px(canvas, o, cell, 4, 6, 2, 5, color2)
		2:
			for i in 4:
				_px(canvas, o, cell, 2 + i, 9 - i, 2, 1, color2)
		3:
			_px(canvas, o, cell, 2, 5, 4, 1, color2)
			_px(canvas, o, cell, 2, 7, 4, 1, color2)
			_px(canvas, o, cell, 2, 9, 4, 1, color2)


static func draw_checker(canvas: CanvasItem, rect: Rect2, cell: float, light: Color, dark: Color) -> void:
	var cols := int(ceil(rect.size.x / cell))
	var rows := int(ceil(rect.size.y / cell))
	for y in rows:
		for x in cols:
			var r := Rect2(rect.position + Vector2(x, y) * cell, Vector2(minf(cell, rect.size.x - x * cell), minf(cell, rect.size.y - y * cell)))
			canvas.draw_rect(r, light if (x + y) % 2 == 0 else dark)


## A small waving chequered flag on a pole. Occupies about 9 x 10 pixels of size `px`.
static func draw_flag(canvas: CanvasItem, pos: Vector2, px: float, light: Color, dark: Color, pole: Color, mirrored: bool = false) -> void:
	var dir := -1.0 if mirrored else 1.0
	var base := pos + (Vector2(9.0 * px, 0) if mirrored else Vector2.ZERO)
	canvas.draw_rect(Rect2(base + Vector2(-px if mirrored else 0.0, 0), Vector2(px, 10.0 * px)), pole)
	for x in 7:
		var wave := 1.0 if x >= 2 and x <= 4 else 0.0
		for y in 5:
			var cell_pos := base + Vector2(dir * (1 + x) * px - (px if mirrored else 0.0), (y + wave) * px)
			canvas.draw_rect(Rect2(cell_pos, Vector2(px, px)), light if (x + y) % 2 == 0 else dark)


## Top-down pixel formula car, nose to the right. 26 x 12 pixels of size `px`.
static func draw_car(canvas: CanvasItem, pos: Vector2, px: float, color: Color, color2: Color) -> void:
	var o := pos
	var tire := Color("16181c")
	for wheel: Array in [[3, 0], [3, 9], [18, 0], [18, 9]]:
		_px(canvas, o, px, wheel[0], wheel[1], 5, 3, tire)
		_px(canvas, o, px, wheel[0] + 1, wheel[1], 1, 3, Color("3a3d44"))
	_px(canvas, o, px, 0, 1, 2, 10, color2)                # rear wing
	_px(canvas, o, px, 2, 3, 1, 6, INK)
	_px(canvas, o, px, 23, 0, 2, 12, color2)               # front wing
	_px(canvas, o, px, 22, 2, 1, 8, INK)
	_px(canvas, o, px, 5, 5, 3, 2, Color("3a3d44"))        # rear axle
	_px(canvas, o, px, 19, 5, 3, 2, Color("3a3d44"))
	_px(canvas, o, px, 3, 4, 8, 4, color)                  # engine cover
	_px(canvas, o, px, 8, 2, 8, 8, color)                  # sidepods
	_px(canvas, o, px, 8, 2, 8, 1, color.lightened(0.25))
	_px(canvas, o, px, 8, 9, 8, 1, color.darkened(0.3))
	_px(canvas, o, px, 16, 4, 6, 4, color)                 # nose
	_px(canvas, o, px, 22, 5, 3, 2, color)
	_px(canvas, o, px, 11, 4, 4, 4, INK)                   # cockpit
	_px(canvas, o, px, 12, 5, 2, 2, color2)                # helmet
	_px(canvas, o, px, 5, 5, 3, 2, color2)


## Phone icon for the messages button.
static func draw_phone(canvas: CanvasItem, pos: Vector2, px: float, unread: int) -> void:
	_px(canvas, pos, px, 0, 0, 8, 13, INK)
	_px(canvas, pos, px, 1, 1, 6, 9, Color("d8f5e3"))
	_px(canvas, pos, px, 2, 2, 4, 1, Color("2f8f60"))
	_px(canvas, pos, px, 2, 4, 3, 1, Color("2f8f60"))
	_px(canvas, pos, px, 2, 6, 4, 1, Color("2f8f60"))
	_px(canvas, pos, px, 3, 11, 2, 1, Color("8db7a0"))
	if unread > 0:
		_px(canvas, pos, px, 5, -2, 5, 5, Color("c8201e"))
		_px(canvas, pos, px, 7, -1, 1, 3, Color.WHITE)


const EMBLEMS := {
	"mcl": ["....######..", "..##......#.", ".#..........", "#...........", "#...........", ".#.........#", "..##.....##.", "....#####..."],
	"fer": [".##########.", ".##########.", ".####++####.", ".###++++###.", "..##++++##..", "..###++###..", "...######...", ".....##....."],
	"rbr": ["#..........#", "##........##", ".##......##.", ".###....###.", "..########..", "..##.##.##..", "...######...", "....#..#...."],
	"mer": [".....##.....", ".....##.....", "....####....", "############", "############", "....####....", ".....##.....", ".....##....."],
	"amr": ["............", "#..........#", "###......###", "#####..#####", ".##########.", "...######...", ".....##.....", "............"],
	"alp": [".....##.....", "....####....", "...##..##...", "..##....##..", ".##########.", "##........##", "#..........#", "............"],
	"wil": ["#....##....#", "#....##....#", "#....##....#", "#...####...#", "#..##..##..#", "#.##....##.#", "###......###", "##........##"],
	"rcb": ["#..........#", "##........##", ".###....###.", "..########..", "...######...", "............", ".##########.", "............"],
	"has": [".....##.....", "....####....", "...######...", "..###++###..", "..###++###..", "...######...", "....####....", ".....##....."],
	"aud": [".####..####.", "#....##....#", "#....##....#", "#....##....#", "#....##....#", "#....##....#", ".####..####.", "............"],
	"cad": ["############", "#..........#", "#.###..###.#", "#.###..###.#", "#..........#", ".#..####..#.", "..#......#..", "...######..."],
}


## Pixel-art team badge: a 12x8 emblem in the team's colours over its three-letter code.
static func draw_logo(canvas: CanvasItem, rect: Rect2, team: Dictionary, _font: Font = null) -> void:
	var c := Color(str(team.get("color", "#888888")))
	var c2 := Color(str(team.get("color2", "#ffffff")))
	var px := maxf(1.0, floorf(minf(rect.size.x / 16.0, rect.size.y / 16.0)))
	var o := rect.position + (rect.size - Vector2(16, 16) * px) * 0.5
	canvas.draw_rect(Rect2(o, Vector2(16, 16) * px), INK)
	canvas.draw_rect(Rect2(o + Vector2(px, px), Vector2(14, 14) * px), c)
	canvas.draw_rect(Rect2(o + Vector2(px, px), Vector2(14, 1) * px), c.lightened(0.3))
	canvas.draw_rect(Rect2(o + Vector2(px, 10.0 * px), Vector2(14, 5) * px), c.darkened(0.3))
	var rows: Array = EMBLEMS.get(str(team.get("id", "")), EMBLEMS["has"])
	var accent := Color.WHITE if c2.get_luminance() < 0.75 else INK
	for y in rows.size():
		var line: String = rows[y]
		for x in line.length():
			if line[x] != ".":
				canvas.draw_rect(Rect2(o + Vector2(2 + x, 2 + y) * px, Vector2(px, px)), c2 if line[x] == "#" else accent)
	var code := str(team.get("short", ""))
	var fpx := maxf(1.0, floorf(px * 0.5))
	var text_color := Color.WHITE if c.get_luminance() < 0.5 else INK
	PixelFont.draw(canvas, Vector2(o.x + (16.0 * px - PixelFont.width(code, fpx)) * 0.5, o.y + 11.0 * px + (4.0 * px - 7.0 * fpx) * 0.5), code, fpx, text_color)


# ---------------------------------------------------------------- garage props

static func draw_tire_stack(canvas: CanvasItem, pos: Vector2, px: float, band: Color, count: int = 3) -> void:
	for i in count:
		var y := (count - 1 - i) * 5
		_px(canvas, pos, px, 1, y, 10, 5, Color("16181c"))
		_px(canvas, pos, px, 0, y + 1, 12, 3, Color("16181c"))
		_px(canvas, pos, px, 2, y + 1, 8, 1, Color("3a3d44"))
		_px(canvas, pos, px, 3, y + 2, 6, 1, band)
		_px(canvas, pos, px, 1, y + 4, 10, 1, Color("0a0a0a"))


static func draw_toolbox(canvas: CanvasItem, pos: Vector2, px: float, color: Color) -> void:
	_px(canvas, pos, px, 0, 2, 16, 14, INK)
	_px(canvas, pos, px, 1, 3, 14, 12, color)
	_px(canvas, pos, px, 1, 3, 14, 1, color.lightened(0.3))
	for i in 3:
		_px(canvas, pos, px, 2, 5 + i * 3, 12, 2, color.darkened(0.3))
		_px(canvas, pos, px, 6, 6 + i * 3, 4, 1, Color("d7dbe0"))
	_px(canvas, pos, px, 5, 0, 6, 1, Color("d7dbe0"))
	_px(canvas, pos, px, 5, 0, 1, 3, Color("d7dbe0"))
	_px(canvas, pos, px, 10, 0, 1, 3, Color("d7dbe0"))
	_px(canvas, pos, px, 2, 16, 2, 2, INK)
	_px(canvas, pos, px, 12, 16, 2, 2, INK)


static func draw_cone(canvas: CanvasItem, pos: Vector2, px: float) -> void:
	_px(canvas, pos, px, 3, 0, 2, 2, Color("ff7a2e"))
	_px(canvas, pos, px, 2, 2, 4, 2, Color.WHITE)
	_px(canvas, pos, px, 2, 4, 4, 2, Color("ff7a2e"))
	_px(canvas, pos, px, 1, 6, 6, 2, Color.WHITE)
	_px(canvas, pos, px, 0, 8, 8, 2, Color("ff7a2e"))


static func draw_lamp(canvas: CanvasItem, pos: Vector2, px: float) -> void:
	_px(canvas, pos, px, 5, 0, 2, 4, Color("3a3d44"))
	_px(canvas, pos, px, 1, 4, 10, 2, Color("d7dbe0"))
	_px(canvas, pos, px, 0, 6, 12, 1, Color("fff3b0"))
