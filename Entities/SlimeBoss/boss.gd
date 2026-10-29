class_name Boss3D extends CharacterBody3D
## A big slime that roams the pitch in short hops. Touching it is safe; its
## attacks are telegraphed: it lunges at players a little way off, swells
## up in a burst when they crowd it, leaps up for a big stomp when one is close,
## and when it finds itself near the ball it dribbles it into whichever goal
## it's nearest, so it's a threat to both teams. Every so often it swells
## up and spits out little minion slimes (SlimeMinion3D) that chase players.
## It's made of an element (see `element`, SlimeElement), picked at random
## unless set: poison, fire, lightning, frost or void. That decides its
## name and color, what its hits (and its minions') do to players, and the
## spell it casts every so often (see _cast).
## Its drop (see `drop`) floats in its core; beating it drops that into play.
## With `swallows_ball` it gulps down a ball it touches instead of kicking
## it, and only gives it back when beaten. A swallowed bomb's fuse stops,
## it comes back as the boss's element's type (a random one if it has
## none), and with some fuse added (see Bomb3D.BOSS_FUSE_BONUS).
## Online the server runs it and streams where it is (like the ball);
## everyone else just plays that back.

enum State {
	IDLE,           ## Resting on the ground between hops
	HOP_PREP,       ## Squashing down before a hop
	HOP,            ## In the air on a small hop
	STOMP_WINDUP,   ## Crouched and quivering, telegraphing a stomp
	STOMP_RISE,     ## Leaping up toward the stomp target
	STOMP_HANG,     ## Hovering at the top, drifting over the target
	STOMP_FALL,     ## Slamming down
	RECOVER,        ## Flattened after a stomp, catching its breath
	STAGGERED,      ## Poise broken: dazed and defenseless for a while
	SPIT_WINDUP,    ## Swelling up, about to spit out minions
	LUNGE_WINDUP,   ## Rearing back, about to lunge
	LUNGE,          ## Skimming forward in a low, fast leap
	SWELL_WINDUP,   ## Crouched and shivering, about to burst outward
	SWELL,          ## Puffed up: the burst
	CAST_WINDUP,    ## Glowing and gurgling, about to cast its element's spell
	WARP,           ## Void: gone through a portal, about to drop on someone
	DEAD,           ## Beaten: deflating, ball released
}

## HP changed (on every machine). For the boss health bar.
signal hp_changed(hp: float, max_hp: float)
## The fight has started (the start delay ran out). On every machine.
signal awakened
## Beaten, by `killer` (the player who landed the last hit; null if
## unknown). On every machine.
signal defeated(killer: PlayerClass3D)

# ===== SIZE =====
const RADIUS := 3.0
const HEIGHT := 4.0
const PLAYER_RADIUS := 0.5  # PlayerClass3D.BODY_RADIUS
const BALL_RADIUS := 0.5

# ===== MOVEMENT =====
@export_category("Hopping")
@export var gravity_scale: float = 2.0
@export var hop_velocity: float = 7.0  ## Upward speed of a small hop
@export var hop_speed: float = 6.0  ## Sideways speed during a small hop
@export var hop_rest_min: float = 0.35  ## Pause on the ground between hops
@export var hop_rest_max: float = 0.8
const HOP_PREP_TIME := 0.15
## Pokes from players slide the slime a little; this is how fast that stops.
const SHOVE_FRICTION := 12.0
const SHOVE_MAX := 4.0
const SHOVE_RESISTANCE := 0.15  # Share of an impulse that actually moves it

# ===== STOMP =====
@export_category("Stomp")
@export var stomp_trigger_range: float = 9.0  ## Stomp when a player is this close
@export var stomp_cooldown: float = 5.0
@export var stomp_radius: float = 6.0  ## Shockwave reach from the slime's center
@export var stomp_damage: float = 40.0  ## At the center, falling to half at the edge
@export var stomp_knockback: float = 14.0
@export var stomp_pop: float = 5.0
@export var stomp_ball_impulse: float = 8.0
const STOMP_WINDUP_TIME := 0.7
const STOMP_JUMP_VELOCITY := 16.0
const STOMP_MAX_DISTANCE := 10.0  # How far it can travel in one stomp leap
const STOMP_HANG_TIME := 0.3
const STOMP_HANG_TRACKING := 4.0  # m/s it drifts toward its target while hanging
const STOMP_FALL_SPEED := 35.0
const STOMP_RECOVER_TIME := 1.1
## Players this far above the ground when it lands jumped the shockwave.
const STOMP_DODGE_HEIGHT := 1.2

# ===== MINIONS =====
@export_category("Minions")
@export var minion_scene: PackedScene = preload("res://Entities/SlimeBoss/Minions/slime_minion.tscn")
@export var spit_cooldown: float = 9.0
## Minions per spit.
@export var spit_count: int = 2
## No spitting while this many of its minions are still around.
@export var max_minions: int = 4
## Sideways and upward launch speed; they land roughly this far out
## (sideways speed * 2 * up speed / gravity).
@export var spit_speed: float = 6.0
@export var spit_lift: float = 10.0
const SPIT_WINDUP_TIME := 0.8
## Spread (radians) around the aim toward a player.
const SPIT_SPREAD := 0.6

# ===== LUNGE =====
@export_category("Lunge")
@export var lunge_trigger_range: float = 14.0  ## Lunge at a player this close
@export var lunge_cooldown: float = 4.0
@export var lunge_distance: float = 9.0  ## Farthest it travels in one lunge
@export var lunge_damage: float = 20.0
@export var lunge_knockback: float = 14.0
@export var lunge_pop: float = 4.0
const LUNGE_WINDUP_TIME := 0.6
const LUNGE_AIR_TIME := 0.4
## It stops tracking its target this long before it goes, so a late sidestep works.
const LUNGE_AIM_LOCK := 0.2
## Rest after a lunge: the opening to punish it.
const LUNGE_RECOVER_TIME := 0.8
## How far the body leans back while rearing (and forward while lunging).
const LUNGE_LEAN := 0.8

# ===== SWELL =====
# A burst outward when players crowd it, so hugging it isn't free.
@export_category("Swell")
@export var swell_trigger_range: float = 5.0  ## Burst when a player is this close to its center
@export var swell_cooldown: float = 3.5
@export var swell_radius: float = 6.0  ## Burst reach from its center
@export var swell_damage: float = 25.0
@export var swell_knockback: float = 16.0
@export var swell_pop: float = 6.0
const SWELL_WINDUP_TIME := 0.55
const SWELL_TIME := 0.3
const SWELL_SCALE := 1.6  # How big it puffs up at the burst

# ===== ELEMENT =====
@export_category("Element")
## What it's made of (see SlimeElement). RANDOM rolls one when it's made,
## the same on every machine (see SlimeElement.pick).
@export var element: SlimeElement.Kind = SlimeElement.Kind.RANDOM
@export var cast_cooldown: float = 10.0
## Casts when its target is this close.
@export var cast_range: float = 22.0
const CAST_WINDUP_TIME := 0.9
## Poison and fire: globs lobbed per cast (aimed at players first, the
## rest around it), how long they fly, and what they do where they land.
@export var glob_count: int = 5
@export var glob_radius: float = 2.5
@export var glob_damage: float = 15.0
@export var glob_knockback: float = 8.0
const GLOB_FLIGHT_TIME := 1.2
const GLOB_SCATTER := 9.0  # How far around it the spare globs land
const POOL_TIME := 6.0
## Puddles a stomp leaves are this much wider than a glob's.
const STOMP_POOL_SCALE := 1.6
## Lightning: a strike on every player in range, plus a few around it.
@export var storm_damage: float = 22.0
@export var storm_radius: float = 3.0
const STORM_WARN_TIME := 1.0
const STORM_EXTRA_STRIKES := 3
const STORM_LEAD := 0.6  # Share of a player's run it aims ahead
## Frost: a nova around it that chills everyone in it, and freezes those
## close in. Its windup is longer, and shows the ring.
@export var nova_radius: float = 10.0
@export var nova_freeze_radius: float = 5.0
@export var nova_damage: float = 15.0
const NOVA_WINDUP_TIME := 1.4
## Void: drops out of a portal this high over its target.
const WARP_TIME := 0.9
const WARP_HEIGHT := 8.0
const PORTAL_SIZE := 5.0
const PORTAL_HOLD := 0.6
var _cast_cooldown: float = 0.0
## What it wears all fight (SlimeElement.AURAS).
var _aura: Node3D = null
var _element_ready: bool = false
## Came into a stomp's hang out of a warp (for the exit portal).
var _warping: bool = false

# ===== BALL =====
@export_category("Ball")
## Goes after the ball instead of players when it's within this range.
@export var ball_interest_range: float = 10.0
@export var kick_impulse: float = 7.0
@export var kick_lift: float = 1.5
const KICK_COOLDOWN := 0.5
## How far behind the ball (away from the goal) it lines up before pushing.
const DRIBBLE_SETUP_OFFSET := RADIUS + BALL_RADIUS + 0.5

# ===== HEALTH =====
@export_category("Health")
## Empty: its element's name (SlimeElement.NAMES).
@export var display_name: String = ""
@export var max_hp: float = 1200.0
## What it drops into play when beaten (shown floating in its core until then).
@export var drop: BossDrop.Kind = BossDrop.Kind.SKULL
## How hard the drop pops out.
@export var release_impulse: float = 1.5
## Touching a ball while its belly is empty (no drop) swallows it: it
## becomes the drop, so the ball's back in play only once the boss is beaten.
@export var swallows_ball: bool = false
## Shut in a pen (BossPen3D) until it's let out: nobody can reach it, so
## bots leave it be.
var penned: bool = false
## Hits tint the slime this bright for a moment.
const HIT_FLASH_TIME := 0.15
## Hits move it this fraction as far as they'd shove a loose object.
const HIT_SHOVE_RATIO := 0.3
const DEATH_TIME := 1.2
## How wide the mushroom cloud it goes out in is (m, see Vfx "nuke").
const NUKE_SIZE := 3.6
## A bomb it holds: its type (-1 = none chosen; a drop picks one from the
## boss's name) and the fuse it had left when swallowed (-1 = a fresh one).
## The same on every machine.
var _bomb_type: int = -1
var _bomb_fuse: float = -1.0
## The drop's model floating in the core, if it has one.
var _core_model: Node3D = null
## How much the core bobs around inside the slime.
const CORE_BOB := 0.2

# ===== POISE =====
# Hits wear down its poise; enough damage in quick succession (a few players
# ganging up on it) staggers it: it stops, can't hurt anyone, and takes extra
# damage for a while. A stagger earned in mid-air waits until it's grounded.
@export_category("Poise")
@export var poise_max: float = 180.0
## Poise fully recovers after this long without being hit.
@export var poise_reset_delay: float = 2.5
@export var stagger_duration: float = 2.5
@export var staggered_damage_multiplier: float = 1.5
var _poise_damage: float = 0.0
var _poise_reset_wait: float = 0.0
var _poise_broken: bool = false

## Don't start acting until the match has had a moment to settle.
@export var start_delay: float = 3.0
## Sleep (no countdown, no health bar) until wake() is called, e.g. by a
## BossTrigger3D when the first player walks into its arena, or by a hit.
@export var wait_for_players: bool = false

@onready var visual: Node3D = $Visual
@onready var body_mesh: MeshInstance3D = $Visual/MeshInstance3D
@onready var core: MeshInstance3D = $Visual/Core
@onready var telegraph: MeshInstance3D = $StompTelegraph
@onready var _core_rest: Vector3 = core.position
@onready var _body_material: StandardMaterial3D = body_mesh.get_surface_override_material(0)
@onready var _body_color: Color = _body_material.albedo_color if _body_material else Color.WHITE

var hp: float:
	set(value):
		hp = value
		hp_changed.emit(hp, max_hp)
var is_awake: bool = false
var is_defeated: bool = false
var _flash: float = 0.0

var state: State = State.IDLE
var _state_time: float = 0.0
var _rest_time: float = 0.5
var _stomp_cooldown: float = 0.0
var _kick_cooldown: float = 0.0
var _lunge_cooldown: float = 0.0
var _swell_cooldown: float = 0.0
## Players the current lunge has already hit.
var _lunge_hits: Array[PlayerClass3D] = []
var _shove: Vector3 = Vector3.ZERO
var _move_dir: Vector3 = Vector3.ZERO
var _stomp_target: Vector3 = Vector3.ZERO
var _ground_y: float = 0.0
var _spit_cooldown: float = 0.0
## Minions it has spat out that are still alive.
var _minions: Array[SlimeMinion3D] = []
## Names spat-out minions, the same on every machine.
var _minions_made: int = 0

# Squash and stretch: a spring on the vertical scale (sideways scale keeps
# the volume roughly constant).
const SQUASH_STIFFNESS := 180.0
const SQUASH_DAMPING := 10.0
var _squash: float = 1.0
var _squash_vel: float = 0.0
var _wobble_time: float = 0.0

## Online: the server sends where it is; clients play it back.
var _motion := NetMotion.new()


## Its element is settled as soon as it's named and in the level, before
## anything (the health bar) reads its name.
func _enter_tree() -> void:
	if _element_ready:
		return
	_element_ready = true
	if element == SlimeElement.Kind.RANDOM:
		element = SlimeElement.pick(String(name))
	if display_name.is_empty():
		display_name = SlimeElement.NAMES[element]
	_apply_element_traits()


## How its element changes the way it fights, on top of its exports.
func _apply_element_traits() -> void:
	match element:
		SlimeElement.Kind.POISON:
			spit_count += 1  # A brood mother
		SlimeElement.Kind.FIRE:
			swell_damage *= 1.2
			cast_cooldown *= 0.9
		SlimeElement.Kind.LIGHTNING:
			# Twitchy: rests less and lunges more
			hop_rest_min *= 0.6
			hop_rest_max *= 0.6
			lunge_cooldown *= 0.7
			hop_speed *= 1.15
		SlimeElement.Kind.FROST:
			hop_speed *= 0.85
			stomp_cooldown *= 0.8
		SlimeElement.Kind.VOID:
			cast_cooldown *= 0.8  # Warps often
			stomp_trigger_range *= 0.7


func _ready() -> void:
	add_to_group("Boss")
	_ground_y = global_position.y
	telegraph.top_level = true
	telegraph.visible = false
	var ring: CylinderMesh = telegraph.mesh as CylinderMesh
	if ring:
		ring.top_radius = 1.0  # Scaled to each attack's reach (see _update_telegraph)
		ring.bottom_radius = 1.0
	_stomp_cooldown = stomp_cooldown * 0.5
	_lunge_cooldown = lunge_cooldown * 0.5
	_spit_cooldown = spit_cooldown * 0.6
	_cast_cooldown = cast_cooldown * 0.4
	hp = max_hp
	_dress_element()
	_dress_core()


func _physics_process(delta: float) -> void:
	if not Net.decides():
		return
	if not is_awake or is_defeated or Net.waiting_for_load() or PerkDirector.halted():
		if PerkDirector.halted():
			velocity.x = 0.0
			velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_send_state()
		return

	_state_time += delta
	_stomp_cooldown = max(_stomp_cooldown - delta, 0.0)
	_spit_cooldown = max(_spit_cooldown - delta, 0.0)
	_kick_cooldown = max(_kick_cooldown - delta, 0.0)
	_lunge_cooldown = max(_lunge_cooldown - delta, 0.0)
	_swell_cooldown = max(_swell_cooldown - delta, 0.0)
	_cast_cooldown = max(_cast_cooldown - delta, 0.0)
	_update_poise(delta)

	match state:
		State.IDLE: _state_idle()
		State.HOP_PREP: _state_hop_prep()
		State.HOP: _state_hop(delta)
		State.STOMP_WINDUP: _state_stomp_windup()
		State.STOMP_RISE: _state_stomp_rise(delta)
		State.STOMP_HANG: _state_stomp_hang(delta)
		State.STOMP_FALL: _state_stomp_fall()
		State.RECOVER: _state_recover()
		State.STAGGERED: _state_staggered()
		State.SPIT_WINDUP: _state_spit_windup()
		State.LUNGE_WINDUP: _state_lunge_windup()
		State.LUNGE: _state_lunge(delta)
		State.SWELL_WINDUP: _state_swell_windup()
		State.SWELL: _state_swell()
		State.CAST_WINDUP: _state_cast_windup()
		State.WARP: _state_warp()

	if state != State.WARP:
		_touch_ball()
	_send_state()


func _process(delta: float) -> void:
	# Every machine counts down itself, so everyone's health bar appears together
	if not is_awake and not wait_for_players:
		start_delay -= delta
		if start_delay <= 0.0:
			is_awake = true
			awakened.emit()
	if not Net.decides():
		_motion.play(self, delta)
		_state_time += delta  # Clients don't run the states, but the visuals time them
	elif state == State.DEAD:
		_state_time += delta  # Physics has stopped, but the fade-out times itself
	# Gone through a portal while warping
	visual.visible = state != State.WARP
	if _aura:
		_aura.visible = visual.visible
	_update_squash(delta)
	_update_core()
	_update_color(delta)
	_update_telegraph()


# ===== STATES =====

func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	if Net.in_session() and Net.is_server and Net.match_synced:
		_net_phase.rpc(new_state)
	_on_state_entered(new_state)


## Visual kicks for a state, run on every machine.
func _on_state_entered(new_state: State) -> void:
	match new_state:
		State.HOP:
			_squash_vel += 4.0  # Stretch up on takeoff
		State.STOMP_RISE:
			_squash_vel += 8.0
		State.IDLE:
			_squash_vel -= 5.0  # Splat on landing
		State.RECOVER:
			_squash_vel -= 12.0  # Landed a stomp
			Sfx.play(&"boss_stomp", global_position)
			CameraShake.add(CameraShake.HEAVY, global_position)
			SlimeElement.show_burst(element, global_position, stomp_radius)
			if SlimeElement.POOLS.has(element):
				get_parent().add_child(SlimePool3D.make(global_position, element, glob_radius * STOMP_POOL_SCALE, POOL_TIME))
		State.STAGGERED:
			_squash_vel -= 10.0
		State.DEAD:
			_squash_vel -= 6.0
		State.SPIT_WINDUP:
			_squash_vel += 2.0
		State.LUNGE:
			_squash_vel += 6.0
		State.SWELL:
			_squash_vel += 6.0
			Sfx.play(&"hit_slime", global_position)
			SlimeElement.show_burst(element, global_position, swell_radius)
		State.CAST_WINDUP:
			_squash_vel += 3.0
			Sfx.play(&"spell_impact", global_position, 0.6)
		State.WARP:
			# Sinks into a portal where it stands; comes out over its target
			_portal(global_position + Vector3.UP * HEIGHT * 0.5)
			Sfx.play(&"spell_impact", global_position, 0.5)
		State.STOMP_HANG:
			if _warping:
				_warping = false
				_portal(Vector3(_stomp_target.x, _ground_y + WARP_HEIGHT + HEIGHT * 0.5, _stomp_target.z))
				Sfx.play(&"spell_impact", _stomp_target, 0.5)
	_warping = new_state == State.WARP


func _state_idle() -> void:
	_slide_shove()
	if _state_time < _rest_time:
		return
	_choose_action()


func _state_hop_prep() -> void:
	_slide_shove()
	if _state_time >= HOP_PREP_TIME:
		velocity = _move_dir * hop_speed + Vector3.UP * hop_velocity
		_set_state(State.HOP)


func _state_hop(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	if is_on_floor() and _state_time > 0.05:
		_land()


func _state_stomp_windup() -> void:
	_slide_shove()
	# Keep following the target while crouched, so the leap is aimed late
	var target: Node3D = _target_player()
	if target:
		_stomp_target = _clamp_stomp_target(target.global_position)
	if _state_time >= STOMP_WINDUP_TIME:
		_ground_y = global_position.y
		var rise_time: float = STOMP_JUMP_VELOCITY / _gravity()
		var travel: Vector3 = _flat(_stomp_target - global_position)
		velocity = travel / rise_time + Vector3.UP * STOMP_JUMP_VELOCITY
		_set_state(State.STOMP_RISE)


func _state_stomp_rise(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	if velocity.y <= 0.0:
		velocity = Vector3.ZERO
		_set_state(State.STOMP_HANG)


func _state_stomp_hang(_delta: float) -> void:
	# Drift over the target, slowly enough that a quick player can get out
	var target: Node3D = _target_player()
	if target:
		var to_target: Vector3 = _flat(target.global_position - global_position)
		velocity = to_target.limit_length(STOMP_HANG_TRACKING)
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	if _state_time >= STOMP_HANG_TIME:
		velocity = Vector3.DOWN * STOMP_FALL_SPEED
		_set_state(State.STOMP_FALL)


func _state_stomp_fall() -> void:
	velocity = Vector3.DOWN * STOMP_FALL_SPEED
	move_and_slide()
	if is_on_floor():
		velocity = Vector3.ZERO
		_stomp_shockwave()
		_stomp_cooldown = stomp_cooldown
		_set_state(State.RECOVER)


func _state_recover() -> void:
	_slide_shove()
	if _state_time >= STOMP_RECOVER_TIME:
		_rest_time = hop_rest_min
		_set_state(State.IDLE)


func _state_staggered() -> void:
	_slide_shove()
	if _state_time >= stagger_duration:
		_rest_time = hop_rest_min
		_set_state(State.IDLE)


func _state_spit_windup() -> void:
	_slide_shove()
	if _state_time >= SPIT_WINDUP_TIME:
		_spit()
		_spit_cooldown = spit_cooldown
		_rest_time = hop_rest_max
		_set_state(State.IDLE)


func _state_lunge_windup() -> void:
	_slide_shove()
	var target: Node3D = _target_player()
	if target and _state_time < LUNGE_WINDUP_TIME - LUNGE_AIM_LOCK:
		var to_target: Vector3 = _flat(target.global_position - global_position)
		if to_target.length() > 0.01:
			_move_dir = to_target.normalized()
	if _state_time >= LUNGE_WINDUP_TIME:
		# Carry it a little past where the target stood, up to lunge_distance
		var reach: float = lunge_distance
		if target:
			reach = min(reach, _flat(target.global_position - global_position).length() + 2.0)
		velocity = _move_dir * reach / LUNGE_AIR_TIME + Vector3.UP * _gravity() * LUNGE_AIR_TIME * 0.5
		_lunge_hits.clear()
		_set_state(State.LUNGE)


func _state_lunge(delta: float) -> void:
	_apply_gravity(delta)
	move_and_slide()
	_lunge_strike()
	if is_on_floor() and _state_time > 0.05:
		velocity = Vector3.ZERO
		_ground_y = global_position.y
		_lunge_cooldown = lunge_cooldown
		_rest_time = LUNGE_RECOVER_TIME
		_set_state(State.IDLE)


func _state_swell_windup() -> void:
	_slide_shove()
	if _state_time >= SWELL_WINDUP_TIME:
		_swell_burst()
		_swell_cooldown = swell_cooldown
		_set_state(State.SWELL)


func _state_swell() -> void:
	_slide_shove()
	if _state_time >= SWELL_TIME:
		_rest_time = hop_rest_max
		_set_state(State.IDLE)


func _state_cast_windup() -> void:
	_slide_shove()
	if _state_time < _cast_windup_time():
		return
	_cast_cooldown = cast_cooldown * randf_range(0.85, 1.15)
	if element == SlimeElement.Kind.VOID:
		_start_warp()
		return
	_cast()
	_rest_time = hop_rest_max
	_set_state(State.IDLE)


## Void: hidden, hanging over where it'll drop until the warp's over.
func _state_warp() -> void:
	velocity = Vector3.ZERO
	if _state_time >= WARP_TIME:
		_set_state(State.STOMP_HANG)


## Count down to poise recovering, and stagger once it's broken and grounded.
func _update_poise(delta: float) -> void:
	if _poise_reset_wait > 0.0:
		_poise_reset_wait -= delta
		if _poise_reset_wait <= 0.0:
			_poise_damage = 0.0
	# A stagger cuts a spit short: hitting it hard enough stops the minions coming
	if _poise_broken and state in [State.IDLE, State.HOP_PREP, State.STOMP_WINDUP, State.RECOVER,
			State.SPIT_WINDUP, State.LUNGE_WINDUP, State.SWELL_WINDUP, State.CAST_WINDUP]:
		_poise_broken = false
		_poise_damage = 0.0
		velocity = Vector3.ZERO
		_set_state(State.STAGGERED)


func _land() -> void:
	velocity = Vector3.ZERO
	_ground_y = global_position.y
	_rest_time = randf_range(hop_rest_min, hop_rest_max)
	_set_state(State.IDLE)


# ===== DECISIONS =====

## On the ground and rested: dribble the ball if it's close, burst if it's
## being crowded, otherwise go after its target (see _target_player),
## casting its spell, stomping or lunging at them if they're in range.
func _choose_action() -> void:
	var ball: Ball3D = _free_ball()
	if ball and _flat(ball.global_position - global_position).length() < ball_interest_range:
		_move_dir = _dribble_direction(ball)
		_set_state(State.HOP_PREP)
		return

	var target: Node3D = _target_player()
	if not target:
		_rest_time = hop_rest_max
		_state_time = 0.0
		return
	if _swell_cooldown <= 0.0 and _players_within(swell_trigger_range):
		_set_state(State.SWELL_WINDUP)
		return
	_forget_dead_minions()
	if _spit_cooldown <= 0.0 and _minions.size() < max_minions and minion_scene:
		_set_state(State.SPIT_WINDUP)
		return
	var to_target: Vector3 = _flat(target.global_position - global_position)
	if _cast_cooldown <= 0.0 and to_target.length() < cast_range:
		_set_state(State.CAST_WINDUP)
		return
	if _stomp_cooldown <= 0.0 and to_target.length() < stomp_trigger_range:
		_stomp_target = _clamp_stomp_target(target.global_position)
		_set_state(State.STOMP_WINDUP)
		return
	_move_dir = to_target.normalized()
	if _lunge_cooldown <= 0.0 and to_target.length() < lunge_trigger_range:
		_set_state(State.LUNGE_WINDUP)
		return
	# A little randomness so it doesn't beeline like a robot
	_move_dir = _move_dir.rotated(Vector3.UP, randf_range(-0.35, 0.35))
	_set_state(State.HOP_PREP)


## Which way to hop to push the ball toward the nearest goal: get behind it
## first, then hop through it.
func _dribble_direction(ball: Ball3D) -> Vector3:
	var goal_dir: Vector3 = _flat(_goal_aim(ball) - ball.global_position).normalized()
	var setup_point: Vector3 = ball.global_position - goal_dir * DRIBBLE_SETUP_OFFSET
	var to_ball: Vector3 = _flat(ball.global_position - global_position)
	var to_setup: Vector3 = _flat(setup_point - global_position)
	# Already lined up behind it: push straight through toward the goal
	if to_ball.normalized().dot(goal_dir) > 0.6 or to_setup.length() < 1.0:
		return goal_dir
	# Otherwise swing around to the setup point, going around the ball rather
	# than through it (which would knock it the wrong way)
	var dir: Vector3 = to_setup.normalized()
	var side: Vector3 = goal_dir.cross(Vector3.UP)
	if to_ball.length() < DRIBBLE_SETUP_OFFSET + 1.0 and dir.dot(to_ball.normalized()) > 0.3:
		dir = (dir + side * sign(side.dot(-to_ball)) * 1.5).normalized()
	return dir


# ===== ATTACKS =====

## Mid-lunge: bowl over anyone it runs into (once each), flinging them
## along the lunge and out to the side they were on.
func _lunge_strike() -> void:
	for player: PlayerClass3D in _players():
		if player.is_dead() or _lunge_hits.has(player):
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y < -1.0 or offset.y > HEIGHT:
			continue
		var flat: Vector3 = _flat(offset)
		if flat.length() > RADIUS + PLAYER_RADIUS + 0.3:
			continue
		_lunge_hits.append(player)
		var side: Vector3 = flat.normalized() if flat.length() > 0.01 else Vector3.ZERO
		if Combat.strike(player, _move_dir + side * 0.5, lunge_damage, lunge_knockback, lunge_pop,
				-1.0, null, SlimeElement.knock_down(element)):
			SlimeElement.afflict(player, element)


## Burst outward: everyone near enough gets blasted away, harder the closer
## they are. Players in the air above it are clear.
func _swell_burst() -> void:
	for player: PlayerClass3D in _players():
		if player.is_dead():
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y < -1.0 or offset.y > HEIGHT * SWELL_SCALE:
			continue
		var dist: float = _flat(offset).length()
		if dist > swell_radius:
			continue
		var falloff: float = 1.0 - 0.4 * dist / swell_radius
		if Combat.strike(player, _flat(offset), swell_damage * falloff,
				swell_knockback * falloff, swell_pop):
			SlimeElement.afflict(player, element)


func _stomp_shockwave() -> void:
	for player: PlayerClass3D in _players():
		var offset: Vector3 = player.global_position - global_position
		if offset.y > STOMP_DODGE_HEIGHT + 1.0:  # Player origin sits ~1m up
			continue
		var dist: float = _flat(offset).length()
		if dist > stomp_radius:
			continue
		var falloff: float = 1.0 - 0.5 * dist / stomp_radius
		if Combat.strike(player, _flat(offset), stomp_damage * falloff,
				stomp_knockback * falloff, stomp_pop):
			# Frost freezes those it lands right on
			SlimeElement.afflict(player, element, 2.0 if dist < stomp_radius * 0.5 else 1.0)
	var ball: Ball3D = _free_ball()
	if ball:
		var offset: Vector3 = _flat(ball.global_position - global_position)
		if offset.length() < stomp_radius:
			var falloff: float = 1.0 - 0.5 * offset.length() / stomp_radius
			var dir: Vector3 = offset.normalized() if offset.length() > 0.01 else Vector3.FORWARD
			Combat.push(ball, (dir + Vector3.UP * 0.8) * stomp_ball_impulse * falloff)
	_kick_cooldown = KICK_COOLDOWN


# ===== SPELLS =====

func _cast_windup_time() -> float:
	return NOVA_WINDUP_TIME if element == SlimeElement.Kind.FROST else CAST_WINDUP_TIME


## Server/offline: its element's spell (a void warp aside, see _start_warp),
## shown everywhere.
func _cast() -> void:
	match element:
		SlimeElement.Kind.POISON, SlimeElement.Kind.FIRE:
			Net.everywhere(_net_lob, _spell_spots(GLOB_FLIGHT_TIME * 0.5, 1, glob_count))
		SlimeElement.Kind.LIGHTNING:
			Net.everywhere(_net_storm, _spell_spots(STORM_WARN_TIME * STORM_LEAD, STORM_EXTRA_STRIKES, 0))
		SlimeElement.Kind.FROST:
			_frost_nova()
			Net.everywhere(_net_nova)


## Where a spell lands, on the ground: on each living player in cast range
## (a little ahead of where they're running, `lead` seconds' worth), then at
## least `extra` more scattered around the slime, and more until there are
## `at_least`.
func _spell_spots(lead: float, extra: int, at_least: int) -> PackedVector3Array:
	var spots := PackedVector3Array()
	for player: PlayerClass3D in _players():
		if player.is_dead() or _flat(player.global_position - global_position).length() > cast_range:
			continue
		var at: Vector3 = player.global_position + _flat(player.velocity) * lead
		spots.append(Vector3(at.x, _ground_y, at.z))
	var total: int = maxi(spots.size() + extra, at_least)
	while spots.size() < total:
		var out: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(RADIUS + 1.0, GLOB_SCATTER)
		spots.append(Vector3(global_position.x + out.x, _ground_y, global_position.z + out.z))
	return spots


## Poison and fire, on every machine: globs fly out of its top to `spots`,
## one after another. Only the server's hurt.
@rpc("authority", "call_local", "reliable")
func _net_lob(spots: PackedVector3Array) -> void:
	if is_defeated:
		return
	_squash_vel -= 6.0
	var fire: bool = element == SlimeElement.Kind.FIRE
	Sfx.play(&"fireball" if fire else &"boss_spit", global_position)
	var mouth: Vector3 = global_position + Vector3.UP * HEIGHT
	for i in spots.size():
		var glob := SlimeGlob3D.make(mouth, spots[i], element, GLOB_FLIGHT_TIME + i * 0.1)
		glob.radius = glob_radius
		glob.damage = glob_damage
		glob.knockback = glob_knockback
		glob.pool_time = POOL_TIME
		glob.attacker = self
		glob.real = Net.decides()
		get_parent().add_child(glob)


## Lightning, on every machine: strikes marked out at `spots`. Only the
## server's hurt.
@rpc("authority", "call_local", "reliable")
func _net_storm(spots: PackedVector3Array) -> void:
	if is_defeated:
		return
	_squash_vel += 6.0
	Vfx.play(&"lightning", global_position, Vector3.FORWARD, false, RADIUS * 2.0, SlimeElement.COLORS[element])
	Sfx.play(&"spell_impact", global_position)
	for at: Vector3 in spots:
		var strike := LightningStrike3D.make(at, storm_radius, STORM_WARN_TIME, SlimeElement.COLORS[element])
		strike.damage = storm_damage
		strike.knock_down = SlimeElement.knock_down(element)
		strike.attacker = self
		strike.real = Net.decides()
		get_parent().add_child(strike)


## Frost, server/offline: everyone on the ground within nova_radius is hit
## and chilled; those within nova_freeze_radius are frozen solid.
func _frost_nova() -> void:
	for player: PlayerClass3D in _players():
		if player.is_dead():
			continue
		var offset: Vector3 = player.global_position - global_position
		if offset.y > STOMP_DODGE_HEIGHT + 1.0:  # Jumped it
			continue
		var dist: float = _flat(offset).length()
		if dist > nova_radius:
			continue
		if Combat.strike(player, _flat(offset), nova_damage, stomp_knockback * 0.4, 2.0):
			SlimeElement.afflict(player, element, 2.0 if dist < nova_freeze_radius else 1.0)


## Frost, on every machine: how the nova looks.
@rpc("authority", "call_local", "reliable")
func _net_nova() -> void:
	if is_defeated:
		return
	_squash_vel -= 10.0
	var color: Color = SlimeElement.COLORS[element]
	Vfx.play(&"impact", global_position, Vector3.FORWARD, false, nova_radius * 0.5, color)
	for i in 10:
		var out: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 10.0)
		Vfx.play(&"shatter", global_position + out * nova_radius * 0.75, out, false, 3.0, color)
	Sfx.play(&"ice_bolt", global_position, 0.6)
	Sfx.play(&"weapon_break", global_position, 0.5)
	CameraShake.add(CameraShake.HEAVY, global_position)


## Void, server/offline: sink into a portal and hang hidden over its
## target (as far as it can get toward them without passing through a
## wall), then drop on them like a stomp.
func _start_warp() -> void:
	var target: PlayerClass3D = _target_player()
	var at: Vector3 = _clear_warp_to(target.global_position) if target else global_position
	_stomp_target = Vector3(at.x, _ground_y, at.z)
	_set_state(State.WARP)  # The portal opens where it stands...
	velocity = Vector3.ZERO
	global_position = _stomp_target + Vector3.UP * WARP_HEIGHT  # ...and it's gone


## `to`, or short of the first wall (or boss cage) between it and the slime.
func _clear_warp_to(to: Vector3) -> Vector3:
	var lift: Vector3 = Vector3.UP * HEIGHT * 0.5
	var query := PhysicsRayQueryParameters3D.create(global_position + lift, Vector3(to.x, global_position.y, to.z) + lift, collision_mask, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	var back: Vector3 = _flat(global_position - hit.position).normalized() * (RADIUS + 0.5)
	return hit.position - lift + back


## A portal standing at `at`, open a moment (just for show).
func _portal(at: Vector3) -> void:
	var portal: Node3D = Vfx.attach(&"portal", get_parent(), Vector3.ZERO, 0.0, 1.0, SlimeElement.COLORS[element])
	if not portal:
		return
	portal.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * PORTAL_SIZE), at)
	get_tree().create_timer(PORTAL_HOLD).timeout.connect(Vfx.release.bind(portal))


## Drop minions that have popped (or been freed) from _minions.
func _forget_dead_minions() -> void:
	for i in range(_minions.size() - 1, -1, -1):
		if not is_instance_valid(_minions[i]) or _minions[i].is_dead:
			_minions.remove_at(i)


## Server/offline: launch spit_count minions from the top of the slime,
## each aimed at a random living player (or anywhere), and tell everyone.
func _spit() -> void:
	_forget_dead_minions()
	var targets: Array[PlayerClass3D] = []
	for player: PlayerClass3D in _players():
		if is_instance_valid(player) and not player.is_dead():
			targets.append(player)
	var names: PackedStringArray = []
	var launches: PackedVector3Array = []
	for i in mini(spit_count, max_minions - _minions.size()):
		var dir: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		if not targets.is_empty():
			var aim: Vector3 = _flat(targets.pick_random().global_position - global_position)
			if aim.length() > 0.01:
				dir = aim.normalized().rotated(Vector3.UP, randf_range(-SPIT_SPREAD, SPIT_SPREAD))
		_minions_made += 1
		names.append("%s_Minion%d" % [name, _minions_made])
		launches.append(dir * spit_speed * randf_range(0.7, 1.2) + Vector3.UP * spit_lift)
	Net.everywhere(_net_spit, names, launches)


## Spawn the spat-out minions, on every machine, beside the boss in the
## arena (so they outlive its node for their pop).
@rpc("authority", "call_local", "reliable")
func _net_spit(names: PackedStringArray, launches: PackedVector3Array) -> void:
	_squash_vel -= 8.0  # Deflates as they fly out
	Sfx.play(&"boss_spit", global_position)
	var mouth: Vector3 = global_position + Vector3.UP * HEIGHT
	for i in names.size():
		var minion: SlimeMinion3D = minion_scene.instantiate()
		minion.name = names[i]
		minion.element = element
		minion.position = mouth
		get_parent().add_child(minion)
		if Net.decides():
			minion.launch(launches[i])
		_minions.append(minion)


## Touching the ball swallows it (see swallows_ball), or knocks it toward
## the nearest goal, as long as the slime is behind it (otherwise it just
## bounces off).
func _touch_ball() -> void:
	if _kick_cooldown > 0.0:
		return
	var ball: Ball3D = _free_ball()
	if not ball:
		return
	var offset: Vector3 = ball.global_position - global_position
	if offset.y > HEIGHT + BALL_RADIUS:
		return
	var flat: Vector3 = _flat(offset)
	if flat.length() > RADIUS + BALL_RADIUS + 0.3:
		return
	if swallows_ball and drop == BossDrop.Kind.NONE and not ball is Skull3D:
		var bomb_type: int = SlimeElement.BOMB_TYPES.get(element, randi() % Bomb3D.Type.size()) if ball is Bomb3D else -1
		var fuse: float = ball.fuse_left if ball is Bomb3D else -1.0
		Net.everywhere(_net_swallow, String(ball.name), bomb_type, fuse)
		return
	var goal_dir: Vector3 = _flat(_goal_aim(ball) - ball.global_position).normalized()
	if flat.normalized().dot(goal_dir) < 0.0:
		return
	_kick_cooldown = KICK_COOLDOWN
	Combat.push(ball, goal_dir * kick_impulse + Vector3.UP * kick_lift)


## On every machine: gulp `ball_name` down. It floats in the core and
## comes back out when the boss is beaten. A bomb's fuse stops at `fuse`
## (as the server had it), and it turns into `bomb_type`.
@rpc("authority", "call_local", "reliable")
func _net_swallow(ball_name: String, bomb_type: int, fuse: float) -> void:
	var game: Game3D_Class = Global.Game3D
	var ball: Ball3D = game.get_node_or_null(ball_name) as Ball3D if game else null
	if not ball or is_defeated:
		return
	var was_type: int = ball.type if ball is Bomb3D else -1
	game._remove_ball(ball)
	_squash_vel += 6.0  # Bulges as it goes down
	Sfx.play(&"boss_spit", global_position)
	if was_type < 0:
		drop = BossDrop.Kind.BALL
		core.visible = true
		game.scoreboard.announce("%s swallowed the ball! Beat it to get it back" % display_name, SlimeElement.COLORS[element])
	else:
		drop = BossDrop.Kind.BOMB
		_bomb_type = bomb_type
		_bomb_fuse = fuse
		_dress_core()
		var text: String = "%s swallowed the bomb! Beat it to get it back" % display_name
		if bomb_type != was_type:
			text = "%s swallowed the bomb and turned it into a %s bomb!" % [display_name, Bomb3D.NAMES[bomb_type]]
		game.scoreboard.announce(text, Bomb3D.COLORS[bomb_type])
	game._update_phase()


## Called by Combat.strike for every attack that lands on the boss.
## `attacker` gets the kill if this hit finishes it. Online the server keeps
## the HP, so other machines pass their hits on to it.
func receive_hit(_dir: Vector3, damage: float, knockback_velocity: Vector3, attacker: Node3D = null) -> bool:
	if is_defeated:
		return false
	wake()
	if not Net.decides():
		if Net.match_synced:
			_request_hit.rpc_id(Net.SERVER_ID, damage, knockback_velocity)
		return true
	Sfx.play_everywhere(&"hit_slime", global_position)
	Vfx.play_everywhere(&"hit", global_position, knockback_velocity)  # Its dir is lost when passed to the server
	receive_impulse(knockback_velocity * HIT_SHOVE_RATIO)
	if state == State.STAGGERED:
		damage *= staggered_damage_multiplier
	elif not _poise_broken:
		_poise_damage += damage
		_poise_reset_wait = poise_reset_delay
		_poise_broken = _poise_damage >= poise_max
	if Global.Game3D:
		Global.Game3D.record_damage(self, attacker, minf(damage, hp))
	Vfx.damage_number_everywhere(self, Vector3.UP * HEIGHT, minf(damage, hp), attacker)
	_set_hp(hp - damage)
	if hp <= 0.0:
		var killer: String = String(attacker.name) if attacker is PlayerClass3D else ""
		Net.everywhere(_net_defeated, killer)
	return true


## Start the start_delay countdown if it was waiting for players.
func wake() -> void:
	wait_for_players = false


func _set_hp(value: float) -> void:
	value = max(value, 0.0)
	if value < hp:
		_flash = HIT_FLASH_TIME
	hp = value
	if Net.in_session() and Net.is_server and Net.match_synced:
		_net_hp.rpc(hp)


## Beaten, on every machine: stop, deflate, and drop the ball.
func _defeat(killer_name: String) -> void:
	if is_defeated:
		return
	is_defeated = true
	_set_state(State.DEAD)
	velocity = Vector3(0.0, min(velocity.y, 0.0), 0.0)
	collision_layer = 0  # Players and the ball pass through; it still lands on the floor
	telegraph.visible = false
	visual.visible = true
	if _aura:
		Vfx.release(_aura)
		_aura = null
	# Its minions go down with it
	_forget_dead_minions()
	for minion: SlimeMinion3D in _minions:
		minion.die()
	_minions.clear()
	Vfx.play(&"nuke", global_position, Vector3.FORWARD, false, NUKE_SIZE)
	CameraShake.add(CameraShake.HEAVY, global_position)
	if drop != BossDrop.Kind.NONE and Global.Game3D:
		core.visible = false
		var dir: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var dropped: Ball3D = Global.Game3D.spawn_ball(core.global_position, (Vector3.UP * 2.0 + dir) * release_impulse, drop)
		if dropped is Bomb3D:
			var fuse: float = maxf(_bomb_fuse + Bomb3D.BOSS_FUSE_BONUS, Bomb3D.MIN_RELEASE_FUSE) if _bomb_fuse >= 0.0 else Bomb3D.FUSE_TIME
			dropped.setup(_drop_bomb_type(), fuse)
	var killer: PlayerClass3D = Global.Game3D.player_named(killer_name) if Global.Game3D else null
	defeated.emit(killer)
	await get_tree().create_timer(DEATH_TIME).timeout
	queue_free()


## Hit by a punch, sword or thrown weapon (see Combat.push). It's heavy, so
## it only slides a little.
func receive_impulse(impulse: Vector3) -> void:
	if not Net.decides():
		_request_push.rpc_id(Net.SERVER_ID, impulse)
		return
	_shove = (_shove + _flat(impulse) * SHOVE_RESISTANCE).limit_length(SHOVE_MAX)
	_squash_vel -= 2.0


func _slide_shove() -> void:
	var delta: float = get_physics_process_delta_time()
	_apply_gravity(delta)
	velocity.x = _shove.x
	velocity.z = _shove.z
	move_and_slide()
	_shove = _shove.move_toward(Vector3.ZERO, SHOVE_FRICTION * delta)


# ===== HELPERS =====

func _gravity() -> float:
	return get_gravity().length() * gravity_scale


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Whether any living player is within `range_` of its center.
func _players_within(range_: float) -> bool:
	for player: PlayerClass3D in _players():
		if not player.is_dead() and _flat(player.global_position - global_position).length() < range_:
			return true
	return false


func _clamp_stomp_target(pos: Vector3) -> Vector3:
	var travel: Vector3 = _flat(pos - global_position).limit_length(STOMP_MAX_DISTANCE)
	return global_position + travel


func _players() -> Array[PlayerClass3D]:
	if Global.Game3D:
		return Global.Game3D.players
	var found: Array[PlayerClass3D] = []
	for node: Node in get_tree().get_nodes_in_group("Player"):
		if node is PlayerClass3D:
			found.append(node)
	return found


## Who to go after: the nearest player on the team leading in kills, or
## the nearest player at all when nobody leads.
func _target_player() -> PlayerClass3D:
	if Global.Game3D:
		var leaders: Array[PlayerClass3D] = Global.Game3D.leader_players()
		if not leaders.is_empty():
			return _nearest_of(leaders)
	return _nearest_of(_players())


func _nearest_of(candidates: Array[PlayerClass3D]) -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = INF
	for player: PlayerClass3D in candidates:
		if player.is_dead():
			continue
		var dist: float = _flat(player.global_position - global_position).length()
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


## The nearest ball that's loose on the pitch (not in someone's hands).
func _free_ball() -> Ball3D:
	if not Global.Game3D:
		return null
	var best: Ball3D = null
	var best_dist: float = INF
	for ball: Ball3D in Global.Game3D.balls:
		if not is_instance_valid(ball) or not ball.is_inside_tree():
			continue
		var dist: float = global_position.distance_to(ball.global_position)
		if dist < best_dist:
			best_dist = dist
			best = ball
	return best


## Where to send the ball: the net of whichever goal the slime is nearest.
func _goal_aim(ball: Ball3D) -> Vector3:
	var best: Goal3D = null
	var best_dist: float = INF
	for goal: Goal3D in get_tree().get_nodes_in_group("Goal"):
		var dist: float = global_position.distance_to(goal.global_position)
		if dist < best_dist:
			best_dist = dist
			best = goal
	return best.net.global_position if best else ball.global_position + Vector3.FORWARD


# ===== VISUALS =====

func _update_squash(delta: float) -> void:
	_wobble_time += delta
	var target: float = 1.0
	match state:
		State.IDLE:
			target = 1.0 + 0.04 * sin(_wobble_time * 5.0)
		State.HOP_PREP:
			target = 0.8
		State.HOP:
			target = 1.12 if velocity.y > 0.0 else 1.04
		State.STOMP_WINDUP:
			# Crouch lower and lower, shivering faster as it goes
			var t: float = clamp(_state_time / STOMP_WINDUP_TIME, 0.0, 1.0)
			target = lerp(0.9, 0.6, t) + 0.03 * sin(_wobble_time * lerp(20.0, 60.0, t))
		State.STOMP_RISE:
			target = 1.25
		State.STOMP_HANG:
			target = 1.0
		State.STOMP_FALL:
			target = 1.35
		State.RECOVER:
			target = 0.85
		State.STAGGERED:
			# Slumped and swaying
			target = 0.7 + 0.05 * sin(_wobble_time * 8.0)
		State.SPIT_WINDUP:
			# Swell up taller and taller, gurgling faster as it goes
			var t: float = clamp(_state_time / SPIT_WINDUP_TIME, 0.0, 1.0)
			target = lerp(1.05, 1.35, t) + 0.04 * sin(_wobble_time * lerp(15.0, 45.0, t))
		State.LUNGE_WINDUP:
			var t: float = clamp(_state_time / LUNGE_WINDUP_TIME, 0.0, 1.0)
			target = lerp(0.95, 0.75, t) + 0.03 * sin(_wobble_time * 40.0)
		State.LUNGE:
			target = 0.85  # Stretched long and low
		State.SWELL_WINDUP:
			var t: float = clamp(_state_time / SWELL_WINDUP_TIME, 0.0, 1.0)
			target = lerp(0.95, 0.7, t) + 0.04 * sin(_wobble_time * lerp(25.0, 70.0, t))
		State.CAST_WINDUP:
			# Rearing up tall, bubbling faster as it goes
			var t: float = clamp(_state_time / _cast_windup_time(), 0.0, 1.0)
			target = lerp(1.0, 1.3, t) + 0.05 * sin(_wobble_time * lerp(20.0, 60.0, t))
		State.DEAD:
			target = 0.15
	_squash_vel += (target - _squash) * SQUASH_STIFFNESS * delta
	_squash_vel *= max(1.0 - SQUASH_DAMPING * delta, 0.0)
	_squash = clamp(_squash + _squash_vel * delta, 0.4, 1.6)
	var side: float = 1.0 / sqrt(_squash)
	visual.scale = Vector3(side, _squash, side) * _puff()
	visual.position = _lean()


## Uniform swelling on top of the squash: a little while winding up a
## burst, then a quick puff out and back for the burst itself.
func _puff() -> float:
	match state:
		State.SWELL_WINDUP:
			return lerp(1.0, 1.1, clamp(_state_time / SWELL_WINDUP_TIME, 0.0, 1.0))
		State.SWELL:
			var t: float = clamp(_state_time / SWELL_TIME, 0.0, 1.0)
			if t < 0.2:
				return lerp(1.1, SWELL_SCALE, t / 0.2)
			return lerp(SWELL_SCALE, 1.0, (t - 0.2) / 0.8)
	return 1.0


## Rearing back away from a lunge's aim, then thrown forward into it.
func _lean() -> Vector3:
	match state:
		State.LUNGE_WINDUP:
			var t: float = clamp(_state_time / LUNGE_WINDUP_TIME, 0.0, 1.0)
			return -_move_dir * LUNGE_LEAN * ease(t, 0.5)
		State.LUNGE:
			return _move_dir * LUNGE_LEAN * 0.5
	return Vector3.ZERO


## Its element's colors (body and danger zone) and aura.
func _dress_element() -> void:
	_body_color = SlimeElement.BODY_COLORS[element]
	var mat: StandardMaterial3D = telegraph.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(SlimeElement.COLORS[element], mat.albedo_color.a)
	var look: Array = SlimeElement.AURAS[element]
	_aura = Vfx.attach(look[0], self, look[2], 0.0, look[1])


## Show the drop in the core: the ball mesh it has already, or the drop's
## own model in its place (a bomb in its type's colors).
func _dress_core() -> void:
	core.visible = drop != BossDrop.Kind.NONE
	if _core_model:
		_core_model.queue_free()
		_core_model = null
	var model: PackedScene = BossDrop.model_of(drop)
	if model:
		core.mesh = null
		_core_model = model.instantiate()
		core.add_child(_core_model)
		if _core_model is BombModel3D:
			_core_model.set_color(Bomb3D.COLORS[_drop_bomb_type()])


## The type of bomb it holds or drops.
func _drop_bomb_type() -> Bomb3D.Type:
	if _bomb_type >= 0:
		return _bomb_type as Bomb3D.Type
	return SlimeElement.BOMB_TYPES.get(element, Bomb3D.type_for(String(name)))


## The drop floating inside: stays round however the slime squashes, and
## drifts lazily around the middle.
func _update_core() -> void:
	if not core.visible:
		return
	var inv: Vector3 = Vector3.ONE / visual.scale
	core.scale = inv
	var bob := Vector3(sin(_wobble_time * 1.3) * 0.5, sin(_wobble_time * 2.1), cos(_wobble_time * 1.7) * 0.5) * CORE_BOB
	# Squashing pushes the core down with the body, but never out of it
	core.position = _core_rest + bob * inv
	core.rotation.y = _wobble_time * 0.6


## Hit flash, and fading out once beaten.
func _update_color(delta: float) -> void:
	if not _body_material:
		return
	_flash = max(_flash - delta, 0.0)
	var brighten: float = 0.7 * _flash / HIT_FLASH_TIME
	if state == State.STAGGERED:
		brighten = max(brighten, 0.15 + 0.15 * sin(_wobble_time * 10.0))  # Dazed shimmer
	var color: Color = _body_color
	if state == State.CAST_WINDUP:
		# Glowing brighter with its magic as the spell builds
		var t: float = clamp(_state_time / _cast_windup_time(), 0.0, 1.0)
		color = color.lerp(SlimeElement.COLORS[element], t * (0.6 + 0.3 * sin(_wobble_time * 20.0)))
	color = color.lerp(Color.WHITE, brighten)
	color.a = _body_color.a
	if state == State.DEAD:
		color.a *= clamp(1.0 - _state_time / DEATH_TIME, 0.0, 1.0)
	_body_material.albedo_color = color


## The danger zone on the ground while a stomp, burst or frost nova is
## coming (or a void drop).
func _update_telegraph() -> void:
	var stomping: bool = state in [State.STOMP_WINDUP, State.STOMP_RISE, State.STOMP_HANG, State.STOMP_FALL, State.WARP]
	var swelling: bool = state == State.SWELL_WINDUP
	var nova: bool = state == State.CAST_WINDUP and element == SlimeElement.Kind.FROST
	telegraph.visible = stomping or swelling or nova
	if not telegraph.visible:
		return
	var center: Vector3 = _stomp_target if state in [State.STOMP_WINDUP, State.WARP] else global_position
	telegraph.global_position = Vector3(center.x, _ground_y + 0.05, center.z)
	var reach: float = stomp_radius
	if swelling:
		reach = swell_radius
	elif nova:
		reach = nova_radius
	telegraph.scale = Vector3(reach, 1.0, reach)
	var mat: StandardMaterial3D = telegraph.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		# Pulse faster the closer it is to landing
		var speed: float = 25.0 if state in [State.STOMP_FALL, State.SWELL_WINDUP, State.CAST_WINDUP] else 10.0
		mat.albedo_color.a = 0.25 + 0.2 * sin(_wobble_time * speed)


# ===== NETWORK =====

func _send_state() -> void:
	if Net.in_session() and Net.is_server and Net.match_synced and _motion.should_send(global_transform):
		_net_state.rpc(NetInterpolator.now(), global_transform, _stomp_target, _ground_y, _move_dir)


@rpc("authority", "unreliable_ordered")
func _net_state(time: float, xform: Transform3D, stomp_target: Vector3, ground_y: float, aim: Vector3) -> void:
	_motion.push(time, xform)
	_stomp_target = stomp_target
	_ground_y = ground_y
	_move_dir = aim  # For the lunge's lean


@rpc("authority", "reliable")
func _net_phase(new_state: State) -> void:
	if is_defeated:
		return
	state = new_state
	_state_time = 0.0
	_on_state_entered(new_state)


@rpc("authority", "reliable")
func _net_hp(value: float) -> void:
	_set_hp(value)


@rpc("authority", "call_local", "reliable")
func _net_defeated(killer_name: String) -> void:
	_defeat(killer_name)


## A client's player hit the boss; the sender's player gets the credit.
@rpc("any_peer", "reliable")
func _request_hit(damage: float, knockback_velocity: Vector3) -> void:
	if Net.is_server:
		var attacker: PlayerClass3D = Global.Game3D.rpc_sender()
		receive_hit(Vector3.ZERO, Combat.vetted_damage(damage, attacker), knockback_velocity, attacker)


@rpc("any_peer", "reliable")
func _request_push(impulse: Vector3) -> void:
	if Net.is_server:
		receive_impulse(impulse)
