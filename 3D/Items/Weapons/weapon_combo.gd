class_name WeaponCombo3D extends Resource
## A special attack on the Off-hand button (see PlayerClass3D._start_special):
## a few beats, each striking with one hand or both. With a one-handed weapon
## in each hand, find_for() picks it; with nothing in the off hand, it's the
## main weapon's alt_attack (its beats strike with that weapon only).

const COMBOS_DIR := "res://3D/Items/Weapons/Combos/"
## Two compatible weapons whose main one has no pair_combo: both swing at once.
const BOTH_AT_ONCE := COMBOS_DIR + "both_at_once.tres"
## Any other pair: the off hand's weapon strikes first, then the main's.
const OFF_THEN_MAIN := COMBOS_DIR + "off_then_main.tres"

## Played in order (see WeaponComboStep3D.delay).
@export var steps: Array[WeaponComboStep3D] = []
## Stamina, times what the same swings would cost one at a time.
@export var stamina_scale: float = 1.0


## The combo for `off` (left hand) and `main` (right hand). A compatible pair
## (see Weapon3D.is_compatible_with) plays the main weapon's pair_combo;
## anything else, the off hand leads and the main follows.
static func find_for(off: Weapon3D, main: Weapon3D) -> WeaponCombo3D:
	if main.is_compatible_with(off):
		return main.pair_combo if main.pair_combo else load(BOTH_AT_ONCE)
	return load(OFF_THEN_MAIN)
