shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float pulse = 0.5 - 0.5 * cos(TIME * 2.617993878);
	COLOR.a *= mix(0.12, 1.0, pulse);
}
