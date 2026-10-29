class_name Tower3D extends AnimatableBody3D
## A tower that comes up somewhere on the field partway through a match
## (see PitchGame3D), sunk into the ground as far as its scene has it (its
## root's height there). A team claims it by standing near it: while only
## one team's players are within capture_radius, its orb (the SphereMesh in
## the scene) fills from the bottom up in their color (faster with more of
## them). If another team arrives they drain that color first, then fill
## with their own; with both teams there it holds. Once full it's theirs:
## it rises to y = 0 and goes to work for them, by its Kind. The enemy can
## knock it down (any attack lands on it), which earns them coins (see
## PitchGame3D.tower_coins); its own team can repair it with coins at
## their altar (Altar3D's repair offer).
##
## Its name floats over it like a player's (NameTag): filled as far as the
## capture has got, in the capturing team's color, and as its health once
## it's claimed.
##
## Online the server runs it: who's capturing, its health, what it shoots
## or spawns. Everyone else is told (see Net.everywhere).

## Emitted on every machine as it falls: `by_team` knocked it down (-1 =
## nobody in particular). Its owner_team is still set.
signal fell(by_team: int)

enum Kind {
	STORM,    ## Calls telegraphed lightning down on enemy players in range
	STRIKER,  ## Zaps a loose ball in range toward the enemy goal
	SLIME,    ## Spits out slimes that hunt the enemy team
}

enum State {
	BURIED,   ## Up for grabs, all but its top in the ground
	RISING,   ## Claimed: growing out of the ground
	ACTIVE,   ## Up and working for its team
	FALLING,  ## Knocked down: sinking away
}

const NAMES: Dictionary[Kind, String] = {
	Kind.STORM: "Storm Tower",
	Kind.STRIKER: "Striker Tower",
	Kind.SLIME: "Slime Tower",
}
## Nobody's yet: the stone, and its name.
const NEUTRAL_COLOR := Color(0.55, 0.55, 0.58)
const FLASH_TIME := 0.12
## How often (s) the server tells everyone how the capture is going.
const CAPTURE_SEND_INTERVAL := 0.1
## Names float this far over its top.
const TAG_GAP := 1.0
const TAG_FONT_SIZE := 26
const TAG_BORDER := 8
const SINK_TIME := 1.6
## How white a hit flashes it.
const FLASH_STRENGTH := 0.7
## How much darker its column is where its health is gone.
const LOST_HP_DARKEN := 0.6
## The sparkle when it's repaired.
const REPAIR_COLOR := Color(0.4, 1.0, 0.5)
## A Storm Tower's crackling ball, this many times as wide as its orb.
const ORB_FX_SCALE := 1.3

## The orb: colored in from the bottom up, in world space, to
## `fill_height`, with a bright band at the edge; `flash` whitens it when
## it's hit.
const FILL_SHADER := """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.55, 0.55, 0.58, 1.0);
uniform vec4 fill_color : source_color = vec4(1.0);
uniform float fill_height = -1000.0;
uniform float flash = 0.0;
varying float world_y;
void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	bool filled = world_y < fill_height;
	vec3 color = filled ? fill_color.rgb : base_color.rgb;
	float edge = 1.0 - smoothstep(0.0, 0.3, abs(world_y - fill_height));
	ALBEDO = mix(color, vec3(1.0), flash);
	EMISSION = (filled ? fill_color.rgb * 0.25 : vec3(0.0)) + fill_color.rgb * edge * 1.5 + vec3(flash);
	ROUGHNESS = 0.8;
}
"""

@export var kind: Kind = Kind.STORM
@export var max_hp: float = 600.0
@export var rise_time: float = 3.0

@export_group("Capture")
## Players this close (flat, from its middle) count toward capturing it.
@export var capture_radius: float = 7.0
## Seconds for one player alone to fill it.
@export var capture_time: float = 8.0
## Each extra player on the team fills it this much faster (0.5 = half
## again as fast).
@export var extra_capturer_speed: float = 0.5
## Draining another team's color goes this many times as fast as filling.
@export var drain_speed: float = 1.5

@export_group("Storm")
## Calls a strike on the nearest enemy player this close.
@export var strike_range: float = 18.0
@export var strike_interval: float = 2.0
## Seconds its marker (LightningStrike3D) shows before it lands: time to
## get out.
@export var strike_warn_time: float = 1.0
@export var strike_radius: float = 3.0
@export var strike_damage: float = 25.0
@export var strike_knockback: float = 10.0
## Aims where the target will be after this share of the warning, if they
## keep going (0 = where they stand; 1 = full lead, hard to dodge).
@export_range(0.0, 1.0) var strike_lead: float = 0.4

@export_group("Striker")
@export var zap_range: float = 14.0
@export var zap_interval: float = 2.5
## How fast (m/s) a zap sends the ball toward the enemy goal, at least.
@export var zap_speed: float = 22.0
@export var zap_lift: float = 4.0

@export_group("Slime")
@export var minion_scene: PackedScene = preload("res://Entities/SlimeBoss/Minions/slime_minion.tscn")
@export var minion_interval: float = 8.0
@export var max_minions: int = 3
@export var minion_hp: float = 30.0
## Only spits while an enemy player is this close.
@export var minion_range: float = 30.0

## The team it works for, once claimed (-1 = nobody yet).
var owner_team: int = -1
var state: State = State.BURIED
var hp: float = 0.0
## Who's filling it, and how far (0-1). Shown everywhere; the server decides.
var capture_team: int = -1
var capture: float = 0.0

## Its top (m above its origin), for the name.
var _top: float = 0.0
## Where it starts (its scene's height), and rises from.
var _buried_y: float = 0.0
## Where it rises to: its lowest mesh on the ground, however it's built.
var _risen_y: float = 0.0
## A Storm Tower's crackling orb while it's up (Vfx "lightning_ball").
var _orb_fx: Node3D = null
## The orb that fills with the capturing team's color, and its look.
var _orb: MeshInstance3D
var _material: ShaderMaterial
## The rest of it (its column), which shows its health once it's claimed.
var _body: Array[MeshInstance3D] = []
var _body_material: ShaderMaterial
var _flash: float = 0.0
var _rise: float = 0.0
var _capture_send: float = 0.0
## Server/offline: seconds until it acts again (shoots, zaps, spits).
var _cooldown: float = 1.0
## Server/offline: the last team to hurt it, for credit if nobody's named.
var _last_hurt_by: int = -1
## Slimes it has spat out that are still about (every machine).
var _minions: Array[SlimeMinion3D] = []
var _minions_made: int = 0
var _tag_layer: CanvasLayer
var _tag: NameTag


func _ready() -> void:
	add_to_group("Tower")
	hp = max_hp
	_top = _measure_top()
	_buried_y = position.y
	_risen_y = -_measure_bottom()
	var shader := Shader.new()
	shader.code = FILL_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_body_material = ShaderMaterial.new()
	_body_material.shader = shader
	_orb = _find_orb()
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		if node == _orb:
			_orb.material_override = _material
		else:
			_body.append(node as MeshInstance3D)
			(node as MeshInstance3D).material_override = _body_material
	if not Net.is_server:
		_tag_layer = CanvasLayer.new()
		_tag_layer.layer = Nameplates3D.LAYER
		add_child(_tag_layer)
		_tag = NameTag.new()
		_tag.font_size = TAG_FONT_SIZE
		_tag.border = TAG_BORDER
		_tag.text = NAMES[kind].to_upper()
		_tag_layer.add_child(_tag)
	_update_look(0.0)


func _physics_process(delta: float) -> void:
	match state:
		State.RISING:
			_rise = minf(_rise + delta / rise_time, 1.0)
			position.y = lerpf(_buried_y, _risen_y, ease(_rise, 0.4))
			if _rise >= 1.0:
				state = State.ACTIVE
		State.FALLING:
			return
	var game: Game3D_Class = Global.Game3D
	if not Net.decides() or Net.waiting_for_load() or not game or game.match_over or PerkDirector.halted():
		return
	match state:
		State.BURIED:
			_tick_capture(delta, game)
		State.ACTIVE:
			_cooldown -= delta
			if _cooldown <= 0.0:
				_act(game)


func _process(delta: float) -> void:
	_update_look(delta)
	_place_tag()


# ===== CAPTURE =====

## Whether it's still up for grabs.
func is_capturable() -> bool:
	return state == State.BURIED


## Whether it's up (or coming up) for `team`.
func is_owned_by(team: int) -> bool:
	return owner_team == team and (state == State.RISING or state == State.ACTIVE)


## Server/offline: fill, drain or hold, by who's standing by it.
func _tick_capture(delta: float, game: Game3D_Class) -> void:
	var near: Dictionary[int, int] = {}
	for player: PlayerClass3D in game.players:
		if not is_instance_valid(player) or player.is_dead() or not player.slot:
			continue
		if _flat(player.global_position - global_position).length() <= capture_radius:
			near[player.slot.team] = near.get(player.slot.team, 0) + 1
	if near.size() == 1:
		var team: int = near.keys()[0]
		var rate: float = (1.0 + extra_capturer_speed * (near[team] - 1)) / capture_time
		if capture_team == team or capture <= 0.0:
			capture_team = team
			capture = minf(capture + rate * delta, 1.0)
		else:
			capture -= rate * drain_speed * delta
			if capture <= 0.0:
				capture = 0.0
				capture_team = team
	if capture >= 1.0:
		Net.everywhere(_claimed, capture_team)
		return
	_capture_send -= delta
	if _capture_send <= 0.0 and Net.in_session() and Net.match_synced:
		_capture_send = CAPTURE_SEND_INTERVAL
		_net_capture.rpc(capture_team, capture)


@rpc("authority", "unreliable_ordered")
func _net_capture(team: int, amount: float) -> void:
	capture_team = team
	capture = amount


## Every machine: `team` filled it. It's theirs, and up it comes.
@rpc("authority", "call_local", "reliable")
func _claimed(team: int) -> void:
	if state != State.BURIED:
		return
	owner_team = team
	capture_team = team
	capture = 1.0
	hp = max_hp
	state = State.RISING
	_rise = 0.0
	_cooldown = rise_time + 1.0
	Sfx.play(&"boss_stomp", global_position)
	CameraShake.add(CameraShake.HEAVY, global_position)
	Vfx.play(&"smoke", global_position, Vector3.FORWARD, false, 6.0)
	var game: Game3D_Class = Global.Game3D
	if game:
		game.scoreboard.announce("The %s claimed the %s!" % [Players.team_name(team), NAMES[kind]],
			Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()])
	if kind == Kind.STORM and _orb:
		_orb_fx = Vfx.attach(&"lightning_ball", _orb, _orb.get_aabb().get_center(), 0.0,
			_orb.get_aabb().size.x * ORB_FX_SCALE, _team_color())
	_update_repair_offers()


# ===== DAMAGE =====

## Called by Combat.strike for every attack that lands on it. Only a tower
## that's up can be hurt. Online the server keeps its health, so other
## machines pass their hits on.
func receive_hit(dir: Vector3, damage: float, _knockback_velocity: Vector3, attacker: Node3D = null,
		type: DamageType.Kind = DamageType.Kind.BLUNT) -> bool:
	if state != State.ACTIVE and state != State.RISING:
		return false
	if not Net.decides():
		if Net.match_synced:
			_request_hit.rpc_id(Net.SERVER_ID, damage, String(attacker.name) if attacker is PlayerClass3D else "", type)
		return true
	var by_team: int = Combat.team_of(attacker)
	if by_team == owner_team:
		return false
	if by_team >= 0:
		_last_hurt_by = by_team
	Sfx.play_everywhere(&"hit_wall", global_position + Vector3.UP * 2.0)
	Vfx.hit_everywhere(type, global_position + Vector3.UP * 2.0, dir, damage)
	Vfx.damage_number_everywhere(self, _muzzle() - global_position + Vector3.UP * 1.5, minf(damage, hp), attacker)
	_set_hp(hp - damage)
	if hp <= 0.0:
		Net.everywhere(_fallen, by_team if by_team >= 0 else _last_hurt_by)
	return true


@rpc("any_peer", "reliable")
func _request_hit(damage: float, attacker_name: String, type: int) -> void:
	if Net.is_server and Global.Game3D:
		# Unvetted or unnamed, it's the sender's own hit, so they can't hurt
		# their own tower.
		var attacker: PlayerClass3D = Global.Game3D.vetted_attacker(attacker_name)
		if not attacker:
			attacker = Global.Game3D.rpc_sender()
		receive_hit(Vector3.ZERO, Combat.vetted_damage(damage, attacker), Vector3.ZERO, attacker, DamageType.vetted(type))


## Server/offline: back up by `amount` HP (an altar repair).
func repair(amount: float) -> void:
	if Net.decides() and (state == State.ACTIVE or state == State.RISING):
		_set_hp(minf(hp + amount, max_hp))


## Missing this share of its health (0 = full).
func damage_share() -> float:
	return 1.0 - hp / max_hp if max_hp > 0.0 else 0.0


func _set_hp(value: float) -> void:
	if Net.in_session() and Net.match_synced:
		_net_hp.rpc(value)
	else:
		_net_hp(value)


@rpc("authority", "call_local", "reliable")
func _net_hp(value: float) -> void:
	if value < hp:
		_flash = FLASH_TIME
	elif value > hp:  # Repaired
		Vfx.play(&"shatter", _muzzle(), Vector3.FORWARD, false, 4.0, REPAIR_COLOR)
	hp = maxf(value, 0.0)


## Every machine: down it goes, and its slimes with it.
@rpc("authority", "call_local", "reliable")
func _fallen(by_team: int) -> void:
	if state == State.FALLING:
		return
	state = State.FALLING
	hp = 0.0
	collision_layer = 0
	Vfx.release(_orb_fx)
	for minion: SlimeMinion3D in _minions:
		if is_instance_valid(minion) and not minion.is_dead:
			minion.die()  # Only the server's counts
	Sfx.play(&"weapon_break", global_position)
	CameraShake.add(CameraShake.HEAVY, global_position)
	Vfx.play(&"explosion", global_position + Vector3.UP * 2.0, Vector3.FORWARD, false, 8.0)
	Vfx.play(&"smoke", global_position, Vector3.FORWARD, false, 8.0)
	fell.emit(by_team)
	_update_repair_offers()
	var tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(self, "position:y", -_top - 1.0, SINK_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


# ===== WORK =====

## Server/offline: do what its kind does, if there's anything to do it to.
func _act(game: Game3D_Class) -> void:
	match kind:
		Kind.STORM:
			_cooldown = strike_interval
			var target: PlayerClass3D = _nearest_enemy(game, strike_range)
			if target:
				var at: Vector3 = target.global_position + _flat(target.velocity) * strike_warn_time * strike_lead
				Net.everywhere(_call_strike, Vector3(at.x, 0.0, at.z))
			else:
				_cooldown = 0.3  # Keep an eye out
		Kind.STRIKER:
			_cooldown = zap_interval
			var ball: Ball3D = _ball_in_range(game)
			var goal: Goal3D = _goal_to_attack()
			if ball and goal:
				_zap(ball, goal)
			else:
				_cooldown = 0.3  # Keep an eye out
		Kind.SLIME:
			_cooldown = minion_interval
			_forget_dead_minions()
			if _minions.size() < max_minions and _nearest_enemy(game, minion_range):
				_minions_made += 1
				var out: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
				Net.everywhere(_spit, "%s_Minion%d" % [name, _minions_made], out * 5.0 + Vector3.UP * 7.0)


## Every machine: a lightning strike marked out at `at`, landing after
## strike_warn_time. Only the server's hurts.
@rpc("authority", "call_local", "reliable")
func _call_strike(at: Vector3) -> void:
	var strike := LightningStrike3D.make(at, strike_radius, strike_warn_time, _team_color())
	strike.damage = strike_damage
	strike.knockback = strike_knockback
	strike.team = owner_team
	strike.attacker = self
	strike.real = Net.decides()
	get_parent().add_child(strike)


## Server/offline: lightning knocks `ball` toward `goal`, there and then.
func _zap(ball: Ball3D, goal: Goal3D) -> void:
	Net.everywhere(_show_zap, ball.global_position)
	var toward: Vector3 = _flat(goal.net.global_position - ball.global_position).normalized()
	ball.redirect(toward, zap_speed, 0.0, zap_lift)
	Sfx.play_everywhere(&"hit_ball", ball.global_position)


## Every machine: the zap's lightning, down on the ball (just for show:
## the server moves the ball).
@rpc("authority", "call_local", "reliable")
func _show_zap(at: Vector3) -> void:
	get_parent().add_child(LightningStrike3D.make(at, 0.0, 0.0, _team_color()))


## Every machine: a slime of its team's flies out of its base.
@rpc("authority", "call_local", "reliable")
func _spit(minion_name: String, launch_velocity: Vector3) -> void:
	if not minion_scene or not is_inside_tree():
		return
	var minion: SlimeMinion3D = minion_scene.instantiate()
	minion.name = minion_name
	minion.team = owner_team
	minion.max_hp = minion_hp
	# Out of the orb: the tower's origin is below the floor once it's up
	minion.position = _muzzle() + _flat(launch_velocity).normalized() * 2.0
	get_parent().add_child(minion)
	minion.launch(launch_velocity)
	_minions.append(minion)
	Sfx.play(&"boss_spit", global_position)


func _forget_dead_minions() -> void:
	for i in range(_minions.size() - 1, -1, -1):
		if not is_instance_valid(_minions[i]) or _minions[i].is_dead:
			_minions.remove_at(i)


func _nearest_enemy(game: Game3D_Class, max_range: float) -> PlayerClass3D:
	var best: PlayerClass3D = null
	var best_dist: float = max_range
	for player: PlayerClass3D in game.players:
		if not is_instance_valid(player) or player.is_dead() or Combat.team_of(player) == owner_team:
			continue
		var dist: float = _flat(player.global_position - global_position).length()
		if dist < best_dist:
			best = player
			best_dist = dist
	return best


## A ball nobody's holding, in zap_range.
func _ball_in_range(game: Game3D_Class) -> Ball3D:
	for ball: Ball3D in game.balls:
		if is_instance_valid(ball) and not ball.holder \
				and _flat(ball.global_position - global_position).length() <= zap_range:
			return ball
	return null


## The goal its team scores in.
func _goal_to_attack() -> Goal3D:
	for goal: Goal3D in get_tree().get_nodes_in_group("Goal"):
		if goal.scoring_team == owner_team \
				or (goal.scoring_team == Goal3D.LAST_TOUCH and goal.owner_team != owner_team):
			return goal
	return null


## The middle of the orb.
func _muzzle() -> Vector3:
	return _orb.global_transform * _orb.get_aabb().get_center() if _orb else global_position + Vector3.UP * _top


# ===== ALTARS =====

## Every machine: each team's altar sells repairs while the team has a
## tower up (see Altar3D.set_repair_offer).
func _update_repair_offers() -> void:
	var game: Game3D_Class = Global.Game3D
	if not game:
		return
	for team: int in game.kills:
		var altar: Altar3D = game.altar_of_team(team)
		if altar:
			altar.set_repair_offer(not owned_by(get_tree(), team).is_empty())


## `team`'s towers that are up (or coming up).
static func owned_by(tree: SceneTree, team: int) -> Array[Tower3D]:
	var found: Array[Tower3D] = []
	for node: Node in tree.get_nodes_in_group("Tower"):
		if node is Tower3D and node.is_owned_by(team):
			found.append(node)
	return found


## Every tower still standing (or waiting to be claimed).
static func standing(tree: SceneTree) -> Array[Tower3D]:
	var found: Array[Tower3D] = []
	for node: Node in tree.get_nodes_in_group("Tower"):
		if node is Tower3D and node.state != State.FALLING:
			found.append(node)
	return found


## `team`'s most hurt tower, if it has one that's hurt at all.
static func most_damaged_of(tree: SceneTree, team: int) -> Tower3D:
	var best: Tower3D = null
	for tower: Tower3D in owned_by(tree, team):
		if tower.hp < tower.max_hp and (not best or tower.damage_share() > best.damage_share()):
			best = tower
	return best


# ===== LOOKS =====

func _team_color() -> Color:
	var team: int = owner_team if owner_team >= 0 else capture_team
	return Players.TEAM_COLORS[team % Players.TEAM_COLORS.size()] if team >= 0 else NEUTRAL_COLOR


## The orb filled from the bottom as far as the capture has got (all of
## it once it's claimed); once claimed, its column in its team's color up
## to its health, darker above; all of it flashing when hit.
func _update_look(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	var flash: float = FLASH_STRENGTH * _flash / FLASH_TIME
	_update_body(flash)
	if not _orb:
		return
	var box: AABB = _orb.global_transform * _orb.get_aabb()
	var height: float = -1000.0
	if owner_team >= 0:
		height = box.end.y + 1.0
	elif capture > 0.0:
		height = lerpf(box.position.y, box.end.y, capture)
	_material.set_shader_parameter(&"fill_color", _team_color())
	_material.set_shader_parameter(&"fill_height", height)
	_material.set_shader_parameter(&"flash", flash)


func _update_body(flash: float) -> void:
	_body_material.set_shader_parameter(&"flash", flash)
	if owner_team < 0 or _body.is_empty():
		_body_material.set_shader_parameter(&"fill_height", -1000.0)
		return
	var box: AABB = _body[0].global_transform * _body[0].get_aabb()
	for mesh: MeshInstance3D in _body:
		box = box.merge(mesh.global_transform * mesh.get_aabb())
	var color: Color = _team_color()
	_body_material.set_shader_parameter(&"fill_color", color)
	_body_material.set_shader_parameter(&"base_color", color.darkened(LOST_HP_DARKEN))
	_body_material.set_shader_parameter(&"fill_height", lerpf(box.position.y, box.end.y, hp / max_hp))


## The name over its top: the capture so far, then its health.
func _place_tag() -> void:
	if not _tag:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var head: Vector3 = global_position + Vector3.UP * (_top + TAG_GAP)
	_tag.visible = camera != null and state != State.FALLING and not camera.is_position_behind(head)
	if not _tag.visible:
		return
	_tag.color = _team_color()
	_tag.fraction = hp / max_hp if owner_team >= 0 else capture
	var at: Vector2 = camera.unproject_position(head)
	_tag.position = (at - Vector2(_tag.size.x * 0.5, _tag.size.y)).round()


## The orb that shows the capture: its sphere (or else its highest mesh).
func _find_orb() -> MeshInstance3D:
	var best: MeshInstance3D = null
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh is SphereMesh:
			return mesh
		if not best or (mesh.transform * mesh.get_aabb()).end.y > (best.transform * best.get_aabb()).end.y:
			best = mesh
	return best


## The highest point of its meshes, over its origin.
func _measure_top() -> float:
	var top: float = 0.0
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.transform * mesh.get_aabb()
		top = maxf(top, box.end.y)
	return top


## The lowest point of its meshes, over its origin.
func _measure_bottom() -> float:
	var bottom: float = INF
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.transform * mesh.get_aabb()
		bottom = minf(bottom, box.position.y)
	return bottom if bottom < INF else 0.0


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
