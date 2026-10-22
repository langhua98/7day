shader_type spatial;
// 七日杀原版建筑（远景网格）。每个顶点带着方块贴图信息：
//   UV2.x = 这种贴图在图集里的起始层（-1 = 没有贴图，用顶点颜色）
//   UV2.y = 大贴图横竖各占几个方块（1 或 2），按方块位置取对应的那一层
// 贴图按模型里的位置投影，每个方块（1 米）铺一次，和游戏里一样。

uniform sampler2DArray atlas : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray atlas_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_atlas = false;
uniform float normal_strength = 1.0;

varying vec3 local_pos;
varying vec2 tex_info;

void vertex() {
	local_pos = VERTEX;
	tex_info = UV2;
}

void fragment() {
	ROUGHNESS = 0.9;
	if (!use_atlas || tex_info.x < 0.0) {
		ALBEDO = COLOR.rgb;
	} else {
		// 这个面朝哪（模型空间），用相邻像素算出真正的面法线，避免拐角处顶点法线被平均
		vec3 gn_v = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(gn_v, VERTEX) > 0.0) {
			gn_v = -gn_v;
		}
		mat3 to_model = transpose(mat3(MODEL_MATRIX)) * mat3(INV_VIEW_MATRIX);
		vec3 gn = normalize(to_model * gn_v);
		vec3 an = abs(gn);
		// 往面里面挪一点再取方块格子，免得正好落在格子边上
		vec3 p = local_pos - gn * 0.01;
		vec2 uvm;     // 以米为单位，x 向右、y 向下（和图片方向一致）
		vec3 t_axis;  // uvm.x 增大的方向
		vec3 b_axis;  // 图片“向上”的方向
		if (an.y >= an.x && an.y >= an.z) {
			uvm = vec2(p.x, p.z);
			t_axis = vec3(1.0, 0.0, 0.0);
			b_axis = vec3(0.0, 0.0, -1.0);
		} else if (an.x >= an.z) {
			float s = sign(gn.x);
			uvm = vec2(-s * p.z, -p.y);
			t_axis = vec3(0.0, 0.0, -s);
			b_axis = vec3(0.0, 1.0, 0.0);
		} else {
			float s = sign(gn.z);
			uvm = vec2(s * p.x, -p.y);
			t_axis = vec3(s, 0.0, 0.0);
			b_axis = vec3(0.0, 1.0, 0.0);
		}
		float blocks = max(tex_info.y, 1.0);
		vec2 cell = mod(floor(uvm), blocks);
		float layer = tex_info.x + cell.x + cell.y * blocks;
		vec2 uv = fract(uvm);
		vec2 dx = dFdx(uvm);
		vec2 dy = dFdy(uvm);
		ALBEDO = textureGrad(atlas, vec3(uv, layer), dx, dy).rgb;
		// 法线图压缩后只剩 x、y 两个通道，z 自己算
		vec2 nxy = (textureGrad(atlas_normal, vec3(uv, layer), dx, dy).rg * 2.0 - 1.0) * normal_strength;
		float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.05));
		vec3 nm = normalize(t_axis * nxy.x + b_axis * nxy.y + gn * nz);
		NORMAL = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * nm);
	}
}
