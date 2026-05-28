shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always;

uniform sampler2D atlas : filter_nearest, repeat_disable, hint_default_white;
uniform float tile_size : hint_range(0.001, 1.0) = 0.0625;

void fragment() {
	vec2 frac_uv = clamp(fract(UV), 0.001, 0.999);
	vec2 sample_uv = UV2 + frac_uv * tile_size;
	vec4 col = texture(atlas, sample_uv);
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = col.a;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
