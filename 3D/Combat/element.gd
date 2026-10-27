class_name Element
## The elements, shared by everything that has one: patches on the floor
## (GroundPatch3D), a slime boss (SlimeElement), bombs (Bomb3D), and
## whatever else gets one. What happens when two of them meet is
## ElementReactions'. Each of the older lists maps onto this one (see the
## of_* functions); new things with an element should use it directly
## rather than add a list of their own.

enum Kind {
	FIRE,       ## Burns; sets off poison, melts ice
	FROST,      ## Chills and makes ice; puts out fire, carries lightning
	LIGHTNING,  ## Shocks; runs through ice
	POISON,     ## Sickens; blows up when lit
	VOID,       ## Swallows whatever it lands on
}

const NAMES: Dictionary[Kind, String] = {
	Kind.FIRE: "Fire",
	Kind.FROST: "Frost",
	Kind.LIGHTNING: "Lightning",
	Kind.POISON: "Poison",
	Kind.VOID: "Void",
}
const COLORS: Dictionary[Kind, Color] = {
	Kind.FIRE: Color(1.0, 0.5, 0.1),
	Kind.FROST: Color(0.6, 0.9, 1.0),
	Kind.LIGHTNING: Color(1.0, 0.95, 0.5),
	Kind.POISON: Color(0.55, 0.95, 0.2),
	Kind.VOID: Color(0.75, 0.35, 1.0),
}


static func of_patch(kind: GroundPatch3D.Kind) -> Kind:
	match kind:
		GroundPatch3D.Kind.ICE:
			return Kind.FROST
		GroundPatch3D.Kind.FIRE:
			return Kind.FIRE
	return Kind.POISON


static func of_slime(kind: SlimeElement.Kind) -> Kind:
	match kind:
		SlimeElement.Kind.FIRE:
			return Kind.FIRE
		SlimeElement.Kind.FROST:
			return Kind.FROST
		SlimeElement.Kind.LIGHTNING:
			return Kind.LIGHTNING
		SlimeElement.Kind.VOID:
			return Kind.VOID
	return Kind.POISON


static func of_bomb(type: Bomb3D.Type) -> Kind:
	match type:
		Bomb3D.Type.FIRE:
			return Kind.FIRE
		Bomb3D.Type.ICE:
			return Kind.FROST
	return Kind.POISON
