@tool
extends VFXControllerBB
class_name VFXZapBB

var zap : GPUParticles3D:
	get():
		if zap and !Engine.is_editor_hint():
			return zap
		
		var result = get_node_or_null("Zap")
		if !Engine.is_editor_hint():
			zap = result
		return result

var zap_extra : GPUParticles3D:
	get():
		if zap_extra and !Engine.is_editor_hint():
			return zap_extra
		
		var result = get_node_or_null("ZapExtra")
		if !Engine.is_editor_hint():
			zap_extra = result
		return result

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

@export var noise_strength : float = 0.4:
	set(v):
		noise_strength = v
		_set_shader_param("noise_strength", noise_strength)

@export var frequency : float = 0.5:
	set(v):
		frequency = v
		_set_shader_param("frequency", frequency)

@export var amplitude : float = 0.4:
	set(v):
		amplitude = v
		_set_shader_param("amplitude", amplitude)

@export var height : float = 6.0:
	set(v):
		height = v
		
		if zap:
			zap.position.y = height / 2.0
			zap.draw_pass_1.height = height
		if zap_extra:
			zap_extra.position.y = height / 2.0
			zap_extra.draw_pass_1.height = height

@export var impact_frequency : float = 4.0:
	set(v):
		impact_frequency = v
		_set_shader_param("impact_frequency", impact_frequency)

@export var streaks_frequency : float = 8.0:
	set(v):
		streaks_frequency = v
		_set_shader_param("streaks_frequency", streaks_frequency)

@export_range(1, 3, 1) var zap_shape : int = 1:
	set(v):
		zap_shape = v
		_set_shader_param("zap_shape", zap_shape)

@export_group("Transparency")

## Hardness of the edges of each part of this effect
@export_range(0.0, 1.0, 0.01) var edge_hardness : float = 0.5:
	set(v):
		edge_hardness = v
		_set_shader_param("edge_hardness", edge_hardness)

## Cutoff of the hard edges
@export_range(0.0, 1.0, 0.01) var edge_position : float = 0.5:
	set(v):
		edge_position = v
		_set_shader_param("edge_position", edge_position)
