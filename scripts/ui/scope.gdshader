shader_type canvas_item;
// 高倍镜画面：圆形透明镜筒，外面压黑，里面画十字准星。

uniform float aspect = 1.7778;
uniform float radius = 0.36;
uniform vec4 mask_color : source_color = vec4(0.01, 0.01, 0.01, 0.97);
uniform vec4 reticle_color : source_color = vec4(0.9, 0.88, 0.78, 0.95);

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= aspect;
	float d = length(p);
	float outside = smoothstep(radius - 0.004, radius + 0.004, d);
	float inside = 1.0 - outside;
	vec2 q = abs(UV - vec2(0.5));
	float cross_h = 1.0 - smoothstep(0.0007, 0.0015, q.y);
	float cross_v = 1.0 - smoothstep(0.0007, 0.0015, q.x);
	float dot = 1.0 - smoothstep(0.002, 0.0035, d);
	float reticle = max(max(cross_h, cross_v), dot) * inside;
	vec4 c = vec4(mask_color.rgb, outside * mask_color.a);
	c = mix(c, reticle_color, reticle * reticle_color.a);
	COLOR = c;
}
