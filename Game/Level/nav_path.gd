class_name NavPath
## Steering for anything that walks itself somewhere (bots, the walk to the
## altar between rounds): which way to head to reach a point, following the
## level's navigation mesh around walls when it has one, and straight there
## when it doesn't (e.g. the open soccer field).
##
## Each walker sticks to the route it picked: two ways round that are about
## as long (say, either door out of the arena) would otherwise swap back and
## forth every step and leave it dithering in place.

## How far along the path the next point must be before we head for it, so
## we don't turn back toward a corner we're already standing on.
const MIN_STEP := 0.75
## How often (seconds) a walker looks for a better route to the same target.
const REPLAN_TIME := 0.5
## A new route has to be this much shorter (m) to be worth switching to.
const SWITCH_MARGIN := 3.0
## Further than this (m) off our route (knocked away, say) and we take
## whatever route is best from where we are now.
const STRAY_DISTANCE := 2.5
## The target moved this far (m): plan afresh.
const RETARGET_DISTANCE := 1.0

## One walker's chosen route.
class Plan:
	var target: Vector3
	var points: PackedVector3Array
	## Index of the corner we're heading for.
	var next: int = 0
	var replan_msec: int = 0

## Walker instance id -> its Plan.
static var _plans: Dictionary = {}


## Flat (y = 0) unit direction for `walker` to head in to reach `target`.
static func direction(walker: Node3D, target: Vector3) -> Vector3:
	var from: Vector3 = walker.global_position
	var straight: Vector3 = _flat(target - from).normalized()
	var map: RID = walker.get_world_3d().navigation_map
	if NavigationServer3D.map_get_regions(map).is_empty():
		return straight

	var id: int = walker.get_instance_id()
	var plan: Plan = _plans.get(id)
	var now: int = Time.get_ticks_msec()
	var retarget: bool = plan == null or plan.target.distance_to(target) > RETARGET_DISTANCE
	if retarget or now >= plan.replan_msec:
		var fresh: PackedVector3Array = NavigationServer3D.map_get_path(map, from, target, true)
		if retarget or _strayed(from, plan) \
				or _length(from, fresh, 0) < _length(from, plan.points, plan.next) - SWITCH_MARGIN:
			if plan == null:
				_forget_departed()
				plan = Plan.new()
				_plans[id] = plan
			plan.target = target
			plan.points = fresh
			plan.next = 0
		plan.replan_msec = now + int(REPLAN_TIME * 1000.0)

	_advance(from, plan)
	if plan.next >= plan.points.size():
		return straight
	return _flat(plan.points[plan.next] - from).normalized()


## Skip corners we've reached or already walked past.
static func _advance(from: Vector3, plan: Plan) -> void:
	while plan.next < plan.points.size():
		var corner: Vector3 = plan.points[plan.next]
		if _flat(corner - from).length() <= MIN_STEP:
			plan.next += 1
			continue
		if plan.next + 1 < plan.points.size():
			var ahead: Vector3 = _flat(plan.points[plan.next + 1] - corner)
			if ahead.length() > 0.01 and _flat(from - corner).dot(ahead) > 0.0:
				plan.next += 1  # Past it, on the way to the one after
				continue
		break


## Whether `from` is too far off the leg of `plan` we're walking.
static func _strayed(from: Vector3, plan: Plan) -> bool:
	if plan.next >= plan.points.size():
		return true
	var to: Vector3 = _flat(plan.points[plan.next])
	var start: Vector3 = _flat(plan.points[plan.next - 1]) if plan.next > 0 else to
	var here: Vector3 = _flat(from)
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(here, start, to)
	return here.distance_to(closest) > STRAY_DISTANCE


## Walking distance from `from` along `points` starting at corner `start`.
static func _length(from: Vector3, points: PackedVector3Array, start: int) -> float:
	if start >= points.size():
		return INF
	var total: float = _flat(points[start] - from).length()
	for i in range(start + 1, points.size()):
		total += _flat(points[i] - points[i - 1]).length()
	return total


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Drop plans of walkers that no longer exist.
static func _forget_departed() -> void:
	if _plans.size() < 32:
		return
	for id: int in _plans.keys():
		if not is_instance_id_valid(id):
			_plans.erase(id)
