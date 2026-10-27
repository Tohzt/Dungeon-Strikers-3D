shader_type spatial;
render_mode unshaded;

uniform vec3 primary_color : source_color;
uniform float emission = 2.0;

uniform sampler2D noise_texture;
uniform vec2 noise_scale = vec2(1.0);

group_uniforms Transparency;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.5;

void fragment() {
	float noise = texture(noise_texture, UV * noise_scale).r;
	float alpha = noise;
	alpha = smoothstep(1.0 - COLOR.a, 1.0, alpha);
	alpha = smoothstep(0.5 * edge_hardness, 1.0 - 0.5 * edge_hardness, alpha);
	
	ALBEDO = primary_color * emission;
	
	ALPHA = alpha;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
