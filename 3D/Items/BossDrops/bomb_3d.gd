class_name Bomb3D extends Ball3D
## A lit bomb (see BossDrop): knock it into the enemy's goal before its
## fuse runs out. It goes off in there, damaging that team's base (see
## Game3D.bomb_in_goal); run out of fuse anywhere else and it goes off right
## there, blasting everyone close by (see blast).
##
## Each bomb has a type (see Type) that decides what else it does, to the
## team whose goal it lands in or to whoever's caught in it on the field.
## A boss that swallows one holds its fuse and may change its type, and
## gives it back with some fuse added (see Boss3D._net_swallow).
##
## The fuse burns on every machine; only the one simulating the bomb
## (server/offline) sets it off.

enum Type {
	FIRE,    ## Hits the base harder; sets players on fire in the open
	POISON,  ## Poisons the team whose goal it lands in, or everyone it catches
	ICE,     ## Chills them instead: slower for a while
}
const NAMES: Dictionary[Type, String] = {
	Type.FIRE: "Fire",
	Type.POISON: "Poison",
	Type.ICE: "Ice",
}
const COLORS: Dictionary[Type, Color] = {
	Type.FIRE: Color(1.0, 0.45, 0.1),
	Type.POISON: Color(0.55, 0.95, 0.2),
	Type.ICE: Color(0.45, 0.85, 1.0),
}
## Base HP it takes going off in a goal. A base has BASE_HP_PER_POINT for
## every point of the lobby's Score to Win.
const BASE_DAMAGE: Dictionary[Type, int] = {
	Type.FIRE: 150,
	Type.POISON: 100,
	Type.ICE: 100,
}
const BASE_HP_PER_POINT := 100

## Seconds of fuse a new bomb has.
const FUSE_TIME := 30.0
## A bomb a boss gives back (beaten) has this much fuse added to what it had
## left when swallowed, and never less than MIN_RELEASE_FUSE.
const BOSS_FUSE_BONUS := 10.0
const MIN_RELEASE_FUSE := 12.0
## The countdown over it turns urgent (and the bomb flickers hard) from here.
const URGENT_TIME := 5.0

## Going off in the open: everyone within BLAST_RADIUS is hit, hardest (and
## knocked down longest, as a multiple of a slide tackle's) at the middle.
const BLAST_RADIUS := 5.0
const BLAST_DAMAGE := 35.0
const BLAST_EDGE_DAMAGE := 10.0
const BLAST_KNOCKBACK := 16.0
const BLAST_EDGE_KNOCKBACK := 6.0
const BLAST_POP := 5.0
const BLAST_KNOCKDOWN := 2.0
const BLAST_EDGE_KNOCKDOWN := 0.5
## How wide its explosion looks (m, see Vfx "explosion").
const BLAST_LOOK_SIZE := 5.0
## Seconds its poison or chill lasts on whoever it catches in the open, and
## on the whole team whose goal it goes off in.
const FIELD_EFFECT_TIME := 5.0
const GOAL_EFFECT_TIME := 8.0

var type: Type = Type.FIRE
## Seconds until it goes off.
var fuse_left: float = FUSE_TIME
var _went_off: bool = false
@onready var _model: BombModel3D = $Model
var _countdown: Label3D
var _sizzle: AudioStreamPlayer3D = null


## Its type and fuse. Call on every machine before it enters play.
func setup(new_type: Type, fuse: float) -> void:
	type = new_type
	fuse_left = fuse


func _ready() -> void:
	super()
	_model.set_color(color())
	_countdown = Label3D.new()
	_countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_countdown.no_depth_test = true
	_countdown.font_size = 72
	_countdown.outline_size = 16
	_countdown.pixel_size = 0.008
	_countdown.position = Vector3.UP * 1.0
	_countdown.top_level = true  # Stays upright while the bomb rolls
	add_child(_countdown)
	_sizzle = Sfx.play_loop(&"fire_loop", self)


func color() -> Color:
	return COLORS[type]


func _process(delta: float) -> void:
	super(delta)
	if not PerkDirector.halted():
		fuse_left = maxf(fuse_left - delta, 0.0)
	_model.set_urgency(1.0 - fuse_left / FUSE_TIME)
	_countdown.global_position = global_position + Vector3.UP * 1.0
	_countdown.text = str(ceili(fuse_left))
	var urgent: bool = fuse_left <= URGENT_TIME
	_countdown.modulate = Color.RED.lerp(Color.WHITE, 0.5 + 0.5 * sin(fuse_left * 20.0)) if urgent else color().lightened(0.4)
	_countdown.scale = Vector3.ONE * (1.4 if urgent else 1.0)


func _physics_process(delta: float) -> void:
	super(delta)
	if Net.decides() and fuse_left <= 0.0 and not _went_off and Global.Game3D:
		_went_off = true
		Global.Game3D.bomb_fuse_out(self)


## Server/offline: a bomb of `type` goes off at `origin`, hitting everyone
## within BLAST_RADIUS (but `exclude`): harder, and knocked down for longer,
## the closer they are; then its type's effect on the players caught.
## `attacker` (a player who threw it) gets the credit.
static func blast(world: World3D, origin: Vector3, blast_type: Type, exclude: Array[RID], attacker: Node3D = null) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = BLAST_RADIUS
	for body: Node3D in Combat.overlaps(world, sphere, Transform3D(Basis(), origin), exclude):
		var away: Vector3 = body.global_position - origin
		var closeness: float = 1.0 - clampf(Vector2(away.x, away.z).length() / BLAST_RADIUS, 0.0, 1.0)
		Combat.strike(body, away, lerpf(BLAST_EDGE_DAMAGE, BLAST_DAMAGE, closeness),
			lerpf(BLAST_EDGE_KNOCKBACK, BLAST_KNOCKBACK, closeness), BLAST_POP, -1.0, attacker,
			lerpf(BLAST_EDGE_KNOCKDOWN, BLAST_KNOCKDOWN, closeness))
		if body is PlayerClass3D and not Combat.are_teammates(body, attacker):
			afflict(body, blast_type, FIELD_EFFECT_TIME, true)


## What a bomb of `bomb_type` does to `player` besides the blast, for
## `seconds`: poison, chill, or (with `burn`, out in the open) fire.
static func afflict(player: PlayerClass3D, bomb_type: Type, seconds: float, burn: bool = false) -> void:
	match bomb_type:
		Type.POISON:
			player.status.apply(PlayerStatus3D.Kind.POISONED, seconds)
		Type.ICE:
			player.status.apply(PlayerStatus3D.Kind.CHILLED, seconds)
		Type.FIRE:
			if burn:
				player.status.apply(PlayerStatus3D.Kind.BURNING, PlayerStatus3D.BURN_TIME)


## Every machine: how it looks and sounds going off at `at`.
static func show_blast(at: Vector3, blast_type: Type, size: float = BLAST_LOOK_SIZE) -> void:
	var tint: Color = COLORS[blast_type] if blast_type != Type.FIRE else Color.TRANSPARENT
	Vfx.play(&"explosion", at, Vector3.FORWARD, false, size, tint)
	Sfx.play(&"boss_stomp", at)
	Sfx.play(&"weapon_break", at, 0.6)
	CameraShake.add(CameraShake.HEAVY, at)
	ElementReactions.strike(Element.of_bomb(blast_type), at, BLAST_RADIUS)


## A type for a bomb nobody chose one for (a boss's drop), the same on
## every machine.
static func type_for(seed_name: String) -> Type:
	return (absi(hash(seed_name)) % Type.size()) as Type
