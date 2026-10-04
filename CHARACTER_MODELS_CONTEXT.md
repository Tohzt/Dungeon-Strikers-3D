# Character Models & Animations — Handoff Context (TEMPORARY)

> Temporary briefing for the agent implementing character models. Delete this
> file once the work has landed. Written 2026-10-03.

## What's here

Two free KayKit packs (Kay Lousberg, CC0) were added, reduced to `.glb` only
(textures are embedded), and reorganized:

```
Assets/Characters/
├── Adventurers/          6 skinned characters, Rig_Medium
│   Barbarian, Knight, Mage, Ranger, Rogue, Rogue_Hooded
├── Mannequins/           plain grey test bodies
│   Mannequin_Medium (Rig_Medium), Mannequin_Large (Rig_Large)
├── Animations/
│   ├── Rig_Medium/       8 files, ~150 clips — fits the Adventurers
│   └── Rig_Large/        6 files, ~32 clips — fits Mannequin_Large only
└── Props/                static meshes, no skin
    ├── Weapons/          axe_1handed, axe_2handed, bow, bow_withString,
    │                     crossbow_1handed, crossbow_2handed, dagger, staff,
    │                     sword_1handed, sword_2handed, sword_2handed_color, wand
    ├── Shields/          shield_{badge,round,spikes,square}[_color], shield_round_barbarian
    ├── Ammo/             arrow_bow[_bundle], arrow_crossbow[_bundle], quiver
    └── Items/            mug_empty, mug_full, smokebomb, spellbook_closed, spellbook_open
```

Nothing in the project references these files yet. There are no `.import` files
because Godot creates them on the next editor launch. On import, Godot also
pulls each character's embedded texture out into a PNG next to the `.glb`
(e.g. `Knight_knight_texture.png`). That's expected.

## Characters

Each character is built from separate meshes that share one skin. Any of them
can be hidden on its own, so accessories can be toggled:

| Model        | Meshes (all prefixed with the model name) |
|--------------|-------------------------------------------|
| Barbarian    | ArmLeft, ArmRight, Body, Head, LegLeft, LegRight, **BearHat** |
| Knight       | Arm×2, Body, Head, Leg×2, **Cape, Helmet, HelmetVisor** |
| Mage         | Arm×2, Body, Head, Leg×2, **Cape, Hat** |
| Ranger       | Arm×2, Body, Head, Leg×2, **Cape, Quiver** |
| Rogue        | Arm×2, Body, Head, Leg×2, **Cape** |
| Rogue_Hooded | Arm×2, Body, Head, Leg×2, **Cape, Mask** (prefix `RogueHooded_`) |

The style is chibi: a big head on a short body. In bind pose (glTF units, feet
at y=0) Medium bodies are about 2.2 tall (Knight with helmet is about 2.5).
Mannequin_Large is about 4.0. **Check the scale in the editor.** The current
player body is a default `CapsuleShape3D` (height 2, radius 0.5) centered on
the player origin, so the feet are at y = −1.

**Facing:** glTF forward is +Z. The player code also treats +Z as forward
(`rotation.y = atan2(dir.x, dir.z)`, `character_body_3d.gd:1351`), so the
models probably need no 180° turn. Confirm this in the editor.

## Rigs

**Rig_Medium** (23 joints). All Adventurers and every `Animations/Rig_Medium/*`
file share the exact same bone names and rest pose, so the clips play on any
Adventurer with no retargeting.

```
root
└── hips
    ├── spine → chest
    │   ├── head
    │   ├── upperarm.l → lowerarm.l → wrist.l → hand.l → handslot.l
    │   └── upperarm.r → lowerarm.r → wrist.r → hand.r → handslot.r
    ├── upperleg.l → lowerleg.l → foot.l → toes.l
    └── upperleg.r → lowerleg.r → foot.r → toes.r
```

- `handslot.l/.r` are the intended weapon attach points (use a
  `BoneAttachment3D`).
- ⚠️ `Mannequins/Mannequin_Medium.glb` has only 21 joints because it is
  **missing both handslots**. It's fine for previewing animations but not for
  attaching weapons.

**Rig_Large** (23 joints, same bone names, much bulkier proportions: wider
shoulders, longer limbs). Only Mannequin_Large uses it. It's a good fit for a
big enemy or boss body. Don't mix Large clips with Medium bodies.

## Animation clips

Every animation file also contains a mannequin mesh and a `T-Pose` clip.
Import them as animation libraries only (see "Importing" below).

### Rig_Medium
- **General**: Death_A, Death_A_Pose, Death_B, Death_B_Pose, Hit_A, Hit_B, Idle_A, Idle_B, Interact, PickUp, Spawn_Air, Spawn_Ground, Throw, Use_Item
- **MovementBasic**: Jump_Full_Long, Jump_Full_Short, Jump_Idle, Jump_Land, Jump_Start, Running_A, Running_B, Walking_A, Walking_B, Walking_C
- **MovementAdvanced**: Crawling, Crouching, Dodge_Backward, Dodge_Forward, Dodge_Left, Dodge_Right, Running_HoldingBow, Running_HoldingRifle, Running_Strafe_Left, Running_Strafe_Right, Sneaking, Walking_Backwards
- **CombatMelee**: Melee_1H_Attack_{Chop, Jump_Chop, Slice_Diagonal, Slice_Horizontal, Stab}, Melee_2H_Attack_{Chop, Slice, Spin, Spinning, Stab}, Melee_2H_Idle, Melee_Block, Melee_Block_Attack, Melee_Block_Hit, Melee_Blocking, Melee_Dualwield_Attack_{Chop, Slice, Stab}, Melee_Unarmed_Attack_Kick, Melee_Unarmed_Attack_Punch_A, Melee_Unarmed_Idle
- **CombatRanged**: Ranged_1H_{Aiming, Reload, Shoot, Shooting}, Ranged_2H_{Aiming, Reload, Shoot, Shooting}, Ranged_Bow_{Aiming_Idle, Draw, Draw_Up, Idle, Release, Release_Up}, Ranged_Magic_{Raise, Shoot, Spellcasting, Spellcasting_Long, Summon}
- **Simulation**: Cheering, Waving, Lie_Down/Idle/StandUp, Sit_Chair_Down/Idle/StandUp, Sit_Floor_Down/Idle/StandUp, Push_Ups, Sit_Ups
- **Special**: Skeletons_{Awaken_Floor, Awaken_Floor_Long, Awaken_Standing, Death, Death_Pose, Death_Resurrect, Idle, Inactive_Floor_Pose, Inactive_Standing_Pose, Spawn_Ground, Taunt, Taunt_Longer, Walking}, EXPERIMENTAL_Medium_Transform
- **Tools**: Chop(ping), Dig(ging), Fishing_{Bite, Cast, Catch, Idle, Reeling, Struggling, Tug}, Hammer(ing), Holding_A/B/C, Lockpick(ing), Pickaxe/Pickaxing, Saw(ing), Work_A/B/C, Working_A/B/C

### Rig_Large
- **General**: Death_A, Death_A_Pose, Hit_A, Idle_A, Idle_B
- **MovementBasic**: Running_A, Walking_A
- **MovementAdvanced**: Dodge_Backwards, Dodge_Forward, Dodge_Left, Dodge_Right
- **CombatMelee**: Melee_1H_Slash, Melee_1H_Stab, Melee_2H_Attack, Melee_2H_Idle, Melee_2H_Slam, Melee_Block, Melee_Block_Attack, Melee_Block_Hit, Melee_Blocking, Melee_Dualwield_Slash, Melee_Dualwield_SlashCombo, Melee_Unarmed_Idle, Melee_Unarmed_Kick, Melee_Unarmed_Punch, Melee_Unarmed_Smash
- **Simulation**: Flexing
- **Special**: EXPERIMENTAL_Large_Transform

## Importing (Godot 4.7)

1. **Animation files:** in the Import dock set *Import As → Animation
   Library*, then add the resulting libraries to the character's
   `AnimationPlayer`. Track paths will look like
   `Rig_Medium/Skeleton3D:<bone>`. Check that the character scene's skeleton
   sits at the same relative path, or the tracks won't bind.
2. **Looping:** glTF doesn't store loop flags. Turn on looping in the Advanced
   Import settings for the clips that should repeat: Idle_*, Walking_*,
   Running_*, Melee_Blocking, Melee_*_Idle, Jump_Idle, and so on.
3. **Character files:** import as a normal scene. Either make an inherited
   scene or instance it under a visual root node.

## How the player works today (read before integrating)

The player scene is `3D/player_3d/player_3d.tscn`, with the script at
`3D/player_3d/character_body_3d.gd`. It is used by `Game3D.tscn`,
`DungeonArena.tscn` and `Game/Dungeon/build_dungeon_arena.gd`.

**Design direction (changed 2026-10-03; this replaces the earlier plan):**
- **No more floating hands.** Players become fully skinned KayKit characters
  with real arms.
- **Attacks are animation-driven:** KayKit melee, ranged and throw clips,
  with weapons attached to the `handslot.l/.r` bones.
- The old plan (procedural Rayman-style hands, with only the body animated) is
  **dropped**. See "Converting to animation-driven combat" below.
- **Gameplay feel stays:** knockback, hitstop, the soccer ball, throws,
  durability, roll, poise and stagger all remain. Only how swings are
  *produced* changes.
- Readability still matters: 4 local players share one top-down camera.

**Code that assumes the current capsule mesh** (it will break if the body mesh
is swapped naively):
- `character_body_3d.gd:3`: `mesh_instance_3d` is an array whose first entry
  is `$Body/MeshInstance3D`, followed by the two hand meshes.
- `entity_behavior_3d.gd`: `set_color()`, `start_iframes()` and
  `end_iframes()` loop over `mesh_instance_3d` and write a
  `StandardMaterial3D` **surface override on surface 0** (team color tint and
  the 50% alpha flash during iframes). Doing that on a textured KayKit mesh
  would wipe its texture and miss its other meshes. Team color needs a new
  approach, such as `material_overlay`, a tinted accessory, a ring under the
  player, or colored hands. The iframe fade also needs to cover every
  sub-mesh.
- Body tilt (`character_body_3d.gd`, around line 1455): `_update_body_tilt()`
  and `_apply_body_tilt()` pitch `mesh_instance_3d[0]` from `body_mesh_rest`.
  It does a full 360° tumble on a roll, a lean on a backstep or boost, and a
  rock-back while staggered. `body_tilt` is **synced online**. Either rotate a
  new visual root the same way, or replace the effect with
  Dodge_Forward/Backward and Hit clips while keeping the synced value working.

**Player state to drive animations from:**

| State | Where it lives |
|-------|----------------|
| move speed | `velocity` (synced online) |
| roll / backstep | `roll_time > 0`, `is_backstep`, `roll_dir` |
| stagger | `stagger_time > 0` (`_stagger()`) |
| sprint / boost | `boost_blend`, `BOOST_LEAN` |
| dead | `is_dead()` |
| airborne | `is_on_floor()` |

**Online play:** remote copies don't simulate the player. They replay
`net_pose`, `velocity` and `body_tilt`. Pick animations from data that is
already synced, so no new sync fields are needed. See `SYNCED_PROPERTIES` at
`character_body_3d.gd:21`.

## Converting to animation-driven combat

This is the bulk of the work. Today, combat is a **procedural two-arm rig**:
each arm is a `Shoulder_*` Node3D that the script rotates. On the end of each
arm sits a `Hand_*` Area3D, which serves as the fist hitbox and as the anchor
that weapons follow. All of it lives in `character_body_3d.gd` (about 1,770
lines). The sections below cover what each part does now and what it should
become.

### Node changes in `player_3d.tscn`
- **Remove** `Appendages/Shoulder_Left|Right`, `Hand_*`, their sphere meshes
  and `Body/MeshInstance3D` (the capsule mesh).
- **Keep** `Body` (the `CollisionShape3D` capsule; resize it to fit the model),
  `Hold` (the ball carry point), `Entity`, `Input` and `Camera3D`.
- **Add** a `Visual` Node3D holding the KayKit character instance, an
  `AnimationTree`, and a `BoneAttachment3D` on each of `handslot.r` and
  `handslot.l`. Each attachment gets a small Area3D or shape that serves as
  the fist hitbox.

### Procedural code that goes away (replaced by clips)

| Current code in `character_body_3d.gd` | Replace with |
|---|---|
| `_update_shoulder_swipe`, swipe timers and durations, `swipe_from_*`, `chop_from_*` | Attack clips through the AnimationTree |
| `SwingDraw`, `_update_swing_draws` (heavy-weapon draw-back) | The wind-up part of the clip (`Melee_2H_Attack_Chop`, etc.) |
| `_wrist_angle`, `_swing_wrist_angle`, `_chop_wrist_angle`, `WRIST_*` and `CHOP_*` constants, `weapon.wrist_pitch` | Pick the clip per weapon: chop vs slice vs stab |
| `_update_weapon_windups`, `_update_hand_windup` (lean-back while charging a throw) | `Throw` clip, held or paused on its wind-up pose while charging |
| `_update_arm_sway`, `SWAY_*` | Walking and running clips |
| `_update_body_tilt`, `_apply_body_tilt`, `body_tilt`, `body_mesh_rest` | `Dodge_*`, `Hit_*` and `Death_*` clips; stagger can use `Hit_B` or `Melee_Block_Hit` |
| `_update_hand_mesh_position`, `_sync_hand_mesh`, `hand_*_mesh_rest` | Not needed: the weapon rides the bone |

**Keep, but feed from animation:**
- **Commitment:** `_lunge`, `SWING_TURN_SPEED`, `SWING_MOVE_CONTROL`,
  `_is_committed()`. Currently "committed" means a strike timer is running.
  Make it mean the active window of the clip.
- **Hitstop and rebound:** `swing_contact()` → `_start_swing_contact`. Pause
  the AnimationTree for the hitstop. For a solid hit, either cut to
  `Melee_Block_Hit` or play the clip backwards briefly.
- **Cancels:** `_cancel_attacks()` and `weapon.cancel_swing()`, called on
  roll and stagger. These must stop the attack clip as well as the hit window.
- **Tuning values:** `WeaponProperties.swing_duration` and `swing_windup`
  hold the current balance numbers (see
  `design-roadmap-oct-2026` — "swing speed"). Convert each to a playback speed
  (clip active length ÷ desired duration) rather than discarding them.
- **Bots:** `bot_input_handler_3d.gd` calls `player.is_arm_swinging(left)`.
  Keep that API.

### Weapons (`3D/Items/Weapons/weapon_3d.gd` and `3D/Weapons/*`)
- **Holding:** held weapons are physics bodies chasing the hand on a spring
  (`sword_3d.gd`: `follow_strength`, `follow_damping`, velocity prediction,
  `held_lift`). Axe, greataxe, dagger, hammer and sword all use
  `sword_3d.gd`. Animation needs them **rigidly on the bone** while held:
  either reparent them to the hand's BoneAttachment3D with a frozen body, or
  copy the bone transform each frame. Keep full physics for thrown and
  dropped weapons.
  - `held_hand: Area3D` becomes the attachment node.
  - `equip()`, `snap_to_hand()` and `unequip()` change accordingly.
- **Hit detection already works with any motion.** `_update_hits()` sweeps
  the weapon's `Collision` shape for overlaps while `swing_time_left > 0`, and
  scales knockback and ball curve by the blade's tracked speed
  (`_track_blade`). So leave the sweep alone and drive the timing from the
  clip. Open the window with a method-call track or per-clip
  start/end times, via `weapon.start_swing(active_time)` /
  `cancel_swing()`. Keep the blade tracking; it gives real speeds once the
  weapon rides a bone.
- **Per-weapon clip:** add exported fields to `WeaponProperties3D`, for
  example `attack_anim`, `two_handed`, `hold_anim`. Suggested mapping:
  - sword / dagger → `Melee_1H_Attack_Slice_Horizontal` / `_Stab`
  - axe / hammer → `Melee_1H_Attack_Chop`
  - greataxe → `Melee_2H_Attack_Chop`
  - matching pair (`_holds_matching_pair`, `_queue_paired_follow`) →
    `Melee_Dualwield_Attack_*`
- **Ranged:** `crossbow_3d.gd` handles bow and staff with
  `plays_swipe_animation = false`, and fires from `attack()`. Use
  `Ranged_Bow_Draw/Release`, `Ranged_Magic_Shoot` or `Ranged_1H_Shoot`, and
  fire the projectile on a method-call key at the release frame.
- **Shield:** `shield_3d.gd` (`start_block`, `stop_block`, a networked
  blocking flag) → `Melee_Blocking`, `Melee_Block_Hit` (on a blocked hit,
  `_receive_blocked_hit`) and `Melee_Block_Attack`.
- **Throwing:** a held button charges a throw (`HOLD_THRESHOLD`,
  `THROW_CHARGE_*`) → `_throw_weapon`. Use the `Throw` clip and release on its
  key frame.
- **Swapping hands:** `swap_hands()` swaps which attachment each weapon is on.

### Fists, ball and other hand uses
- **Fists:** `_start_punch`, `_update_punches`, `_check_fist_hits` (uses the
  Hand Area3D + `FIST_REACH`). Move the hit shape onto the hand attachment and
  use `Melee_Unarmed_Attack_Punch_A`. `Melee_Unarmed_Attack_Kick` could suit
  the soccer side.
- **Ball:** `held_ball` is carried at the `Hold` node
  (`update_held_ball_position`), and `throw_ball` throws it. Use the
  `Holding_*` (Tools) or `Jump_Idle`-style carry pose for an upper-body layer,
  and `Throw` to release.
- **Altar and pickups:** `PickUp` and `Interact` clips are available for
  `_pickup_weapon` and `_take_from_nearest_stand`, but they're optional.

### ⚠️ Decisions for the user before building
1. **Independent hands vs full-body attacks.** Today the two arms swing
   **independently**: one button per hand, both can swing at once, and
   `is_arm_swinging(is_left)` is tracked per arm. KayKit clips are full-body.
   The options:
   - **(a)** AnimationTree with locomotion on the legs and per-arm upper-body
     layers. Use bone filters on `upperarm.l` → `handslot.l` and on the
     matching right-arm chain. This keeps independent hands, but mixed poses
     can look odd.
   - **(b)** One attack at a time on the upper body (`chest` and down), so
     the second press queues. This is simpler and reads better, but it
     changes the feel.
2. **Left-hand attacks.** The 1H clips swing with the **right** hand, and
   Godot 4.7 has no runtime animation mirroring. The options:
   - Mirror the clips offline (in Blender) to make `_L` variants.
   - Make the right hand the main hand and give the left hand off-hand
     actions only (shield, block, dual-wield follow-up).
   - Use the `Melee_Dualwield_*` clips whenever the left hand acts.
3. **Simple vs advanced controls.** `Input_Handler.uses_simple_controls()`
   (the default) means separate throw and attack buttons with an off-hand
   button. Advanced controls use tap-to-swing / hold-to-throw per hand. Both
   paths go through `_handle_hand_attack`, and both need mapping to the new
   clips.

### Online (`net_pose`, `SYNCED_PROPERTIES`)
- Today, `net_pose` is `[time, transform, left shoulder yaw, right shoulder
  yaw]` and `body_tilt` is synced. Held weapons also stream their own pose
  (`weapon_3d.gd` `_send_pose` / `follow_net_pose`).
- After the change:
  - Drop the shoulder yaws and `body_tilt`.
  - Sync **animation events** instead, e.g. an RPC or synced field with
    `(attack clip id, hand, start time)`, plus state that's already synced
    (`velocity`, roll and stagger, HP).
  - Remote copies play the same clips locally.
  - Held weapons follow the bone on every machine, so their per-frame pose
    sync can stop while held. Keep it for thrown and dropped weapons.
- Hit resolution stays on the owner (`Combat.strike` → `_net_receive_hit`).
  Don't move it.

### Suggested order of work (keep the game playable between steps)
1. **Visual swap.** Add the KayKit model, AnimationTree, and locomotion,
   dodge, hit, death and spawn clips. Hide the capsule mesh and hand spheres
   but leave the procedural hand nodes in place, so combat still works
   (weapons will float at the old hand spots for now). Fix team tint and the
   iframe fade.
2. **Weapons on bones.** Attach held weapons to `handslot` instead of the
   Hand Area3D, and move fist hitboxes to the attachments.
3. **Animated attacks.** Use per-weapon clips and drive hit windows from
   animation. Then delete the procedural swing code from the table above, and
   finally delete `Appendages`.
4. **Ranged, shield, throw and ball** clips.
5. **Network sync, bots, then tuning.** Re-check swing speeds and TTK against
   the design roadmap.

## Other possible uses
- **Props/Weapons and Props/Shields** could replace the visuals of the existing
  weapon scenes in `3D/Weapons/*` (Sword, Axe, Dagger, Hammer, Shield, Staff,
  Bow, Torch). The weapon scenes contain physics and hitboxes, so swap only
  their mesh children.
- **Rig_Large + Mannequin_Large** could serve as a large enemy or boss
  (the current boss is `3D/Entities/Boss_Slime`).
- **Skeletons_\* clips** (Rig_Medium) suit undead minions. No skeleton mesh is
  included; KayKit's Skeletons pack would provide one.

## Progress

**Step 1 (visual swap): done 2026-10-03.**
- `Rig_Medium/*.glb` import as Animation Libraries; loop flags are set in each
  `.import` `_subresources` (Idle/Walking/Running/Blocking/Aiming/etc.).
  Rig_Large is still imported as plain scenes.
- `3D/player_3d/player_visual_3d.gd` (`PlayerVisual3D`, node `Player/Visual`)
  owns the body. It swaps `Visual/Character` for a character picked by
  `player_id` (or the `character` export) and builds its AnimationTree in
  code: root BlendTree = `base` state machine (Move blendspace + TimeScale,
  Roll, Backstep, Stagger, Spawn) → `hit` OneShot filtered to the upper body.
  New upper-body attack layers should be added the same way as `hit`.
- Team color is a ring at the feet (`Visual/TeamRing`). The iframe fade uses
  `GeometryInstance3D.transparency`.
- The player now syncs `anim_pose` (`Pose.NONE/ROLL/BACKSTEP/STAGGER`).
  `body_tilt` now carries only the boost lean. The roll tumble is gone.
- The capsule, shoulder and hand spheres are hidden, not deleted. The
  procedural `Appendages` still drive combat, so weapons float at the old
  hand spots.
- Death has no clip because the player is hidden as soon as they die.

**Steps 2–3 (weapons on bones, animated attacks): done 2026-10-03.**
Decisions 1 and 2 above are settled: **independent arms**, and **the right
hand is the main hand**.
- `Appendages` and the capsule mesh are deleted, along with the whole
  procedural swing (shoulders, wrists, sway, hand-mesh sync, weapon springs).
- Held weapons ride the `handslot` bones rigidly. `PlayerVisual3D.hand(is_left)`
  is posed on `Skeleton3D.skeleton_updated` and re-poses held weapons at the
  same moment. While held, a weapon is frozen (kinematic) and its physics step
  runs after its wielder's. Thrown and dropped weapons get full physics back.
  Held weapons no longer stream their pose online; every machine poses them
  from the hand.
- **Hand rules** (`Weapon3D.grip`): MAIN_HAND = right only (sword, axe,
  hammer, staff, crossbow); OFF_HAND = left only (shield); EITHER_HAND
  (dagger, torch); TWO_HANDED = right, and it fills the left hand too
  (greataxe; either button swings it). Pickup, stands/altars, swap and the
  server's equip check all go through `PlayerClass3D.can_hold*` /
  `free_hand_for`. The matching-pair dual-wield follow-up was removed.
- **Attacks:** each arm has a Blend2 layer filtered to its arm bones, holding
  a frozen clip that is seeked every frame. `PlayerClass3D.arm_anim` =
  [action, phase] per arm (REST/SWING/THROW/HOLD; phase 0–1 wind-up, 1–2
  strike, 2–3 recovery). It is computed from the existing swing timers, so
  hitstop, rebound, draw-backs and `swing_duration`/`swing_windup` tuning
  all still work. Online it rides in `net_pose` in place of the shoulder
  yaws. `NetInterpolator` extras are now stepped rather than blended.
- Per weapon: `swing_clip`, `offhand_swing_clip`, `hold_clip` and
  `hold_offset` (exported on `Weapon3D`). Clip timing lives in
  `PlayerVisual3D.CLIP_KEYS`, measured from hand speed in each clip.
- The crossbow aims with `General/Use_Item`, because the `Ranged_1H_*` clips
  aim by turning the torso, which the arm-only layer leaves out.
- The ball is carried at the `Hold` node.

**Still to do:** carry pose for the ball; spawn/death clips for weapons;
tune weapon scales against the KayKit props (ours are noticeably bigger);
left-hand throws use the dual-wield chop and look weak; playtest swing feel
and re-check TTK (step 5).

**Weapon models (2026-10-03):** the weapons now use the KayKit weapons pack,
`Assets/Weapons/*.glb`. It was converted from FBX with Blender; the texture
is embedded, and the imports are set to keep it embedded
(`gltf/embedded_image_handling=3`). Like the character props, each model has
its grip at the origin and its blade along +Y, so it sits on the handslot
with no offset. The bows are the exception: they lie flat, so `bow_3d.tscn`
turns its model +90° about Y. The old BetterDungeon weapon models are deleted;
its torch model is kept, since the new pack has no torch.
- Re-skinned: Sword (`sword_B`), Axe (`axe_A`), Greataxe (`axe_B`), Dagger
  (`dagger_A`), Hammer (`hammer_A`), Shield (`shield_B`), Staff (`staff_B`)
  and arrows (`arrow_A`). "Bow" is now a real bow (`bow_A_withString`), not
  a crossbow. It is two-handed and rides the left hand (`Weapon3D.rides_left_hand`),
  holds `Ranged_Bow_Aiming_Idle` and shoots with `Ranged_Bow_Release`.
- New weapons: Scimitar (`sword_C`), Rapier (`sword_D`), Greatsword
  (`sword_E` at 0.75 scale, two-handed), Mace (`hammer_B`), Spear and
  Halberd (two-handed), Knuckles (`fistweapon_A`, either hand) and Wand
  (`wand_A`, fires `wand_bolt_3d`). They're in the altar tiers, chest loot
  and `GameTools3D.test_weapons`, but not on the DungeonArena's fixed stands.
- Unused variants left for later (e.g. rarity skins): sword_A (wooden),
  axe_C, hammer_C, dagger_B, shield_A/C, staff_A, bow_A/B, arrow_B and the
  other fist weapons.

**Fit fixes (2026-10-03):** the bow and block poses are side-on. The torso
twists into them (the bow's is mostly the hips, −45°), and an arm-only layer
left the bow beside the body, half inside it. There is now a `torso` layer
(hips, spine, chest, head) between `hit` and the arm layers. It plays the
clip of whichever arm is in a HOLD pose, or swinging a weapon with
`Weapon3D.turns_torso` (the bow). `shield_B` was about 1.5× KayKit's
character-pack shield and sat with the forearm through it, so its model is
at 0.8 scale with `hold_offset` (0, 0.1, 0.06).

**Swing feel and throws (2026-10-04):**
- The torso layer now follows every arm action, not just held poses.
- `PlayerVisual3D.CLIP_SWEEP` adds a whole-body yaw and pitch per attack
  clip. It winds back during the wind-up, whips through the strike, then
  settles. The yaw signs come from measuring each clip's strike direction.
- `WeaponTrail3D` is a ribbon behind melee blades. It's driven by the
  synced `arm_anim` strike phase plus blade speed, so it needs no
  networking, and it's tinted by rarity.
- Loose weapons stop tumbling on their first world contact, and lie flat
  (thinnest side up) once they hit the floor. `throw_point_first` (the spear)
  keeps the blade along the flight path.
- A lone shield is thrown with Throw + Attack (`main_hand_is_left(shield_too)`).
