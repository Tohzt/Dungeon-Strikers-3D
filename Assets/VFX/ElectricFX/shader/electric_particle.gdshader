shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

uniform vec3 primary_color : source_color;
uniform vec3 secondary_color : source_color;
uniform float emission = 2.0;

uniform sampler2D noise_texture;
uniform vec2 noise_scale = vec2(1.0);

uniform float frequency = 1.5;
uniform float amplitude = 0.3;

group_uniforms Transparency;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.0;

float sample_wave(float y, float freq, float offset) {
	float wave = abs(fract(y * freq + offset) * 2.0 - 1.0) - 0.5;
	return wave;
}

float sample_noise(vec2 uv) {
	return texture(noise_texture, uv * noise_scale).r;
}

void vertex() {
	float mask = 1.0 - abs(UV.y * 4.0 - 1.0);
	
	float motion = TIME * 0.1;
	
	float rand = COLOR.r;
	
	float wave1 = sample_wave(UV.y * 2.0, frequency, 0.0 + motion + rand);
	float wave2 = sample_wave(UV.y * 2.0, frequency, PI  + motion - rand);
	
	vec2 wave = vec2(wave1, wave2);
	
	VERTEX.xz *= mask;
	
	VERTEX.xz += wave * amplitude;
}

void fragment() {
	float fresnel = pow(dot(VIEW, NORMAL), 2.0);
	
	float noise = sample_noise(UV);
	noise -= 1.0 - COLOR.a;
	noise *= fresnel;
	
	noise -= edge_position;
	float alpha = smoothstep(0.0, 1.0 * (1.0 - edge_hardness), noise);
	
	float value = mix(fresnel, step(0.6, fresnel), edge_hardness);
	
	vec3 color = mix(secondary_color, primary_color, value);
	
	ALBEDO = color * emission;
	ALPHA = alpha;
}