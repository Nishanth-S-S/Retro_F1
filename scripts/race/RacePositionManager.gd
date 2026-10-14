class_name RacePositionManager
extends RefCounted
## Orders cars by laps completed + normalised progress around the lap.
## Cars that have taken the flag are locked in finishing order.

var order: Array[VehicleController] = []
var _positions: Dictionary = {}


func update(cars: Array[VehicleController], timers: Array[LapTimer], track_length: float) -> void:
	var scored: Array = []
	for i in cars.size():
		var timer := timers[i]
		var score: float
		if timer.finish_time >= 0.0:
			score = 1.0e6 - timer.finish_time          # earlier finish = higher score
		else:
			# Before the first start-line crossing the car is on its "lap zero".
			score = float(timer.laps_completed) + cars[i].progress / track_length - (0.0 if timer.started else 1.0)
		scored.append([score, cars[i]])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	order.clear()
	_positions.clear()
	for i in scored.size():
		order.append(scored[i][1])
		_positions[scored[i][1]] = i + 1


func position_of(car: VehicleController) -> int:
	return _positions.get(car, 1)
