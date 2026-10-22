shader_type sky;
// 天空：颜色渐变 + 太阳/月亮 + 七日杀的云层（全景图，G 是云的厚度，R 是受光）+ 夜里的银河

uniform vec3 top_color : source_color = vec3(0.3, 0.5, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.7, 0.74);
uniform vec3 ground_color : source_color = vec3(0.2, 0.19, 0.17);
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform sampler2D stars : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_clouds = false;
uniform bool has_stars = false;
uniform float cloud_amount = 1.0;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_dark : source_color = vec3(0.45, 0.48, 0.55);
uniform float night = 0.0;
uniform float cloud_turn = 0.0;

// 方向 → 全景图坐标。七日杀是左手坐标，z 要反过来
vec2 pano_uv(vec3 d, float turn) {
	float lon = atan(d.x, -d.z) + turn;
	float lat = asin(clamp(d.y, -1.0, 1.0));
	return vec2(lon / (2.0 * PI) + 0.5, 0.5 - lat / PI);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 6.0, 0.0, 1.0));
	}
	if (has_stars && h > -0.05) {
		col += texture(stars, pano_uv(d, TIME * 0.002)).rgb * night * 2.5;
	}
	// 太阳 / 月亮的光晕和圆盘
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		vec3 lc = LIGHT0_COLOR * LIGHT0_ENERGY;
		col += lc * pow(max(sd, 0.0), 60.0) * 0.35 * (1.0 - night * 0.7);
		col += lc * smoothstep(0.9993, 0.9996, sd) * (night > 0.5 ? 0.6 : 3.0);
	}
	if (has_clouds && h > -0.02) {
		vec4 c = texture(clouds, pano_uv(d, cloud_turn));
		float a = clamp(c.g * 1.3, 0.0, 1.0) * cloud_amount * smoothstep(-0.02, 0.08, h);
		vec3 cc = mix(cloud_dark, cloud_lit, clamp(0.55 + c.r * 0.6, 0.0, 1.0));
		col = mix(col, cc, a);
	}
	COLOR = col;
}
