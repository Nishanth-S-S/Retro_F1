class_name SkidMarks
extends Node2D
## Bounded skid mark renderer. A fixed pool of Line2D nodes is recycled round-robin,
## so no nodes are ever created or freed while driving.

const POOL_SIZE := 72
const MAX_POINTS := 36
const MIN_SPACING := 7.0

var _lines: Array[Line2D] = []
var _active: Dictionary = {}      # wheel key -> pool index
var _touched: Dictionary = {}
var _next := 0


func _ready() -> void:
	z_index = -5
	for i in POOL_SIZE:
		var line := Line2D.new()
		line.width = 3.2
		line.default_color = Color(0.04, 0.04, 0.05, 0.3)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		add_child(line)
		_lines.append(line)


## Call every physics frame for each wheel that is currently sliding.
func mark(key: int, world_pos: Vector2) -> void:
	_touched[key] = true
	var line: Line2D
	if _active.has(key):
		line = _lines[_active[key]]
		if line.get_point_count() >= MAX_POINTS:
			var last := line.get_point_position(line.get_point_count() - 1)
			line = _take(key)
			line.add_point(last)
	else:
		line = _take(key)
	var n := line.get_point_count()
	if n == 0 or line.get_point_position(n - 1).distance_squared_to(world_pos) > MIN_SPACING * MIN_SPACING:
		line.add_point(world_pos)


func _take(key: int) -> Line2D:
	# Skip pool entries still being drawn by another wheel.
	for attempt in POOL_SIZE:
		var idx := _next
		_next = (_next + 1) % POOL_SIZE
		if not _active.values().has(idx):
			_lines[idx].clear_points()
			_active[key] = idx
			return _lines[idx]
	return _lines[0]


func _physics_process(_delta: float) -> void:
	# Wheels that stopped sliding release their line (it stays visible until recycled).
	for key: int in _active.keys():
		if not _touched.has(key):
			_active.erase(key)
	_touched.clear()
