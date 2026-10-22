shader_type spatial;
// 七日杀原版建筑（远景网格）。每个顶点记着方块贴图号（UV2.x）。
// 有方块贴图数组时按贴图号取贴图，没有就用顶点颜色。

uniform sampler2DArray atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_atlas = false;

void fragment() {
	if (use_atlas) {
		ALBEDO = texture(atlas, vec3(UV, UV2.x)).rgb;
	} else {
		ALBEDO = COLOR.rgb;
	}
	ROUGHNESS = 0.92;
}
