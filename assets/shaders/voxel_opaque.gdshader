shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas : filter_nearest, repeat_disable, hint_default_white;
uniform float tile_size : hint_range(0.001, 1.0) = 0.0625;

void fragment() {
	vec2 frac_uv = clamp(fract(UV), 0.001, 0.999);
	vec2 sample_uv = UV2 + frac_uv * tile_size;
	vec4 col = texture(atlas, sample_uv);
	if (col.a < 0.5) discard;

	// Subtle edge shading — just enough to give block separation without a harsh grid
	float edge_x = min(frac_uv.x, 1.0 - frac_uv.x);
	float edge_y = min(frac_uv.y, 1.0 - frac_uv.y);
	float edge   = min(edge_x, edge_y);
	float ao     = smoothstep(0.0, 0.07, edge);
	float ao_mix = mix(0.82, 1.0, ao);

	ALBEDO    = col.rgb * COLOR.rgb * ao_mix;
	ROUGHNESS = 1.0;
	METALLIC  = 0.0;
}
