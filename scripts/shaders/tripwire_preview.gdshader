shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, fog_disabled;

uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 32.0) = 100.0;
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 10.0;

void fragment() {
	ALBEDO = line_color.rgb;
	EMISSION = line_color.rgb * emission_strength;
	ALPHA = line_color.a * alpha_multiplier;
}