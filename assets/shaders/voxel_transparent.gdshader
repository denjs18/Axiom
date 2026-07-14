shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, unshaded;

// Transparent voxel pass (water, glass, plants, torches).
// Same light encoding as voxel_opaque: COLOR.r shade, .g sky, .b block.

uniform sampler2D atlas : filter_nearest, repeat_disable, hint_default_white;
uniform float tile_size : hint_range(0.001, 1.0) = 0.0625;

uniform float sky_energy : hint_range(0.0, 1.5) = 1.0;
uniform vec3  sky_tint   : source_color = vec3(1.0);
uniform vec3  block_tint : source_color = vec3(1.0, 0.86, 0.66);

void fragment() {
	vec2 frac_uv = clamp(fract(UV), 0.001, 0.999);
	vec2 sample_uv = UV2 + frac_uv * tile_size;
	vec4 col = texture(atlas, sample_uv);
	if (col.a < 0.04) discard;

	float floor_l = 0.045;
	vec3 skyl   = sky_tint * (COLOR.g * COLOR.g) * sky_energy;
	vec3 blockl = block_tint * (COLOR.b * COLOR.b);
	vec3 light  = max(max(skyl, blockl), vec3(floor_l));

	ALBEDO = col.rgb * COLOR.r * light;
	ALPHA  = col.a;
}
