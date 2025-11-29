class_name AttackResource extends Resource

enum AttackType { MELEE, PROJECTILE, MAGIC, AOE, HEAL, BUFF, TELEPORT }

@export var attack_name: String = ""
@export var attack_damage: float = 0.0
@export var attack_distance: float = 0.0
@export var attack_mana_cost: float = 0.0
@export var attack_cast_time: float = 0.0
@export var attack_cooldown: float = 0.0
@export var attack_duration: float = 1.0
@export var attack_aoe_radius: float = 0.0
@export var attack_telegraph_scene: PackedScene
@export var attack_type: AttackType = AttackType.MELEE
