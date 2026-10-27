@tool
extends VFXEmitterBB
class_name VFXElectricBallBB

var light : VFXOmniLightBB:
	get():
		if light and !Engine.is_editor_hint():
			return light
		
		var result = get_node_or_null("VFXOmniLightBB")
		if !Engine.is_editor_hint():
			light = result
		return result


@export_group("Color")

## The primary color of this effect.
@export var primary_color : Color:
	set(v):
		primary_color = v
		_set_shader_param("primary_color", primary_color)

## The secondary color of this effect.
@export var secondary_color : Color:
	set(v):
		secondary_color = v
		_set_shader_param("secondary_color", secondary_color)

## Emission of the effect. Higher values make it glowy.
@export var emission : float = 2.0:
	set(v):
		emission = v
		_set_shader_param("emission", emission)

@export_group("Light")

## Color of the emitted light of this effect
@export var light_color : Color:
	set(v):
		light_color = v
		if light: light.light_color = light_color

## Energy of the emitted light of this effect
@export var light_energy : float = 5.0:
	set(v):
		light_energy = v
		if light: light.vfx_light_energy = light_energy

## Energy of the indirect light emitted by this effect
@export var light_indirect_energy : float = 1.0:
	set(v):
		light_indirect_energy = v
		if light: light.vfx_light_indirect_energy = light_indirect_energy

## Energy of the light in volumetric fog emitted by this effect
@export var light_volumetric_fog_energy : float = 1.0:
	set(v):
		light_volumetric_fog_energy = v
		if light: light.vfx_light_volumetric_fog_energy = light_volumetric_fog_energy


@export_group("Shape")

@export var noise_texture : Texture2D:
	set(v):
		noise_texture = v
		_set_shader_param("noise_texture", noise_texture)

@export var noise_scale : Vector2 = Vector2(1.0, 1.0):
	set(v):
		noise_scale = v
		_set_shader_param("noise_scale", noise_scale)

@export var frequency : float = 1.0:
	set(v):
		frequency = v
		_set_shader_param("frequency", frequency)

@export var amplitude : float = 0.3:
	set(v):
		amplitude = v
		_set_shader_param("amplitude", amplitude)


@export_group("Transparency")

## Hardness of the edges of each part of this effect
@export_range(0.0, 1.0, 0.01) var edge_hardness : float = 1.0:
	set(v):
		edge_hardness = v
		_set_shader_param("edge_hardness", edge_hardness)

## Cutoff of the hard edges
@export_range(0.0, 1.0, 0.01) var edge_position : float = 0.0:
	set(v):
		edge_position = v
		_set_shader_param("edge_position", edge_position)
