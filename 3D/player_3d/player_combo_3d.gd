class_name PlayerCombo3D extends RefCounted
## Plays out a player's dual-wield special or alt attack (see WeaponCombo3D)
## once PlayerClass3D._start_special has paid for it: strikes each beat as
## it comes due, and turns the body through a spinning one. It stops if
## either weapon leaves its hand.

var _player: PlayerClass3D
## The beats still to come, and the time to the next.
var _steps: Array[WeaponComboStep3D] = []
var _wait: float = 0.0
## The weapons it's for.
var _left_weapon: Weapon3D = null
var _right_weapon: Weapon3D = null
## Which hand the combo's MAIN beats strike with (an alt attack with the
## weapon in the left hand), the other being OFF.
var _main_is_left: bool = false
## A spinning beat (see WeaponComboStep3D.spin_turns): time left of it, out
## of _spin_total, turning the body _spin_turns times round.
var _spin_time: float = 0.0
var _spin_total: float = 0.0
var _spin_turns: float = 0.0


func _init(player: PlayerClass3D) -> void:
	_player = player


func is_running() -> bool:
	return not _steps.is_empty()


## Start `combo`'s beats, its MAIN ones in the left hand if `main_is_left`.
## The first goes off at once if it has no delay.
func start(combo: WeaponCombo3D, main_is_left: bool) -> void:
	_main_is_left = main_is_left
	_left_weapon = _player.left_arm.weapon
	_right_weapon = _player.right_arm.weapon
	_steps = combo.steps.duplicate()
	_wait = _steps[0].delay
	update(0.0)


## Drop the beats still to come, and any spin.
func cancel() -> void:
	_steps.clear()
	_spin_time = 0.0


## Which arms strike on `step` when MAIN is the left hand if `main_is_left`:
## those of its hands that hold a weapon, left first.
func arms_for(step: WeaponComboStep3D, main_is_left: bool) -> Array[PlayerArm3D]:
	var picked: Array[PlayerArm3D] = [_player.left_arm, _player.right_arm]
	match step.hand:
		WeaponComboStep3D.Hand.OFF:
			picked = [_player.arm_of(not main_is_left)]
		WeaponComboStep3D.Hand.MAIN:
			picked = [_player.arm_of(main_is_left)]
	return picked.filter(func(a: PlayerArm3D) -> bool: return a.weapon != null)


func update(delta: float) -> void:
	_spin_time = max(_spin_time - delta, 0.0)
	if _steps.is_empty():
		return
	if _player.left_arm.weapon != _left_weapon or _player.right_arm.weapon != _right_weapon:
		_steps.clear()
		return
	_wait -= delta
	while not _steps.is_empty() and _wait <= 0.0:
		var step: WeaponComboStep3D = _steps.pop_front()
		var longest: float = 0.0
		for arm: PlayerArm3D in arms_for(step, _main_is_left):
			longest = maxf(longest, _player.strike(arm, step))
		if step.spin_turns != 0.0:
			_spin_total = longest
			_spin_time = longest
			_spin_turns = step.spin_turns
		if not _steps.is_empty():
			_wait += _steps[0].delay


## How far round (radians) a spinning beat has turned the body: quick to get
## going, easing off at the end.
func spin_angle() -> float:
	if _spin_time <= 0.0 or _spin_total <= 0.0:
		return 0.0
	var t: float = 1.0 - _spin_time / _spin_total
	return _spin_turns * TAU * smoothstep(0.0, 1.0, t)
