class_name Throwable3D extends Node3D
## Something a player holds up in both hands and throws (see
## PlayerClass3D.held_throwable), from an item box (see WildItem):
## - a big flask (Potion.LARGE) that shatters where it lands, splashing
##   everyone within Potion.SPLASH_RADIUS and maybe leaving a puddle, or
## - a bomb (a Bomb3D.Type) that goes off where it lands. Its fuse burns
##   while it's held, too: hang on to it too long and it goes off in hand.
## Holding one, a player can't attack or pick anything up; a hit that
## knocks them about makes them drop it.
##
## Every machine shows it held and flying. The thrower's own machine (the
## server for a bot) decides where it lands and who it gets, and tells
## every machine (_burst). Found by name online, so give() names it the
## same everywhere.

enum Kind { FLASK, BOMB }

## Thrown along the aim: this fast across the ground (m/s, times the
## throw_power perk stat), from a tap to a full charge.
const THROW_SPEED := Vector2(7.0, 20.0)
## Thrown at a lock-on target: as fast as it takes to land on them, up to this.
const MAX_THROW_SPEED := 24.0
## Every throw goes up this fast, and falls this hard (m/s, m/s^2).
const LIFT := 6.5
const GRAVITY := 22.0
## A dropped one (its holder knocked about, or gone).
const DROP_SPEED := 2.5
const DROP_LIFT := 3.0
## How big it is to hit things with in flight.
const RADIUS := 0.35
const HIT_MASK := 0b111  # World, players, enemies (the ball's on Enemy)
## A flying one that somehow hasn't landed after this long bursts anyway.
const MAX_FLIGHT := 4.0
## Seconds of fuse a bomb has, from the moment it's handed over.
const BOMB_FUSE := 6.0
## A bomb's explosion looks this big (m, see Bomb3D.show_blast).
const BOMB_LOOK_SIZE := 4.0

var kind: Kind = Kind.FLASK
## Which flask (Potion.LARGE) or bomb (Bomb3D.Type).
var variant: int = 0
## Who has it in hand (null once it's thrown).
var holder: PlayerClass3D = null
## Who has it or threw it: their machine decides where it lands.
var thrower: PlayerClass3D = null
var velocity: Vector3 = Vector3.ZERO
var flying: bool = false
var fuse_left: float = BOMB_FUSE
var _flight_time: float = 0.0
var _burst_sent: bool = false
var _look: Node3D
var _bomb: BombModel3D = null
var _spin: Vector3 = Vector3.ZERO
var _sizzle: AudioStreamPlayer3D = null


## Every machine: `player` gets one of `kind_` (`variant_` as in variant).
static func give(player: PlayerClass3D, kind_: Kind, variant_: int) -> Throwable3D:
	if is_instance_valid(player.held_throwable):
		player.held_throwable.queue_free()
	player.throwables_made += 1
	var item := Throwable3D.new()
	item.name = "%s_Throwable%d" % [player.name, player.throwables_made]
	item.kind = kind_
	item.variant = variant_
	item.holder = player
	item.thrower = player
	player.held_throwable = item
	Global.Game3D.add_child(item)
	item.global_position = player.carry_point()
	return item


func title() -> String:
	return Potion.large(variant).title if kind == Kind.FLASK else "%s Bomb" % Bomb3D.NAMES[variant as Bomb3D.Type]


func color() -> Color:
	return Potion.large(variant).color if kind == Kind.FLASK else Bomb3D.COLORS[variant as Bomb3D.Type]


func _ready() -> void:
	if kind == Kind.FLASK:
		_look = Node3D.new()
		var flask: Node3D = Potion.model(&"jug", color(), Potion.LARGE_HEIGHT)
		flask.position.y = -Potion.LARGE_HEIGHT * 0.5
		_look.add_child(flask)
		var glow := OmniLight3D.new()
		glow.light_color = color()
		glow.light_energy = 0.7
		glow.omni_range = 2.5
		_look.add_child(glow)
	else:
		_bomb = BombModel3D.new()
		_bomb.set_color(color())
		_bomb.scale = Vector3.ONE * 0.85
		_look = _bomb
		_sizzle = Sfx.play_loop(&"fire_loop", self)
	add_child(_look)


## Whether this machine decides where it lands: the thrower's.
func _decides() -> bool:
	return thrower._is_local() if is_instance_valid(thrower) else Net.decides()


func _process(delta: float) -> void:
	if kind == Kind.BOMB:
		if not PerkDirector.halted():
			fuse_left = maxf(fuse_left - delta, 0.0)
		_bomb.set_urgency(1.0 - fuse_left / BOMB_FUSE)
		if fuse_left <= 0.0 and _decides():
			_send_burst(global_position)
	if flying:
		_look.rotation += _spin * delta
		return
	if not is_instance_valid(holder) or holder.is_dead() or holder.held_throwable != self:
		# Its holder's gone down: it falls out of their hands
		holder = null
		_launch(global_position, Vector3.UP * DROP_LIFT)
		return
	global_position = holder.carry_point() + Vector3.UP * 0.35
	_look.rotation.y += delta * 2.0


## Owner of the holder: throw it `launch` (from where it is).
func throw(launch: Vector3) -> void:
	Net.everywhere(_thrown, global_position, launch)


## Owner of the holder: it's knocked out of their hands, along `dir`.
func drop(dir: Vector3) -> void:
	dir.y = 0.0
	throw(dir.normalized() * DROP_SPEED + Vector3.UP * DROP_LIFT)


@rpc("any_peer", "call_local", "reliable")
func _thrown(from: Vector3, launch: Vector3) -> void:
	if not _from_thrower():
		return
	if is_instance_valid(holder):
		holder.right_arm.play_throw_release()
	Sfx.play(&"throw", from, 0.7)
	_launch(from, launch)


## Inside an RPC: whether it came from the thrower's machine (or this one).
func _from_thrower() -> bool:
	var sender: int = multiplayer.get_remote_sender_id()
	return sender == 0 or not is_instance_valid(thrower) or sender == thrower.get_multiplayer_authority()


func _launch(from: Vector3, launch: Vector3) -> void:
	if is_instance_valid(holder) and holder.held_throwable == self:
		holder.held_throwable = null
	holder = null
	flying = true
	global_position = from
	velocity = launch
	_spin = Vector3(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0), randf_range(-8.0, 8.0))


func _physics_process(delta: float) -> void:
	if not flying:
		return
	_flight_time += delta
	velocity.y -= GRAVITY * delta
	var motion: Vector3 = velocity * delta
	var shape := SphereShape3D.new()
	shape.radius = RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.motion = motion
	query.collision_mask = HIT_MASK
	if is_instance_valid(thrower) and _flight_time < 0.4:
		query.exclude = [thrower.get_rid()]  # Not out of their own hands
	var fractions: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	var safe: float = fractions[0] if fractions.size() > 0 else 1.0
	global_position += motion * safe
	if safe < 1.0 or _flight_time >= MAX_FLIGHT:
		if _decides():
			_send_burst(global_position)
		else:
			flying = false  # Lies there till the thrower's machine says
			velocity = Vector3.ZERO


## The deciding machine: it bursts at `at`. Work out who it gets, hit them
## (a bomb), and tell every machine.
func _send_burst(at: Vector3) -> void:
	if _burst_sent:
		return
	_burst_sent = true
	var caught := PackedStringArray()
	if kind == Kind.BOMB:
		Bomb3D.blast(get_world_3d(), at, variant as Bomb3D.Type, [], thrower)
	elif Global.Game3D:
		var for_allies: bool = Potion.large(variant).get("allies", false)
		for player: PlayerClass3D in Global.Game3D.players:
			if not is_instance_valid(player) or player.is_dead():
				continue
			var away: Vector3 = player.global_position - at
			if Vector2(away.x, away.z).length() > Potion.SPLASH_RADIUS or absf(away.y) > 3.0:
				continue
			var ally: bool = player == thrower or (is_instance_valid(thrower) and Combat.are_teammates(player, thrower))
			if ally == for_allies:
				caught.append(String(player.name))
	Net.everywhere(_burst, at, caught)


## Every machine: it bursts at `at`, splashing the players named `caught`.
@rpc("any_peer", "call_local", "reliable")
func _burst(at: Vector3, caught: PackedStringArray) -> void:
	if not _from_thrower():
		return
	if is_instance_valid(holder) and holder.held_throwable == self:
		holder.held_throwable = null
	if kind == Kind.BOMB:
		Bomb3D.show_blast(at, variant as Bomb3D.Type, BOMB_LOOK_SIZE)
	else:
		_splash(at, caught)
	queue_free()


func _splash(at: Vector3, caught: PackedStringArray) -> void:
	var potion: Dictionary = Potion.large(variant)
	Vfx.play(&"impact", at, Vector3.FORWARD, false, 2.2, potion.color)
	Vfx.play(&"shatter", at + Vector3.UP * 0.4, Vector3.FORWARD, false, 2.0, potion.color)
	Sfx.play(&"weapon_break", at, 1.6)
	Sfx.play(&"spell_impact", at)
	if potion.has("patch") and Global.Game3D:
		GroundPatch3D.lay(Global.Game3D, potion.patch, at, thrower, Potion.PUDDLE_RADIUS, Potion.PUDDLE_TIME, true)
	if not Global.Game3D:
		return
	for player_name: String in caught:
		var player: PlayerClass3D = Global.Game3D.player_named(player_name)
		if player:
			Potion.splash(player, variant, thrower)


func _exit_tree() -> void:
	if is_instance_valid(holder) and holder.held_throwable == self:
		holder.held_throwable = null


## The launch that lands a throw from `from` on `to`, as fast as it takes
## (up to MAX_THROW_SPEED).
static func launch_onto(from: Vector3, to: Vector3) -> Vector3:
	var fall: float = maxf(from.y - to.y, 0.0)
	var airtime: float = (LIFT + sqrt(LIFT * LIFT + 2.0 * GRAVITY * fall)) / GRAVITY
	var across := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return (across / airtime).limit_length(MAX_THROW_SPEED) + Vector3.UP * LIFT


## The launch for a throw along `dir`, with `charge` (0-1) and `power`
## (the thrower's throw_power).
static func launch_along(dir: Vector3, charge: float, power: float) -> Vector3:
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	return dir * lerpf(THROW_SPEED.x, THROW_SPEED.y, charge) * power + Vector3.UP * LIFT
