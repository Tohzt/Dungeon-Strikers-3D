class_name WeaponClass3D extends Weapon3D
## A melee weapon held in the hand and swung by the arm's attack clip. A
## fast swing leaves a trail behind the blade (see WeaponTrail3D).

var trail: WeaponTrail3D = null


func _ready() -> void:
	super()
	if plays_swipe_animation and not self is ShieldClass3D:
		trail = WeaponTrail3D.new()
		trail.name = "Trail"
		add_child(trail)
		trail.setup(self, _trail_color())


## White, or tinted with its rarity's color.
func _trail_color() -> Color:
	if rarity == WeaponRarity.Tier.COMMON:
		return Color.WHITE
	return Color(WeaponRarity.COLORS[rarity], 1.0).lightened(0.3)


func set_rarity(tier: int) -> void:
	super(tier)
	if trail:
		(trail.material_override as StandardMaterial3D).albedo_color = _trail_color()


func on_hand_posed() -> void:
	super()
	if trail:
		trail.sample()
