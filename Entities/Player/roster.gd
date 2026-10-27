class_name Roster
## Who can be played: Humans (team 0) against Skeletons (team 1). Each
## character belongs to one side and carries its own signature kit, which
## can't break and can't be taken by anyone else (see PlayerClass3D's KIT
## section). A character is an index into CHARACTERS (PlayerSlot.character),
## the same on every machine.
##
## Formats with more than two teams (hidden for now, see Players.TEAM_COUNTS)
## draw their rosters from the two sides in turn.

const HUMANS := 0
const SKELETONS := 1

## Each character: name, side, body model, and kit as [main hand, off hand]
## (null = nothing there; a two-handed weapon fills both). For the character
## select lineup (see CharacterStage3D): kit_name, a flourish clip played
## when the character is picked out, and the ready clip it loops after. Paths, loaded
## when needed: preloading weapon scenes here would load them while their
## own scripts (which use PlayerClass3D, which uses this) are still loading.
const CHARACTERS: Array[Dictionary] = [
	{
		"name": "Knight", "side": HUMANS,
		"model": "res://Assets/Characters/Adventurers/Knight.glb",
		"kit": ["res://Items/Weapons/Sword/sword_3d.tscn", "res://Items/Weapons/Shield/shield_3d.tscn"],
		"kit_name": "Sword & Shield",
		"flourish": &"CombatMelee/Melee_1H_Attack_Slice_Diagonal", "ready": &"CombatMelee/Melee_Blocking",
	},
	{
		"name": "Barbarian", "side": HUMANS,
		"model": "res://Assets/Characters/Adventurers/Barbarian.glb",
		"kit": ["res://Items/Weapons/Axe/greataxe_3d.tscn", null],
		"kit_name": "Greataxe",
		"flourish": &"CombatMelee/Melee_2H_Attack_Spin", "ready": &"CombatMelee/Melee_2H_Idle",
	},
	{
		"name": "Mage", "side": HUMANS,
		"model": "res://Assets/Characters/Adventurers/Mage.glb",
		"kit": ["res://Items/Weapons/Staff/wand_3d.tscn", null],
		"kit_name": "Wand",
		"flourish": &"CombatRanged/Ranged_Magic_Spellcasting", "ready": &"General/Idle_B",
	},
	{
		"name": "Rogue", "side": HUMANS,
		"model": "res://Assets/Characters/Adventurers/Rogue.glb",
		"kit": ["res://Items/Weapons/Dagger/dagger_3d.tscn", "res://Items/Weapons/Dagger/dagger_3d.tscn"],
		"kit_name": "Twin Daggers",
		"flourish": &"CombatMelee/Melee_Dualwield_Attack_Slice", "ready": &"CombatMelee/Melee_Unarmed_Idle",
	},
	{
		"name": "Ranger", "side": HUMANS,
		"model": "res://Assets/Characters/Adventurers/Ranger.glb",
		"kit": ["res://Items/Weapons/Bow/bow_3d.tscn", null],
		"kit_name": "Bow",
		"flourish": &"CombatRanged/Ranged_Bow_Release", "ready": &"CombatRanged/Ranged_Bow_Idle",
	},
	{
		"name": "Hooded Rogue", "side": HUMANS,
		"model": "res://Assets/Characters/Adventurers/Rogue_Hooded.glb",
		"kit": ["res://Items/Weapons/Sword/rapier_3d.tscn", "res://Items/Weapons/Dagger/dagger_3d.tscn"],
		"kit_name": "Rapier & Dagger",
		"flourish": &"CombatMelee/Melee_1H_Attack_Stab", "ready": &"General/Idle_B",
	},
	{
		"name": "Skeleton Warrior", "side": SKELETONS,
		"model": "res://Assets/Skeleton/Characters/Skeleton_Warrior.glb",
		"kit": ["res://Items/Weapons/Bone/bone_blade_3d.tscn", "res://Items/Weapons/Bone/bone_shield_3d.tscn"],
		"kit_name": "Bone Blade & Shield",
		"flourish": &"Special/Skeletons_Taunt", "ready": &"CombatMelee/Melee_Blocking",
	},
	{
		"name": "Skeleton Minion", "side": SKELETONS,
		"model": "res://Assets/Skeleton/Characters/Skeleton_Minion.glb",
		"kit": ["res://Items/Weapons/Bone/bone_axe_3d.tscn", null],
		"kit_name": "Bone Axe",
		"flourish": &"Special/Skeletons_Awaken_Standing", "ready": &"Special/Skeletons_Idle",
	},
	{
		"name": "Skeleton Archer", "side": SKELETONS,
		"model": "res://Assets/Skeleton/Characters/Skeleton_Rogue.glb",
		"kit": ["res://Items/Weapons/Bow/bow_3d.tscn", null],
		"kit_name": "Bow",
		"flourish": &"Special/Skeletons_Taunt_Longer", "ready": &"CombatRanged/Ranged_Bow_Idle",
	},
	{
		"name": "Skeleton Mage", "side": SKELETONS,
		"model": "res://Assets/Skeleton/Characters/Skeleton_Mage.glb",
		"kit": ["res://Items/Weapons/Bone/bone_staff_3d.tscn", null],
		"kit_name": "Bone Staff",
		"flourish": &"CombatRanged/Ranged_Magic_Summon", "ready": &"Special/Skeletons_Idle",
	},
]


static func count() -> int:
	return CHARACTERS.size()


static func _entry(character: int) -> Dictionary:
	return CHARACTERS[posmod(character, CHARACTERS.size())]


static func name_of(character: int) -> String:
	return _entry(character).name


## A few words on what it fights with, e.g. "Sword & Shield".
static func kit_name_of(character: int) -> String:
	return _entry(character).kit_name


## Clips ("Library/Clip", see CharacterStage3D) for the select screen.
static func flourish_of(character: int) -> StringName:
	return _entry(character).flourish


static func ready_clip_of(character: int) -> StringName:
	return _entry(character).ready


static func side_of(character: int) -> int:
	return _entry(character).side


static func model_of(character: int) -> PackedScene:
	return load(_entry(character).model)


## [main hand, off hand] scenes; either may be null.
static func kit_of(character: int) -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for path: Variant in _entry(character).kit:
		scenes.append(load(path) if path else null)
	return scenes


## Which side (HUMANS or SKELETONS) plays `team`.
static func side_of_team(team: int) -> int:
	return posmod(team, 2)


## The characters `team` can pick, in roster order.
static func characters_of_team(team: int) -> Array[int]:
	var found: Array[int] = []
	for character: int in CHARACTERS.size():
		if CHARACTERS[character].side == side_of_team(team):
			found.append(character)
	return found


static func fits_team(character: int, team: int) -> bool:
	return characters_of_team(team).has(posmod(character, CHARACTERS.size()))


## `team`'s nth character (wrapping), e.g. to keep a player's place in the
## list when they switch sides.
static func nth_of_team(team: int, n: int) -> int:
	var choices: Array[int] = characters_of_team(team)
	return choices[posmod(n, choices.size())]


## Where `character` sits in its own side's list (0 if it isn't on `team`).
static func rank_in_team(character: int, team: int) -> int:
	return maxi(characters_of_team(team).find(posmod(character, CHARACTERS.size())), 0)


## `character` if `team` can play it, else the one in the same place on
## `team`'s list.
static func for_team(character: int, team: int) -> int:
	if fits_team(character, team):
		return posmod(character, CHARACTERS.size())
	return nth_of_team(team, rank_in_team(character, 1 - side_of_team(team)))


## The next (step 1) or previous (step -1) character on `team` after `character`.
static func step(character: int, team: int, step_by: int) -> int:
	return nth_of_team(team, rank_in_team(character, team) + step_by)
