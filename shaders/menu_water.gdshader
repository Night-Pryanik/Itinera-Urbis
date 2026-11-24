shader_type canvas_item;
render_mode blend_mix;

// The mask is a black/white image of the river in city_panorama.jpg. Only its
// white parts receive a ripple, so the shore, the bridge and the mill stay
// untouched. UV spans the whole picture because the overlay uses the same
// fit-and-centre layout as the panorama. The uniforms are driven by
// main_menu_ambience.gd.
uniform float flow_speed : hint_range(0.0, 0.4, 0.005) = 0.055;
uniform float ripple_scale : hint_range(0.3, 4.0, 0.05) = 1.7;
uniform float opacity : hint_range(0.0, 0.6, 0.005) = 0.32;
uniform vec3 highlight_color : source_color = vec3(0.98, 0.99, 1.0);
uniform vec3 shade_color : source_color = vec3(0.04, 0.06, 0.09);

void fragment() {
    float water = COLOR.r;
    vec2 p = UV * ripple_scale;
    float t = TIME * flow_speed;

    // Every wave is continuous in TIME, so the animation has no loop point.
    // Advecting the phase along x reads as a slow current rather than a pulse.
    float fine = sin((p.x - t * 1.6) * 32.0 + p.y * 10.0 + sin(p.y * 7.0 - t) * 0.8);
    float middle = sin((p.x - t * 1.1) * 17.0 - p.y * 9.0 + 1.7);
    float broad = sin((p.x - t * 0.55) * 6.0 + p.y * 3.5);

    float ripple = fine * 0.28 + middle * 0.42 + broad * 0.30;
    // Light and shade in equal measure: on an already bright river a white-only
    // highlight has almost no contrast, while a moving darkening does.
    vec3 tint = ripple > 0.0 ? highlight_color : shade_color;
    COLOR = vec4(tint, water * abs(ripple) * opacity);
}
