class_name WeaponComboStep3D extends Resource
## One beat of a WeaponCombo3D: which hand(s) strike, when, and how.

enum Hand {
	OFF,  ## The off hand's weapon (the left, dual wielding)
	MAIN,  ## The main hand's weapon (the right, dual wielding)
	BOTH,  ## Both at once
}
## Which hand(s) strike on this beat.
@export var hand: Hand = Hand.BOTH
## Seconds after the previous beat (after the button press, for the first).
@export var delay: float = 0.0
## Clip each arm plays (see PlayerVisual3D.CLIP_KEYS). Empty = that weapon's
## own swing clip for that hand.
@export var main_clip: StringName = &""
@export var off_clip: StringName = &""
## Times each weapon's own swing_duration.
@export var duration_scale: float = 1.0
## Times each weapon's own damage.
@export var damage_scale: float = 1.0
## Times the step forward a normal swing takes. 0 = stand still.
@export var lunge_scale: float = 1.0
## Whole turns the body spins through over this beat, arms held out so the
## weapons hit all the way round. Negative spins the other way. 0 = none.
@export var spin_turns: float = 0.0
## A ranged weapon swings as a club on this beat instead of firing.
@export var melee: bool = false
