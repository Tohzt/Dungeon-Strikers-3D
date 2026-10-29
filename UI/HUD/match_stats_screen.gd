class_name MatchStatsScreen extends CanvasLayer
## The end of a match: who won, and a card for every player, the winners first. Each card shows the character they finished
## the match as in 3D (cheering if they won, slumped on the floor if not),
## their kills, deaths, goals and damage, and any awards they took (most
## kills, top scorer...). Made by Game3D from the rows MatchStats sends.
##
## Offline it has Play Again and Main Menu; online the server sends
## everyone back to the lobby on its own, so it just counts down to that.

## Award title for whoever has the most of each MatchStats field (ties
## share it), in the order they're listed on a card.
const AWARDS: Array[Array] = [
	["goals", "Top Scorer"],
	["kills", "Most Kills"],
	["damage", "Heavy Hitter"],
	["boss_kills", "Boss Slayer"],
	["boss_damage", "Boss Bully"],
	["deaths", "Floor Inspector"],
]
const MVP := "MVP"
const MVP_COLOR := Color(1.0, 0.8, 0.25)
const AWARD_COLOR := Color(0.95, 0.85, 0.6)
## What each stat is worth towards MVP.
const MVP_WEIGHTS: Dictionary[String, float] = {
	"goals": 3.0, "kills": 2.0, "boss_kills": 2.0, "damage": 0.01, "boss_damage": 0.005,
}
## Shown on each card, as [field, caption].
const LINES: Array[Array] = [
	["kills", "Kills"], ["deaths", "Deaths"], ["goals", "Goals"],
	["damage", "Damage"], ["boss_damage", "Boss dmg"],
]

const BACKGROUND := preload("res://Assets/UI/menu_background.png")
## Each card is the player's name, character and figure standing on top of
## the theme's stone panel holding their stats; the players on this machine
## get their panel tinted gold.
const LOCAL_CARD_TINT := Color(1.35, 1.15, 0.65)
## Room above and below the stats inside the stone frame.
const CARD_PADDING := 24.0
## Extra room at the panel's sides so the stats clear the stone frame.
const CARD_SIDE_PADDING := 22.0
## Whole row of cards stays within this width; each card is between these.
const ROW_WIDTH := 1060.0
const CARD_WIDTH := Vector2(120.0, 210.0)
const CARD_GAP := 10.0
## Extra gap between one team's cards and the next.
const TEAM_GAP := 24.0
const FADE_TIME := 0.4

## The figures' poses.
const WIN_CLIPS: Array[StringName] = [&"Simulation/Cheering", &"Special/Skeletons_Taunt"]
const LOSE_CLIPS: Array[StringName] = [&"Simulation/Sit_Floor_Idle", &"Simulation/Sit_Floor_Idle"]

## Online: seconds until the server sends everyone back to the lobby.
var _lobby_in: float = -1.0
var _countdown: Label


## `rows` from MatchStats.rows, `winner` the winning team. `local_names` are
## the players on this machine, whose cards stand out.
func setup(rows: Array, winner: int, local_names: Array[String]) -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var background := TextureRect.new()
	background.texture = BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_label("%s win!" % Players.team_name(winner), Players.team_color(winner), 44))

	var awards: Dictionary = _awards(rows)
	var ordered: Array = rows.duplicate()
	# Winners first, then each team in turn, seats in order within a team
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key: int = -1 if a.team == winner else a.team
		var b_key: int = -1 if b.team == winner else b.team
		return a_key < b_key)
	var teams: int = 0
	for i in ordered.size():
		if i == 0 or ordered[i].team != ordered[i - 1].team:
			teams += 1
	var card_width: float = clampf((ROW_WIDTH - TEAM_GAP * (teams - 1)) / maxf(ordered.size(), 1) - CARD_GAP, CARD_WIDTH.x, CARD_WIDTH.y)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", int(CARD_GAP))
	column.add_child(cards)
	for i in ordered.size():
		var row: Dictionary = ordered[i]
		if i > 0 and row.team != ordered[i - 1].team:
			var gap := Control.new()
			gap.custom_minimum_size.x = TEAM_GAP - CARD_GAP
			cards.add_child(gap)
		cards.add_child(_card(row, row.team == winner, card_width, awards.get(row.name, []), local_names.has(row.name)))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	if Net.in_session():
		_lobby_in = Net.LOBBY_RETURN_DELAY - Game3D_Class.STATS_DELAY
		_countdown = _label("", Color(1, 1, 1, 0.75), 18)
		buttons.add_child(_countdown)
	else:
		var again := _button("Play Again", func() -> void:
			get_tree().paused = false
			get_tree().reload_current_scene())
		buttons.add_child(again)
		buttons.add_child(_button("Main Menu", func() -> void:
			get_tree().paused = false
			get_tree().change_scene_to_file(Net.MAIN_MENU)))
		again.grab_focus.call_deferred()

	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, FADE_TIME)


func _process(delta: float) -> void:
	if _lobby_in < 0.0:
		return
	_lobby_in = maxf(_lobby_in - delta, 0.0)
	_countdown.text = "Back to the lobby in %d..." % ceili(_lobby_in)


## Player node name -> the award titles they won, MVP first.
func _awards(rows: Array) -> Dictionary:
	var won: Dictionary = {}
	var best_mvp: float = 0.0
	for row: Dictionary in rows:
		best_mvp = maxf(best_mvp, _mvp_score(row))
	for row: Dictionary in rows:
		if best_mvp > 0.0 and _mvp_score(row) == best_mvp:
			won.get_or_add(row.name, []).append(MVP)
	for award: Array in AWARDS:
		var field: String = award[0]
		var best: int = 0
		for row: Dictionary in rows:
			best = maxi(best, row.get(field, 0))
		if best <= 0:
			continue
		for row: Dictionary in rows:
			if row.get(field, 0) == best:
				won.get_or_add(row.name, []).append(award[1])
	return won


func _mvp_score(row: Dictionary) -> float:
	var score: float = 0.0
	for field: String in MVP_WEIGHTS:
		score += row.get(field, 0) * MVP_WEIGHTS[field]
	return score


func _card(row: Dictionary, won: bool, width: float, awards: Array, is_local: bool) -> Control:
	var color: Color = Players.team_color(row.team)
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = width
	card.add_theme_constant_override("separation", 2)

	var name_label := _label(row.label, color, 20 if width > 150.0 else 16)
	name_label.add_theme_font_override("font", NameTag.font())
	card.add_child(_trimmed(name_label))
	card.add_child(_trimmed(_label(Roster.name_of(row.character), Color(1, 1, 1, 0.6), 13)))
	# Blank for people, so every card's figure and panel line up
	card.add_child(_label("Bot" if row.bot else "", Color(1, 1, 1, 0.4), 12))
	card.add_child(_figure(row.character, won, Vector2(width, minf(width * 1.15, 210.0))))

	var style: StyleBox = _theme_panel().duplicate()
	style.set_content_margin_all(CARD_PADDING)
	style.content_margin_left = CARD_SIDE_PADDING
	style.content_margin_right = CARD_SIDE_PADDING
	if is_local and style is StyleBoxTexture:
		(style as StyleBoxTexture).modulate_color = LOCAL_CARD_TINT
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", style)
	card.add_child(frame)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	frame.add_child(stats)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(grid)
	for line: Array in LINES:
		var caption := _label(line[1], Color(1, 1, 1, 0.7), 14)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(caption)
		var value := _label(str(row.get(line[0], 0)), Color.WHITE, 14)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)

	for title: String in awards:
		stats.add_child(_label(("★ " if title == MVP else "") + title, MVP_COLOR if title == MVP else AWARD_COLOR, 15 if title == MVP else 13))
	return card


## The project theme's panel (the stone frame).
func _theme_panel() -> StyleBox:
	var theme: Theme = ThemeDB.get_project_theme()
	return theme.get_stylebox(&"panel", &"PanelContainer") if theme else StyleBoxEmpty.new()


## `character` in its own little world, cheering if `won`, else slumped.
func _figure(character: int, won: bool, size: Vector2) -> Control:
	var box := ScreenResViewport.new()
	box.custom_minimum_size = size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport: SubViewport = box.viewport
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.45, 0.4)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	viewport.add_child(sun)

	var body: Node3D = CharacterStage3D.make_body(character)
	body.rotation.y = deg_to_rad(-12)
	viewport.add_child(body)
	var anim: AnimationPlayer = CharacterStage3D.animator_of(body)
	var side: int = Roster.side_of(character)
	var clip: StringName = (WIN_CLIPS if won else LOSE_CLIPS)[mini(side, 1)]
	if not anim.has_animation(clip):
		clip = CharacterStage3D.SKELETON_IDLE if side == Roster.SKELETONS else CharacterStage3D.HUMAN_IDLE
	if anim.has_animation(clip):
		_start_clip.call_deferred(anim, clip)  # Once it's in the tree

	var camera := Camera3D.new()
	camera.fov = 36.0
	camera.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 3.6)).looking_at(Vector3(0, 0.7, 0))
	viewport.add_child(camera)
	return box


## Each figure starts somewhere different in its clip, so they're out of step.
func _start_clip(anim: AnimationPlayer, clip: StringName) -> void:
	anim.play(clip)
	anim.seek(randf() * anim.current_animation_length, true)


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 40)
	button.pressed.connect(on_pressed)
	return button


## Cut short with "..." rather than widening its card.
func _trimmed(label: Label) -> Label:
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	return label


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(roundi(size / 5.0), 3))
	return label
