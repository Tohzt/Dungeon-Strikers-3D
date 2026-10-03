class_name WeaponRarity
## How rare a weapon is. Rarer weapons last longer before breaking, so the
## commons that altars hand out early on break often, and a rare find is
## worth fighting over. Rarity shows as a colored glow on the weapon.

enum Tier { COMMON, UNCOMMON, RARE, LEGENDARY }

const NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Legendary"]
## Uses before breaking (hits landed, blocks, shots), before the weapon's
## own WeaponProperties3D.durability_scale.
const DURABILITY: Array[int] = [5, 9, 14, 24]
const COLORS: Array[Color] = [
	Color(1, 1, 1, 0),  # No glow
	Color(0.2, 0.9, 0.3, 0.3),
	Color(0.25, 0.5, 1.0, 0.35),
	Color(1.0, 0.65, 0.1, 0.4),
]


## A tier picked at random, weighted by `weights` (one per tier; missing
## ones count as 0). Common if they're all 0.
static func roll(weights: Array[float]) -> int:
	var total: float = 0.0
	for w: float in weights:
		total += max(w, 0.0)
	if total <= 0.0:
		return Tier.COMMON
	var pick: float = randf() * total
	for i in mini(weights.size(), Tier.size()):
		pick -= max(weights[i], 0.0)
		if pick < 0.0:
			return i
	return Tier.COMMON


## Glow every mesh under `root` in `tier`'s color (commons get none). The
## overlay material is returned so it can be pulsed (e.g. when nearly broken).
static func apply_glow(root: Node, tier: int) -> StandardMaterial3D:
	var color: Color = COLORS[clampi(tier, 0, COLORS.size() - 1)]
	var material: StandardMaterial3D = null
	if color.a > 0.0:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.albedo_color = color
	for mesh: Node in root.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = material
	return material
