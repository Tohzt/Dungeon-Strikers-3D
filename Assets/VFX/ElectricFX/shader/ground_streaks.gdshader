shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform vec3 primary_color : source_color;
uniform float emission = 4.0;

uniform float streaks_frequency = 8.0;

group_uniforms Transparency;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.5;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	float y = UV.y * 1.0;
	
	float wave1 = (sin(UV.x * TAU * streaks_frequency + TIME) * 0.5 + 0.5) * 2.0;
	float wave2 = (sin(UV.x * TAU * (streaks_frequency + 1.0) - TIME) * 0.5 + 0.5) * 2.0;;
	float wave3 = sin(UV.x * TAU * (streaks_frequency * 8.0) + TIME) * 0.5 + 0.5;;
	
	float wave = wave1 + wave2 + wave3;
	
	float value = clamp(y - wave * 0.1, 0.0, 1.0);
	value = min(value, y);
	
	float edge_pos = pow(edge_position, 3.0);
	
	value = clamp((value - edge_pos) / (1.0 - edge_pos), 0.0, 1.0);
	float alpha = smoothstep(0.009 * edge_hardness, 1.0 - 0.99 * edge_hardness, value);
	
	ALBEDO = primary_color * emission * 2.0;
	ALPHA = alpha * COLOR.a;
}
