shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

uniform vec3 primary_color : source_color;
uniform vec3 secondary_color : source_color;
uniform float emission = 2.0;

uniform float impact_frequency = 4.0;

uniform float grow_amount : hint_range(0.0, 1.0, 0.01) = 0.5;

group_uniforms Transparency;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	float radius = length(centered_uv);
	float angle = atan(centered_uv.x, centered_uv.y);
	
	float wave1 = (sin(angle * impact_frequency + radius + COLOR.r * PI) * 0.5 + 0.5) * 2.0;
	float wave2 = (sin(angle * impact_frequency * 1.76 - radius - COLOR.r * 0.5) * 0.5 + 0.5) * 1.5;
	float wave3 = sin(angle * impact_frequency * PI + radius + COLOR.r * PI) * 0.5 + 0.5;
	float wave4 = (sin(angle * (impact_frequency * 10.0 + 1.0) + radius - COLOR.r * 0.5) * 0.5 + 0.5) * 0.2;
	
	float wave = (wave1 + wave2 + wave3 + wave4);
	
	float factor = COLOR.a;
	factor = 1.0 - factor;
	
	float value = radius + wave * 0.1;
	value -= grow_amount - factor;
	value = max(1.0 - abs(value / factor), 0.0);
	
	value = clamp((value - edge_position) / (1.0 - edge_position), 0.0, 1.0);
	float alpha = smoothstep(0.1 * edge_hardness, 1.0 - 0.9 * edge_hardness, value);
	
	value = mix(value, floor(value * 4.0) / 3.0, edge_hardness);
	
	vec3 color = mix(secondary_color, primary_color, value);
	
	ALBEDO = color * 0.5 * ((1.0 + value * emission));
	ALPHA = alpha;
}