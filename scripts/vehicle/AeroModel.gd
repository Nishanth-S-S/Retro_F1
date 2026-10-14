class_name AeroModel
extends RefCounted
## Speed-squared downforce and drag. Front and rear downforce are tracked separately
## so aero balance shifts handling at speed.

var front_area := 1.0        # ClA acting on the front axle (m^2)
var rear_area := 1.2         # ClA acting on the rear axle (m^2)
var drag_area := 0.9         # CdA (m^2)
var air_density := 1.225

var front_downforce := 0.0
var rear_downforce := 0.0
var drag := 0.0
## DRS: the rear wing flap is open - much less drag, a little less rear downforce.
var drs := false


func configure(stats: CarStats, config: VehiclePhysicsConfig) -> void:
	front_area = stats.front_downforce_area
	rear_area = stats.rear_downforce_area
	drag_area = stats.drag_area
	air_density = config.air_density


func update(speed: float) -> void:
	var q := 0.5 * air_density * speed * speed
	front_downforce = q * front_area
	rear_downforce = q * rear_area
	drag = q * drag_area * (0.75 if drs else 1.0)
	if drs:
		rear_downforce *= 0.85
