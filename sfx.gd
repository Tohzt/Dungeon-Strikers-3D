extends Node
## Sound effects. Each sound is a named set of takes (see SOUNDS); every
## play picks one at random, never the same twice running, at a slightly
## different pitch and volume, so repeated swings and hits don't drone.
##
## play() is just this machine. Most sounds come from something every
## machine already does (a swing's animation, a throw, a weapon breaking);
## play_everywhere() is for the ones only one machine sees happen (a block,
## a hit on the boss), and sends them on to the rest.

const DIR := "res://Assets/Audio/SFX/"

## id: [file prefix under DIR, takes (_01, _02...), volume dB, pitch].
const SOUNDS: Dictionary[StringName, Array] = {
	# Swings, one per kind of weapon (see Weapon3D.swing_sound)
	&"swing_sword": ["Sword/Sword_Swing_Short_", 5, -4.0, 1.0],
	&"swing_greatsword": ["Sword/Sword_Swing_Long_", 5, -4.0, 1.0],
	&"swing_axe": ["Axe/Axe_Swing_", 5, -4.0, 1.0],
	&"swing_club": ["Club/Club_Swing_", 5, -4.0, 1.0],
	&"swing_dagger": ["Dagger/Dagger_Swing_", 5, -4.0, 1.0],
	&"swing_spear": ["Spear/Spear_Swing_", 5, -4.0, 1.0],
	&"swing_halberd": ["Lance/Lance_Swing_", 5, -4.0, 1.0],
	&"swing_torch": ["Torch/Torch_Swing_", 5, -4.0, 1.0],
	&"swing_fist": ["Fist/Fist_Swing_", 5, -6.0, 1.0],
	# Shots (see CrossbowClass3D.fire_sound)
	&"bow_release": ["Bow/Bow_Release_", 10, -2.0, 1.0],
	&"fireball": ["Spells/Fireball_", 3, -4.0, 1.0],
	&"ice_bolt": ["Spells/Ice_Throw_", 2, -4.0, 1.0],
	&"spell_impact": ["Spells/Spell_Impact_", 3, -2.0, 1.0],
	&"throw": ["Throw/Thrown_Knife_", 5, -2.0, 1.0],
	# Picking up a weapon, by its size
	&"equip_small": ["Unsheathe/Unsheathe_Small_", 5, -6.0, 1.0],
	&"equip_medium": ["Unsheathe/Unsheathe_Medium_", 5, -6.0, 1.0],
	&"equip_long": ["Unsheathe/Unsheathe_Long_", 5, -6.0, 1.0],
	# Impacts
	&"hit_player": ["Impacts/Body/Impact_Body_", 10, 0.0, 1.0],
	&"hit_slime": ["Impacts/Juicy/Impact_Juicy_", 10, 0.0, 1.0],
	&"hit_ball": ["Impacts/Dull/Impact_Dull_", 10, -2.0, 1.0],
	&"hit_wall": ["Impacts/Metal/Impact_Clash_Light_", 10, -4.0, 1.0],
	&"block": ["Impacts/Metal/Impact_Clash_Strong_", 10, 0.0, 1.0],
	&"arrow_wall": ["Impacts/Wood/Arrow_Impact_Wood_", 10, -4.0, 1.0],
	&"weapon_break": ["Impacts/Powerful/Impact_Powerful_", 10, 2.0, 1.0],
	# Fire: the ball catching light, and the crackle of anything burning
	&"ignite": ["Fire/Ignite_", 2, -2.0, 1.0],
	&"fire_loop": ["Fire/Fire_Loop_", 1, -8.0, 1.0],
	# Moving about (see PlayerVisual3D._update_footsteps)
	&"footstep": ["Footsteps/Stone_Run_", 5, -22.0, 1.0],
	&"footstep_armored": ["Footsteps/Stone_Chain_Run_", 5, -22.0, 1.0],
	&"roll": ["Footsteps/Stone_Roll_", 1, -6.0, 1.0],
	&"land": ["Footsteps/Stone_Land_", 1, -6.0, 1.0],
	# The boss
	&"boss_stomp": ["Boss/Stomp_", 2, 2.0, 1.0],
	&"boss_spit": ["Boss/Spit_", 2, -2.0, 1.0],
	&"chest_open": ["Chest/Chest_Open_", 2, -2.0, 1.0],
	# The altar
	&"altar_tier": ["Anvil/Anvil_Strike_Light_", 5, -4.0, 1.0],
	&"altar_reward": ["Anvil/Anvil_Strike_Heavy_", 5, -2.0, 1.0],
}

## Background loops, one per level (see Game3D_Class.ambience), not placed
## anywhere: [file under AMBIENCE_DIR, volume dB].
const AMBIENCE_DIR := "res://Assets/Audio/Ambience/"
const AMBIENCES: Dictionary[StringName, Array] = {
	&"cave": ["Cave_01.ogg", -14.0],
}

## Music tracks: [intro file, loop file (under MUSIC_DIR), volume dB]. The
## intro plays once from a clean start, then the loop takes over seamlessly
## and repeats until the next track.
const MUSIC_DIR := "res://Assets/Audio/BGM/"
const MUSIC: Dictionary[StringName, Array] = {
	&"lava_dungeon": ["11 Lava Dungeon (clean intro).wav", "11 Lava Dungeon LOOP.wav", -10.0],
	&"boss": ["12 Boss Theme (clean intro).wav", "12 Boss Theme LOOP.wav", -8.0],
}
## How long one track takes to fade into the next.
const MUSIC_FADE := 1.5
## Volume a track fades in from / out to.
const MUSIC_SILENT_DB := -40.0

## Pitch varies up to this factor either way, volume up to this many dB down.
const PITCH_VARIATION := 1.08
const VOLUME_VARIATION_DB := 2.0
## Loudness falloff with distance from the camera.
const UNIT_SIZE := 12.0
const MAX_DISTANCE := 80.0

var _streams: Dictionary[StringName, AudioStreamRandomizer] = {}
var _ambience: AudioStreamPlayer = null
var _music: AudioStreamPlayer = null
var _music_id: StringName = &""
## A dedicated server has nobody to play to.
var _silent: bool = DisplayServer.get_name() == "headless"


## Play `id` at `at` on this machine only.
func play(id: StringName, at: Vector3) -> void:
	if _silent:
		return
	var stream: AudioStreamRandomizer = _stream(id)
	if not stream:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = SOUNDS[id][2]
	player.pitch_scale = SOUNDS[id][3]
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.finished.connect(player.queue_free)
	add_child(player)
	player.global_position = at
	player.play()


## Keep `id`'s first take looping on `parent`, following it around, until
## the returned player is freed (or `parent` is). Null if there's no sound.
func play_loop(id: StringName, parent: Node3D) -> AudioStreamPlayer3D:
	if _silent:
		return null
	var stream: AudioStreamRandomizer = _stream(id)
	if not stream or stream.streams_count == 0:
		return null
	var take: AudioStream = stream.get_stream(0)
	if take is AudioStreamOggVorbis:
		(take as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer3D.new()
	player.stream = take
	player.volume_db = SOUNDS[id][2]
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.autoplay = true
	parent.add_child(player)
	return player


## Loop the level's background `id` (an AMBIENCES id; empty = silence),
## until the next call.
func play_ambience(id: StringName) -> void:
	if _ambience:
		_ambience.queue_free()
		_ambience = null
	if _silent or id == &"" or not AMBIENCES.has(id):
		return
	var stream: AudioStreamOggVorbis = load(AMBIENCE_DIR + AMBIENCES[id][0]) as AudioStreamOggVorbis
	if not stream:
		return
	stream.loop = true
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = stream
	_ambience.volume_db = AMBIENCES[id][1]
	add_child(_ambience)
	_ambience.play()


## Crossfade to music track `id` (a MUSIC id; empty = fade to silence),
## starting from its intro. Already playing it: carries on.
func play_music(id: StringName) -> void:
	if id == _music_id:
		return
	_music_id = id
	if _music:
		var old: AudioStreamPlayer = _music
		_music = null
		var fade_out: Tween = old.create_tween()
		fade_out.tween_property(old, "volume_db", MUSIC_SILENT_DB, MUSIC_FADE)
		fade_out.tween_callback(old.queue_free)
	if _silent or id == &"" or not MUSIC.has(id):
		return
	var track: Array = MUSIC[id]
	var stream := AudioStreamInteractive.new()
	stream.clip_count = 2
	stream.set_clip_name(0, &"intro")
	stream.set_clip_stream(0, load(MUSIC_DIR + track[0]))
	stream.set_clip_auto_advance(0, AudioStreamInteractive.AUTO_ADVANCE_ENABLED)
	stream.set_clip_auto_advance_next_clip(0, 1)
	stream.set_clip_name(1, &"loop")
	stream.set_clip_stream(1, load(MUSIC_DIR + track[1]))  # Imported to loop forever
	stream.initial_clip = 0
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	_music.volume_db = MUSIC_SILENT_DB
	_music.process_mode = Node.PROCESS_MODE_ALWAYS  # Keeps playing on the pause menu
	add_child(_music)
	_music.play()
	_music.create_tween().tween_property(_music, "volume_db", track[2], MUSIC_FADE)


## Play `id` at `at` here and, online, on every other machine too.
func play_everywhere(id: StringName, at: Vector3) -> void:
	play(id, at)
	if Net.match_synced:
		_net_play.rpc(id, at)


@rpc("any_peer", "unreliable")
func _net_play(id: StringName, at: Vector3) -> void:
	play(id, at)


## Loaded the first time it's played.
func _stream(id: StringName) -> AudioStreamRandomizer:
	if _streams.has(id):
		return _streams[id]
	if not SOUNDS.has(id):
		push_error("Unknown sound: %s" % id)
		_streams[id] = null
		return null
	var stream := AudioStreamRandomizer.new()
	stream.random_pitch = PITCH_VARIATION
	stream.random_volume_offset_db = VOLUME_VARIATION_DB
	var prefix: String = SOUNDS[id][0]
	for take: int in SOUNDS[id][1]:
		var path: String = DIR + prefix + "%02d.ogg" % (take + 1)
		var take_stream: AudioStream = load(path) as AudioStream
		if take_stream:
			stream.add_stream(-1, take_stream)
	_streams[id] = stream
	return stream
