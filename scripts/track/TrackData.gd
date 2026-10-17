class_name TrackData
extends RefCounted
## Geometry and rules of one circuit, built from a list of control points.
## Nothing here assumes a road course or a particular vehicle type: an oval is just
## another control-point file.

const PPM := VehiclePhysicsConfig.PPM
const SAMPLE_SPACING := 4.0          # metres between centreline samples
const CURB_CURVATURE := 0.0065       # corners tighter than ~150 m radius get curbs
const GRAVEL_CURVATURE := 0.014      # corners tighter than ~70 m radius get gravel outside
const CORNER_CURVATURE := 0.0042
const LEGAL_MARGIN := 2.2            # metres beyond the curb that still counts as "on track"
## Width of the car as drawn (outer edge of the rear wheels), metres.
const CAR_WIDTH := 2.0
## Official FIA permanent circuit width : 2026 F1 car width = 6.32 : 1.
const WIDTH_RATIO := 6.32
## A few sections squeeze down to this many car widths (tight corners away from the pits).
const NARROW_RATIO := 4.6
## Metres over which a narrow section blends in and out.
const NARROW_BLEND := 60.0

var id := ""
var display_name := ""
## Standard half width: half of 6.32 car widths. `widths` holds the half width at every sample.
var half_width := CAR_WIDTH * WIDTH_RATIO * 0.5
var widths := PackedFloat32Array()
var narrow_sections: Array[Vector2] = []     # progress from / to, metres
var curb_width := 1.6
var runoff := 13.0
var curve := Curve2D.new()           # centreline in pixels (shown through a Path2D)
var count := 0
var spacing := SAMPLE_SPACING
var length := 0.0                    # metres

var points := PackedVector2Array()   # pixels
var tangents := PackedVector2Array()
var normals := PackedVector2Array()  # points to the right of travel
var curvature := PackedFloat32Array()  # 1/m, positive = right-hand corner
var curb_left := PackedByteArray()
var curb_right := PackedByteArray()
var gravel_left := PackedByteArray()
var gravel_right := PackedByteArray()
var barrier_left := PackedFloat32Array()   # barrier offset from centreline, metres
var barrier_right := PackedFloat32Array()
var corners: Array[Dictionary] = []
var sector_bounds := PackedFloat32Array()  # progress (m) where sectors 1 and 2 end
var checkpoints := PackedFloat32Array()    # progress (m) of every gate, gate 0 = start line
var bounds := Rect2()
## Pit lane: an asphalt apron on the left of the start straight with one service box.
const PIT_WIDTH := 8.5
var pit_start := 40.0
var pit_end := 300.0
var pit_box := 170.0


static func load_track(path: String) -> TrackData:
	var data: Variant = SaveManager.load_json(path)
	var track := TrackData.new()
	if data is Dictionary:
		track._build(data)
	return track


func _build(data: Dictionary) -> void:
	id = data.get("id", "track")
	display_name = data.get("name", "Circuit")
	# Every real circuit is 6.32 car widths wide; a test track can keep its own width.
	half_width = float(data.get("half_width", 7.0)) if data.get("fixed_width", false) else CAR_WIDTH * WIDTH_RATIO * 0.5
	curb_width = float(data.get("curb_width", 1.6))
	runoff = float(data.get("runoff", 13.0))
	var raw: Array = data.get("control_points", [])
	var ctrl := PackedVector2Array()
	for p: Array in raw:
		ctrl.append(Vector2(float(p[0]), float(p[1])) * PPM * float(data.get("scale", 1.0)))
	_build_curve(ctrl)
	_sample(float(data.get("start_offset_m", 0.0)) * PPM)
	var pit: Dictionary = data.get("pit", {})
	pit_start = float(pit.get("start", 40.0))
	pit_end = float(pit.get("end", 300.0))
	pit_box = float(pit.get("box", 170.0))
	_find_corners()
	_compute_widths(data)
	_classify()
	var fractions: Array = data.get("sector_fractions", [0.333, 0.666])
	sector_bounds = PackedFloat32Array([float(fractions[0]) * length, float(fractions[1]) * length])
	var gates := int(data.get("checkpoint_count", 12))
	checkpoints.resize(gates)
	for i in gates:
		checkpoints[i] = length * i / gates


## Smooth closed spline through the control points. Each point's tangent is parallel to the
## chord between its neighbours and scaled by the adjacent segment length, which avoids the
## overshoot plain Catmull-Rom shows on unevenly spaced points.
func _build_curve(ctrl: PackedVector2Array) -> void:
	curve = Curve2D.new()
	curve.bake_interval = 4.0
	var n := ctrl.size()
	for i in n + 1:
		var p := ctrl[i % n]
		var prev := ctrl[(i - 1 + n) % n]
		var next := ctrl[(i + 1) % n]
		var dir := (next - prev).normalized()
		curve.add_point(p, -dir * p.distance_to(prev) * 0.36, dir * p.distance_to(next) * 0.36)


func _sample(start_offset_px: float) -> void:
	var total := curve.get_baked_length()
	count = int(round(total / (SAMPLE_SPACING * PPM)))
	spacing = total / count / PPM
	length = total / PPM
	points.resize(count)
	tangents.resize(count)
	normals.resize(count)
	curvature.resize(count)
	for i in count:
		points[i] = curve.sample_baked(fposmod(start_offset_px + i * spacing * PPM, total), true)
	for i in count:
		var t := (points[(i + 1) % count] - points[(i - 1 + count) % count]).normalized()
		tangents[i] = t
		normals[i] = Vector2(-t.y, t.x)
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in count:
		raw[i] = tangents[(i - 1 + count) % count].angle_to(tangents[(i + 1) % count]) / (2.0 * spacing)
	curvature = smooth(raw, 2)
	bounds = Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)


## Circular moving average.
static func smooth(values: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := values.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += values[(i + k + n) % n]
		out[i] = sum / (2 * radius + 1)
	return out


func _classify() -> void:
	for arr: PackedByteArray in [curb_left, curb_right, gravel_left, gravel_right]:
		arr.resize(count)
	curb_left.resize(count); curb_right.resize(count); gravel_left.resize(count); gravel_right.resize(count)
	curb_left.fill(0); curb_right.fill(0); gravel_left.fill(0); gravel_right.fill(0)
	var wide := smooth(curvature, 4)
	for i in count:
		var k := wide[i]
		if absf(k) > CURB_CURVATURE:
			for o in range(-3, 6):
				var j := (i + o + count) % count
				curb_left[j] = 1
				curb_right[j] = 1
		if absf(k) > GRAVEL_CURVATURE:
			# Gravel sits on the outside, reaching back along the braking zone.
			for o in range(-26, 9):
				var j := (i + o + count) % count
				if k > 0.0:
					gravel_left[j] = 1
				else:
					gravel_right[j] = 1
	# Barriers follow the track at a fixed offset, pulled in on the inside of tight corners
	# so the offset line never folds over itself.
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(count)
	right.resize(count)
	var very_wide := smooth(curvature, 8)
	for i in count:
		var k := very_wide[i]
		var radius := 1.0 / maxf(absf(k), 0.0001)
		var base := widths[i] + curb_width + runoff
		var inside := maxf(widths[i] + curb_width + 1.5, minf(base, radius * 0.62))
		left[i] = inside if k < 0.0 else base
		right[i] = inside if k > 0.0 else base
	barrier_left = smooth(smooth(left, 5), 5)
	barrier_right = smooth(smooth(right, 5), 5)
	for i in count:
		barrier_left[i] = minf(barrier_left[i], left[i] + 2.0)
		barrier_right[i] = minf(barrier_right[i], right[i] + 2.0)


## The track is 6.32 car widths everywhere except a few narrow sections: the tightest corners
## that are clear of the pit lane and the grid (or the sections a track file lists in "narrow").
func _compute_widths(data: Dictionary) -> void:
	widths.resize(count)
	widths.fill(half_width)
	narrow_sections.clear()
	if data.get("fixed_width", false):
		return
	var listed: Array = data.get("narrow", [])
	for pair: Array in listed:
		narrow_sections.append(Vector2(float(pair[0]), float(pair[1])))
	if listed.is_empty():
		var tight := corners.duplicate()
		tight.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["radius"]) < float(b["radius"]))
		var wanted := 3 if length > 5000.0 else 2
		for c: Dictionary in tight:
			var from := float(c["start"]) - 20.0
			var to := float(c["end"])
			var clear_of_pits := from > pit_end + 120.0 and to < length - 260.0
			var apart := true
			for other: Vector2 in narrow_sections:
				apart = apart and (to < other.x - 300.0 or from > other.y + 300.0)
			if clear_of_pits and apart and float(c["radius"]) < 120.0:
				narrow_sections.append(Vector2(from, to))
			if narrow_sections.size() >= wanted:
				break
	var narrow := CAR_WIDTH * NARROW_RATIO * 0.5
	for i in count:
		var p := i * spacing
		var squeeze := 0.0
		for sec: Vector2 in narrow_sections:
			var into := minf(p - (sec.x - NARROW_BLEND), (sec.y + NARROW_BLEND) - p)
			squeeze = maxf(squeeze, smoothstep(0.0, NARROW_BLEND, into))
		widths[i] = lerpf(half_width, narrow, squeeze)


## Half width of the track at sample `index` (metres).
func half_width_at(index: int) -> float:
	return widths[posmod(index, count)] if widths.size() == count else half_width


## "12.6 M WIDE  ·  6.32 CAR WIDTHS  ·  NARROWS TO 9.2 M" for the screens that show the track.
func width_text() -> String:
	var text := "%.1f M WIDE  ·  %.2f CAR WIDTHS" % [half_width * 2.0, half_width * 2.0 / CAR_WIDTH]
	if narrowest() < half_width - 0.1:
		text += "  ·  NARROWS TO %.1f M" % (narrowest() * 2.0)
	return text


## Narrowest half width anywhere on the lap.
func narrowest() -> float:
	var low := half_width
	for w in widths:
		low = minf(low, w)
	return low


func _find_corners() -> void:
	corners.clear()
	var wide := smooth(curvature, 3)
	var i := 0
	var groups: Array[Vector2i] = []
	while i < count:
		if absf(wide[i]) > CORNER_CURVATURE:
			var start := i
			var direction := signf(wide[i])
			while i < count and absf(wide[i]) > CORNER_CURVATURE and signf(wide[i]) == direction:
				i += 1
			if (i - start) * spacing >= 20.0:
				groups.append(Vector2i(start, i - 1))
		else:
			i += 1
	for g in groups:
		var apex := g.x
		for j in range(g.x, g.y + 1):
			if absf(wide[j]) > absf(wide[apex]):
				apex = j
		corners.append({
			"name": "TURN %d" % (corners.size() + 1),
			"start": maxf(0.0, (g.x - 14) * spacing),
			"apex": apex * spacing,
			"end": minf(length - 1.0, (g.y + 10) * spacing),
			"direction": signf(wide[apex]),
			"radius": 1.0 / absf(wide[apex]),
		})


# ---------------------------------------------------------------- queries

func wrap_index(i: int) -> int:
	return posmod(i, count)


func index_at(progress: float) -> int:
	return posmod(int(progress / spacing), count)


## Nearest centreline sample. With a hint only a small window is searched (cheap per-frame path).
func nearest_index(pos: Vector2, hint: int = -1) -> int:
	var best := 0
	var best_d := INF
	if hint >= 0:
		for o in range(-8, 14):
			var j := posmod(hint + o, count)
			var d := pos.distance_squared_to(points[j])
			if d < best_d:
				best_d = d
				best = j
		if best_d < pow(45.0 * PPM, 2.0):
			return best
	best_d = INF
	for j in range(0, count, 3):
		var d := pos.distance_squared_to(points[j])
		if d < best_d:
			best_d = d
			best = j
	return nearest_index(pos, best) if hint != best else best


func lateral_offset(pos: Vector2, index: int) -> float:
	return (pos - points[index]).dot(normals[index]) / PPM


func progress_at(pos: Vector2, index: int) -> float:
	return fposmod(index * spacing + (pos - points[index]).dot(tangents[index]) / PPM, length)


func in_pit_lane(progress: float, lateral: float) -> bool:
	return progress >= pit_start and progress <= pit_end and lateral < 0.0 and lateral >= -(half_width + PIT_WIDTH)


func in_pit_box(progress: float, lateral: float) -> bool:
	return absf(progress - pit_box) < 7.0 and lateral <= -(half_width + 1.0) and lateral >= -(half_width + PIT_WIDTH)


func surface_at(lateral: float, index: int) -> int:
	var d := absf(lateral)
	if lateral < 0.0 and d <= half_width + PIT_WIDTH and index * spacing >= pit_start and index * spacing <= pit_end:
		return VehiclePhysicsConfig.Surface.ASPHALT
	var w := half_width_at(index)
	if d <= w:
		return VehiclePhysicsConfig.Surface.ASPHALT
	var right := lateral > 0.0
	if d <= w + curb_width and (curb_right[index] if right else curb_left[index]) == 1:
		return VehiclePhysicsConfig.Surface.CURB
	if (gravel_right[index] if right else gravel_left[index]) == 1 and d > w + 1.0:
		return VehiclePhysicsConfig.Surface.GRAVEL
	return VehiclePhysicsConfig.Surface.GRASS


func is_legal(lateral: float, index: int = -1) -> bool:
	return absf(lateral) <= (half_width_at(index) if index >= 0 else half_width) + curb_width + LEGAL_MARGIN


func position_at(progress: float, lateral: float = 0.0) -> Vector2:
	var f := fposmod(progress, length) / spacing
	var i := int(f) % count
	var j := (i + 1) % count
	var t := f - int(f)
	return points[i].lerp(points[j], t) + normals[i].lerp(normals[j], t).normalized() * lateral * PPM


func heading_at(progress: float) -> float:
	return tangents[index_at(progress)].angle()


func sector_of(progress: float) -> int:
	if progress < sector_bounds[0]:
		return 0
	return 1 if progress < sector_bounds[1] else 2


## Signed shortest distance along the lap from `from` to `to` (metres).
func progress_delta(from: float, to: float) -> float:
	var d := fposmod(to - from, length)
	return d - length if d > length * 0.5 else d


func grid_slot(slot: int) -> Dictionary:
	var progress := length - 16.0 - slot * 8.5
	var lateral := -2.7 if slot % 2 == 0 else 2.7
	return {"position": position_at(progress, lateral), "rotation": heading_at(progress), "progress": progress}
