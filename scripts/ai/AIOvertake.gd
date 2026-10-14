class_name AIOvertake
extends RefCounted
## Basic overtaking: when a faster AI closes on a car in its lane it picks one side,
## commits for a while, then drifts back to the racing line.

const LANE_WIDTH := 2.5
const PASS_OFFSET := 3.1
const MIN_COMMIT_TIME := 1.6
const RETURN_RATE := 2.2          # m/s the offset relaxes at
const MOVE_RATE := 3.6

var offset := 0.0                 # current lateral offset from the racing line (m)
var speed_cap := INF              # set when stuck behind someone
var passing := false

var _side := 0.0
var _commit := 0.0


func update(delta: float, me: VehicleController, others: Array, track: TrackData, line_offset: float, aggression: float) -> void:
	speed_cap = INF
	_commit = maxf(0.0, _commit - delta)
	var look := 14.0 + me.speed * (0.35 + 0.35 * aggression)
	var ahead: VehicleController = null
	var ahead_gap := INF
	var beside_push := 0.0
	for other: VehicleController in others:
		if other == me:
			continue
		var gap := track.progress_delta(me.progress, other.progress)
		var side_gap := other.lateral - me.lateral
		if gap > 0.5 and gap < look and gap < ahead_gap and absf(side_gap) < LANE_WIDTH + 1.2:
			ahead = other
			ahead_gap = gap
		elif absf(gap) <= 5.5 and absf(side_gap) < LANE_WIDTH:
			# Someone alongside: give them room.
			beside_push = -signf(side_gap) * (LANE_WIDTH - absf(side_gap))
	var target := 0.0
	if ahead != null:
		var closing := me.speed - ahead.speed
		var wants_pass := closing > lerpf(2.0, 0.3, aggression) or ahead_gap < 9.0
		if wants_pass and _commit <= 0.0 and not passing:
			# Go for the side with more room.
			_side = 1.0 if (track.half_width - ahead.lateral) > (track.half_width + ahead.lateral) else -1.0
			_commit = MIN_COMMIT_TIME
			passing = true
		if passing:
			var limit := track.half_width - 1.3
			var desired := clampf(ahead.lateral + _side * PASS_OFFSET, -limit, limit)
			target = desired - line_offset
			if absf(desired - ahead.lateral) < LANE_WIDTH * 0.8:
				# No room on that side after all: tuck in behind.
				speed_cap = ahead.speed + 0.5
		if ahead_gap < 7.5 and absf(ahead.lateral - me.lateral) < 1.9:
			speed_cap = minf(speed_cap, ahead.speed + (1.0 if ahead_gap > 5.5 else -1.5))
	elif _commit <= 0.0:
		passing = false
	target += beside_push
	var rate := MOVE_RATE if absf(target) > absf(offset) else RETURN_RATE
	offset = move_toward(offset, target, rate * delta)
