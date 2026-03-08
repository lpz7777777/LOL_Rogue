shader_type spatial;

// LOL 风格草地 / 战线土地着色器
uniform vec4 color_dark: source_color = vec4(0.18, 0.42, 0.18, 1.0);
uniform vec4 color_light: source_color = vec4(0.32, 0.58, 0.28, 1.0);
uniform vec4 color_lane: source_color = vec4(0.45, 0.52, 0.38, 1.0);
uniform float cell_size: hint_range(1.0, 15.0) = 4.0;
uniform float noise_scale: hint_range(0.0, 0.2) = 0.08;
uniform float lane_width: hint_range(0.0, 0.15) = 0.04;
uniform bool show_lanes = true;

varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_pos = world_position.xz;
	
	vec2 cell_coord = floor(world_pos / cell_size);
	vec2 local_coord = fract(world_pos / cell_size);
	
	float checker = mod(cell_coord.x + cell_coord.y, 2.0);
	vec3 base_color = mix(color_dark.rgb, color_light.rgb, checker);
	
	float n = noise(world_pos * 0.15);
	base_color = mix(base_color, base_color * (0.92 + n * 0.16), noise_scale);
	
	if (show_lanes) {
		float lane_dist = min(abs(world_pos.x), abs(world_pos.y)) * 0.05;
		float lane_streak = 1.0 - smoothstep(0.0, 12.0, lane_dist) * 0.15;
		base_color = mix(color_lane.rgb, base_color, lane_streak);
	}
	
	ALBEDO = base_color;
	METALLIC = 0.0;
	ROUGHNESS = 0.92;
}