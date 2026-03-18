shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(1.0, 0.35, 0.35, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 tinted = mix(base.rgb, tint_color.rgb, tint_strength);
	COLOR = vec4(tinted, base.a * tint_color.a);
}
