class_name BotBench extends Node
## A repeatable bot match for checking performance: seats a full match of
## bots, plays the lobby's map for a while, and prints how long frames took,
## how many draw calls and triangles they drew, the node count (a leak shows
## as one that keeps climbing), and the score. Frames over HITCH_MS are
## listed with when they happened, since a stutter matters more than an
## average.
##
## Run it windowed to measure rendering (vsync is turned off for it):
##   godot --path . --fixed-fps 60 res://Tools/Bench/bot_bench.tscn -- --secs=90 --seed=1
## or headless for game logic only (much faster than real time):
##   godot --headless --path . --fixed-fps 60 res://Tools/Bench/bot_bench.tscn -- --secs=600
## Options: --secs=N (game seconds, default 90), --seed=N, --score=N (Score
## to Win, default MAX_SCORE so the match runs the whole time).

## Seconds of game between progress lines.
const REPORT_EVERY := 15.0
## A frame longer than this (ms) is a hitch, listed at the end.
const HITCH_MS := 50.0
## The opening seconds (loading the level) don't count as hitches.
const WARMUP := 4.0
const MAX_SCORE := Players.MAX_SCORE_TO_WIN

var duration: float = 90.0
var _time: float = 0.0
var _since_report: float = 0.0
var _last_usec: int = 0
var _frame_ms: Array[float] = []
var _draw_calls: Array[float] = []
var _triangles: Array[float] = []
## [ms, game time] for each hitch.
var _hitches: Array[Vector2] = []


## The scene's own copy seats the bots and starts the match; a second copy
## on the root, which survives the change of scene, does the measuring.
func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene != self:
		_start_measuring()
		return
	var probe := BotBench.new()
	var score: int = MAX_SCORE
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--secs="):
			probe.duration = arg.trim_prefix("--secs=").to_float()
		elif arg.begins_with("--seed="):
			seed(arg.trim_prefix("--seed=").to_int())
		elif arg.begins_with("--score="):
			score = arg.trim_prefix("--score=").to_int()
	Players.leave_all()
	Players.fill_with_bots = true
	Players.set_score_to_win(score)
	Players.fill_bots()
	get_tree().root.add_child.call_deferred(probe)
	get_tree().change_scene_to_file.call_deferred(MatchMap.scene_of(Players.map))


func _start_measuring() -> void:
	process_priority = 1000  # Last in the frame
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("Bench: %d bots, %.0fs" % [Players.slots.size(), duration])


func _process(delta: float) -> void:
	if get_tree().current_scene == self:
		return  # The copy that starts the match
	_time += delta
	var now: int = Time.get_ticks_usec()
	if _last_usec > 0:
		var ms: float = (now - _last_usec) / 1000.0
		_frame_ms.append(ms)
		if _time > WARMUP and ms > HITCH_MS:
			_hitches.append(Vector2(ms, _time))
	_last_usec = now
	_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_triangles.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_since_report += delta
	if _since_report >= REPORT_EVERY:
		_since_report = 0.0
		_report()
	if _time >= duration:
		_report()
		_finish()
		get_tree().quit()


func _report() -> void:
	var frames: Vector3 = _summary(_frame_ms)
	var game: Game3D_Class = Global.Game3D
	print("[%5.0fs] frame ms avg %.2f p95 %.2f max %.1f | draws %.0f tris %.0fk | nodes %d orphans %d%s" % [
		_time, frames.x, frames.y, frames.z, _summary(_draw_calls).x, _summary(_triangles).x / 1000.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		" | kills %s base hp %s" % [game.kills, game.base_hp] if is_instance_valid(game) else ""])
	_frame_ms.clear()
	_draw_calls.clear()
	_triangles.clear()


func _finish() -> void:
	_hitches.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var listed: PackedStringArray = []
	for hitch: Vector2 in _hitches.slice(0, 10):
		listed.append("%.0fms at %.1fs" % [hitch.x, hitch.y])
	print("Hitches over %.0fms: %d  %s" % [HITCH_MS, _hitches.size(), ", ".join(listed)])


## (average, 95th percentile, max) of `values`.
func _summary(values: Array[float]) -> Vector3:
	if values.is_empty():
		return Vector3.ZERO
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted:
		total += value
	return Vector3(total / sorted.size(), sorted[int(sorted.size() * 0.95)], sorted[-1])
