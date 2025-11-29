##TODO: Remove the "weapon_" prefix
class_name WeaponResource extends Resource

enum Handedness { LEFT, RIGHT, BOTH, EITHER, NONE }
enum ThrowStyle { SPIN, STRAIGHT, TUMBLE }
enum InputMode { CLICK_ONLY, HOLD_ACTION, BOTH }
enum Types { SWORD, SHIELD, STAFF, BOW, ARROW, INSTANCE}

# Basic Weapon Information
@export_group("Basic Info")
@export var weapon_name: String = ""
@export var weapon_type: Types
@export var weapon_synergies: Array[Types]
@export var weapon_hand: Handedness
@export var weapon_throw_style: ThrowStyle

# Visual and Sprite Properties
@export_group("Visual")
@export var weapon_sprite: Array[CompressedTexture2D]
@export var weapon_sprite_offset: Vector2
@export_range(0.0, 360.0) var weapon_angle: float

# Collision Properties
@export_group("Collision")
@export var weapon_col_radius: float
@export var weapon_col_height: float
@export var weapon_col_rotation: float
@export var weapon_col_offset: Vector2

# Combat Properties
@export_group("Combat")
@export var weapon_damage: float = 0.0
@export var weapon_mod_damage: float = 0.0
@export var weapon_cooldown: float = 0.0
@export var weapon_duration: float = 1.0
@export var weapon_stamina_cost: float = 0.0
@export var weapon_mana_cost: float = 0.0
@export var weapon_cast_duration: float = 0.0

# Equipment Properties
@export_group("Equipment")
@export var weapon_arm_length: float
@export var weapon_controller: Resource
@export var weapon_effect: PackedScene
