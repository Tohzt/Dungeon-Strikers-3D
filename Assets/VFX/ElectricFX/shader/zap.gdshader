shader_type spatial;
render_mode unshaded;

uniform vec3 primary_color : source_color;
uniform vec3 secondary_color : source_color;

uniform sampler2D noise_texture;
uniform vec2 noise_scale = vec2(1.0);
uniform float noise_strength = 0.4;

uniform float frequency = 0.4;
uniform float amplitude = 0.4;
uniform int zap_shape : hint_range(1, 3, 1) = 1;

float sample_wave(float y, float freq, float offset) {
	float wave = abs(fract(y * freq + offset) * 2.0 - 1.0) - 0.5;
	if (zap_shape == 1){
		return wave;
	} else if (zap_shape == 2) {
		return wave * wave * wave * 6.0;
	} else {
		return wave * wave * wave * wave * wave * 30.0;
	}
}

float sample_noise(vec2 uv) {
	return texture(noise_texture, uv * noise_scale).r;
}

void vertex(){
	float y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	
	float motion = TIME * 0.1;
	
	float rand = COLOR.r;
	
	float wave1 = sample_wave(y, frequency, 0.0 + motion + rand);
	float wave2 = sample_wave(y, frequency * 1.5, PI - motion - rand);
	float wave3 = sample_wave(y, frequency, -PI + motion + rand);
	float wave4 = sample_wave(y, frequency * 1.5, -TAU - motion - rand);
	
	vec2 offset = vec2(wave1 + wave2, wave3 + wave4);
	
	float mask = pow(1.0 - (UV.y * 2.0), 0.5);
	
	VERTEX.xz += offset * amplitude * mask * (1.0 + (1.0 - COLOR.a));
	
	float detail = sample_noise(vec2(UV.x, y)) * noise_strength * mask;
	
	VERTEX.xz += NORMAL.xz * detail * offset;
}

void fragment() {
	float fresnel = pow(dot(VIEW, NORMAL), 2.0);
	
	float noise = sample_noise(vec2(UV.x, UV.y * 2.0));
	
	float alpha = step(1.0 - COLOR.a, noise);
	
	alpha = clamp(alpha * (UV.y * 4.0), 0.0, 1.0);
	
	float value = step(0.5, fresnel);
	
	vec3 color = mix(secondary_color, primary_color, value);
	
	ALBEDO = color * 3.0;
	
	ALPHA = alpha;
}