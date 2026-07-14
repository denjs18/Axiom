shader_type spatial;
render_mode cull_back, unshaded;

// Voxel terrain shader — Minecraft-style baked lighting.
// COLOR.r = face shade (top bright / bottom dark)
// COLOR.g = sky light  (0..1, from the light engine)
// COLOR.b = block light (0..1, torches, lava, glowstone...)
// UV  = tiling coords (fract() tiles within the atlas cell)
// UV2 = atlas tile top-left

uniform sampler2D atlas : filter_nearest, repeat_disable, hint_default_white;
uniform float tile_size : hint_range(0.001, 1.0) = 0.0625;

// Driven every frame by DayNightCycle
uniform float sky_energy : hint_range(0.0, 1.5) = 1.0;
uniform vec3  sky_tint   : source_color = vec3(1.0);
uniform vec3  block_tint : source_color = vec3(1.0, 0.86, 0.66);

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
	float ao_mix = mix(0.84, 1.0, ao);

	// Minecraft-style light: sky and block light compete, brightest wins
	float floor_l = 0.045;                       // deepest caves stay barely readable
	vec3 skyl   = sky_tint * (COLOR.g * COLOR.g) * sky_energy;
	vec3 blockl = block_tint * (COLOR.b * COLOR.b);
	vec3 light  = max(max(skyl, blockl), vec3(floor_l));

	ALBEDO = col.rgb * COLOR.r * light * ao_mix;
}
