class_name WeaponCombo3D extends Resource
## A few beats played one after another, each striking with one hand or
## both (see WeaponComboStep3D): how a WeaponMove3D plays out over more than
## one strike, e.g. the dagger's rapid stabs or the greataxe's spin. See
## PlayerCombo3D.

## Played in order (see WeaponComboStep3D.delay).
@export var steps: Array[WeaponComboStep3D] = []
## Stamina, times what the same swings would cost one at a time.
@export var stamina_scale: float = 1.0
