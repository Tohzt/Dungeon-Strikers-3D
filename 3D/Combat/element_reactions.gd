class_name ElementReactions
## What happens when elements (see Element) meet on the floor: a patch laid
## on another (see GroundPatch3D.lay), or a bolt, blast or glob landing on
## patches (strike), or a burning ball rolling through them (ball_at):
## - fire and frost make steam: both are gone (water puts out fire),
## - fire on poison blows it up, and the blast runs on through every
##   poison patch touching it,
## - lightning on ice shocks everyone on it, running on through every ice
##   patch touching it,
## - void swallows whatever it lands on.
## Reactions hurt everyone, their makers' own team too.
##
## Patches are made on every machine, so every machine works out their
## reactions for itself and shows them. Each hurts only the players it
## owns, and only the deciding one (see Net.decides) hurts or shoves
## anything else (bosses, minions, the ball), so nothing is sent online.

enum Reaction {
	STEAM,     ## Both go up in steam
	DETONATE,  ## The poison patch it lands on blows up (and the poison touching it)
	IGNITE,    ## Poison landing on fire: the poison blows up
	SHOCK,     ## The ice patch it lands on is shocked (and the ice touching it)
	SWALLOW,   ## The patch it lands on is gone
}

## What an element landing on a patch does, by the patch's element.
const ON_PATCH: Dictionary[Element.Kind, Dictionary] = {
	Element.Kind.FIRE: {Element.Kind.FROST: Reaction.STEAM, Element.Kind.POISON: Reaction.DETONATE},
	Element.Kind.FROST: {Element.Kind.FIRE: Reaction.STEAM},
	Element.Kind.LIGHTNING: {Element.Kind.FROST: Reaction.SHOCK},
	Element.Kind.POISON: {Element.Kind.FIRE: Reaction.IGNITE},
	Element.Kind.VOID: {Element.Kind.FIRE: Reaction.SWALLOW, Element.Kind.FROST: Reaction.SWALLOW,
		Element.Kind.POISON: Reaction.SWALLOW},
}

## Patches this close (m, edge to edge) touch: a chain runs on through them.
const TOUCH_GAP := 0.4
## A chain moves on to the next patches after this long (s), and stops
## after this many.
const HOP_DELAY := 0.06
const MAX_CHAIN := 48
## Things this far over or under a patch are clear of it.
const REACH_HEIGHT := 1.5

## Lightning on ice: everyone on it is shocked, and knocked down (times a
## slide tackle's, see Combat.strike).
const SHOCK_DAMAGE := 12.0
const SHOCK_KNOCKBACK := 3.0
const SHOCK_POP := 3.0
const SHOCK_KNOCK_DOWN := 0.8
## Ice can't be shocked again this soon after (ms).
const SHOCK_COOLDOWN_MSEC := 1000

## Fire on poison: each patch blows up, reaching this far past its edge.
const BLAST_DAMAGE := 25.0
const BLAST_KNOCKBACK := 12.0
const BLAST_POP := 6.0
const BLAST_KNOCK_DOWN := 0.6
const BLAST_REACH := 1.2

## The ball goes through a patch this far out from its middle.
const BALL_REACH := 0.4
## A ball rolling through fire burns this long.
const BALL_BURN := 4.0

const STEAM_COLOR := Color(0.9, 0.93, 0.95)


## Every machine: `patch` was just laid. Whatever it lands on that it
## reacts with, reacts.
static func on_laid(patch: GroundPatch3D) -> void:
	var element: Element.Kind = Element.of_patch(patch.kind)
	var source: PlayerClass3D = patch.maker()
	for other: GroundPatch3D in GroundPatch3D.all.duplicate():
		if patch.consumed:
			return
		if other != patch and not other.consumed and _touching(patch, other):
			_meet(element, other, patch, source)


## Every machine: `element` lands at `at` (on the floor), reaching `reach`
## meters: a lightning strike, a bomb's blast, a slime's glob. `source` is
## whoever's behind it, if anyone.
static func strike(element: Element.Kind, at: Vector3, reach: float, source: Node3D = null) -> void:
	for patch: GroundPatch3D in GroundPatch3D.all.duplicate():
		if not patch.consumed and _reaches(patch, at, reach):
			_meet(element, patch, null, source)


## Every machine, every frame: the ball goes through whatever patches it's
## on. Burning, it sets off poison and melts ice; through fire, it catches
## (the deciding machine sets it burning, see Ball3D).
static func ball_at(ball: Ball3D) -> void:
	for patch: GroundPatch3D in GroundPatch3D.all.duplicate():
		if patch.consumed or not _reaches(patch, ball.global_position, BALL_REACH):
			continue
		match patch.kind:
			GroundPatch3D.Kind.FIRE:
				if Net.decides() and ball.burn_left < BALL_BURN * 0.5:
					ball._ignite(BALL_BURN, patch.maker_name)
			_:
				if ball.burn_left > 0.0:
					_meet(Element.Kind.FIRE, patch, null, null)


## `element` lands on `patch`: as another patch (`arriving`) or not.
static func _meet(element: Element.Kind, patch: GroundPatch3D, arriving: GroundPatch3D, source: Node3D) -> void:
	var reactions: Dictionary = ON_PATCH.get(element, {})
	var target: Element.Kind = Element.of_patch(patch.kind)
	if not reactions.has(target):
		return
	var detonate := func(next: GroundPatch3D, hit: Dictionary) -> void: _detonate(next, source, hit)
	var shock := func(next: GroundPatch3D, hit: Dictionary) -> void: _shock(next, source, hit)
	match reactions[target] as Reaction:
		Reaction.STEAM:
			_steam(patch.global_position, patch.radius)
			patch.consume()
			if arriving:
				arriving.consume()
		Reaction.DETONATE:
			_chain([patch], detonate, {}, {})
		Reaction.IGNITE:
			if arriving:
				_chain([arriving], detonate, {}, {})
			else:
				_explode(patch, patch.global_position, patch.radius + BLAST_REACH, source, {})
		Reaction.SHOCK:
			if not _shocked_lately(patch):
				_chain([patch], shock, {}, {})
		Reaction.SWALLOW:
			Vfx.play(&"dark_blast", patch.global_position, Vector3.FORWARD, false, patch.radius * 2.0)
			patch.consume()


## Do `step` to each of `patches`, then, a moment later, to every patch of
## the same kind touching them it hasn't been done to yet, and so on.
## Everything it hits it hits once (`hit`).
static func _chain(patches: Array, step: Callable, seen: Dictionary, hit: Dictionary) -> void:
	var kind: GroundPatch3D.Kind = patches[0].kind
	for patch: GroundPatch3D in patches:
		seen[patch] = true
	for patch: GroundPatch3D in patches:
		step.call(patch, hit)
	var next: Array[GroundPatch3D] = []
	for patch: GroundPatch3D in patches:
		for other: GroundPatch3D in GroundPatch3D.all:
			if seen.size() + next.size() >= MAX_CHAIN:
				break
			if other.kind == kind and not other.consumed and not seen.has(other) and not next.has(other) \
					and not (kind == GroundPatch3D.Kind.ICE and _shocked_lately(other)) and _touching(patch, other):
				next.append(other)
	if next.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	tree.create_timer(HOP_DELAY).timeout.connect(func() -> void:
		var left: Array[GroundPatch3D] = []
		for patch: GroundPatch3D in next:
			if is_instance_valid(patch) and not patch.consumed:
				left.append(patch)
		if not left.is_empty():
			_chain(left, step, seen, hit))


## Lightning runs through the ice `patch`, shocking everyone on it.
static func _shock(patch: GroundPatch3D, source: Node3D, hit: Dictionary) -> void:
	patch.set_meta(&"shocked_msec", Time.get_ticks_msec())
	var at: Vector3 = patch.global_position
	Vfx.play(&"lightning", at, Vector3.FORWARD, false, patch.radius * 2.0, Element.COLORS[Element.Kind.LIGHTNING])
	if hit.is_empty():
		Sfx.play(&"spell_impact", at)
		CameraShake.add(CameraShake.MEDIUM, at)
	_hurt_around(patch, at, patch.radius, SHOCK_DAMAGE, SHOCK_KNOCKBACK, SHOCK_POP, SHOCK_KNOCK_DOWN, source, hit)


static func _shocked_lately(patch: GroundPatch3D) -> bool:
	return Time.get_ticks_msec() - int(patch.get_meta(&"shocked_msec", -SHOCK_COOLDOWN_MSEC)) < SHOCK_COOLDOWN_MSEC


## The poison `patch` blows up and is gone.
static func _detonate(patch: GroundPatch3D, source: Node3D, hit: Dictionary) -> void:
	patch.consume()
	_explode(patch, patch.global_position, patch.radius + BLAST_REACH, source, hit)


## A blast of lit poison at `at`, reaching `reach` meters (in `node`'s world).
static func _explode(node: Node3D, at: Vector3, reach: float, source: Node3D, hit: Dictionary) -> void:
	Vfx.play(&"explosion", at, Vector3.FORWARD, false, reach)
	Vfx.play(&"smoke", at, Vector3.FORWARD, false, reach, Element.COLORS[Element.Kind.POISON])
	Sfx.play(&"fireball", at)
	CameraShake.add(CameraShake.HEAVY, at)
	_hurt_around(node, at, reach, BLAST_DAMAGE, BLAST_KNOCKBACK, BLAST_POP, BLAST_KNOCK_DOWN, source, hit)


static func _steam(at: Vector3, reach: float) -> void:
	Vfx.play(&"smoke", at, Vector3.FORWARD, false, reach * 1.5, STEAM_COLOR)
	Sfx.play(&"ignite", at, 0.6)


## Hit everything within `reach` of `at` (in `node`'s world) that this
## machine looks after and `hit` doesn't have yet: its own players, and,
## deciding, everything else. Whoever's behind it (`source`, a player) is
## blamed by the enemies it hurts.
static func _hurt_around(node: Node3D, at: Vector3, reach: float, damage: float, knockback: float, pop: float,
		knock_down: float, source: Node3D, hit: Dictionary) -> void:
	if not node.is_inside_tree():
		return
	var shape := CylinderShape3D.new()
	shape.radius = reach
	shape.height = REACH_HEIGHT * 2.0
	for body: Node3D in Combat.overlaps(node.get_world_3d(), shape, Transform3D(Basis(), at), []):
		if hit.has(body) or (body is Weapon3D and body.wielder):
			continue
		if not (body._is_local() if body is PlayerClass3D else Net.decides()):
			continue
		hit[body] = true
		var landed: bool = Combat.strike(body, body.global_position - at, damage, knockback, pop, -1.0, null, knock_down)
		if landed and body is PlayerClass3D and source is PlayerClass3D and source != body \
				and not Combat.are_teammates(body, source):
			body.blame(source)


## Whether `a` and `b` touch (or near enough), on the same floor.
static func _touching(a: GroundPatch3D, b: GroundPatch3D) -> bool:
	return _reaches(a, b.global_position, b.radius + TOUCH_GAP)


## Whether a circle at `at`, `reach` meters across, overlaps `patch`.
static func _reaches(patch: GroundPatch3D, at: Vector3, reach: float) -> bool:
	var away: Vector3 = at - patch.global_position
	return Vector2(away.x, away.z).length() <= patch.radius + reach and absf(away.y) < REACH_HEIGHT
