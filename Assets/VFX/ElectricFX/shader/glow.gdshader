shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

uniform vec3 primary_color : source_color;
uniform vec3 secondary_color : source_color;

uniform float emission = 2.0;
uniform float exponent = 4.0;

void fragment() {
	float fresnel = clamp(pow(dot(VIEW, NORMAL), exponent), 0.0, 1.0);
	
	vec3 color = mix(secondary_color, primary_color, fresnel);
	
	ALBEDO = color * emission;
	
	ALPHA = fresnel * COLOR.a;
}