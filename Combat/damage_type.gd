class_name DamageType
## What a hit is made of, passed along with it (see Combat.strike) so
## whoever takes it can show the right effect (see Vfx.hit). For now it only
## changes how a hit looks, not what it does.

enum Kind {
	BLUNT,      ## Fists, hammers, shields, the ball, slimes
	SLASH,      ## Swords, axes
	PIERCE,     ## Spears, daggers, arrows, spikes
	BLAST,      ## Explosions: a weapon shattering, a bomb
	ARCANE,     ## Magic with no element: staff and wand bolts and orbs
	FIRE,
	FROST,
	LIGHTNING,
	POISON,
	VOID,
}


## A type another machine sent us: as sent, or BLUNT if it isn't one.
static func vetted(type: int) -> Kind:
	return type as Kind if Kind.values().has(type) else Kind.BLUNT


static func of_element(element: Element.Kind) -> Kind:
	match element:
		Element.Kind.FIRE:
			return Kind.FIRE
		Element.Kind.FROST:
			return Kind.FROST
		Element.Kind.LIGHTNING:
			return Kind.LIGHTNING
		Element.Kind.VOID:
			return Kind.VOID
	return Kind.POISON
