shader_type canvas_item;
render_mode unshaded;

// Depth vignette: a pool of light around the pod that tightens as you descend.
//
// At the surface this is almost invisible. By the Core it closes to a tight
// lamp, which does three things at once -- sells "deep underground", pushes
// the eye to the pod, and makes the heat bar's red glow read stronger against
// a darker frame.

uniform vec2 light_uv = vec2(0.5, 0.5);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float radius : hint_range(0.1, 2.0) = 0.95;
uniform float aspect = 0.5625;      // width / height
uniform vec3 shade : source_color = vec3(0.02, 0.01, 0.015);

void fragment() {
	vec2 d = UV - light_uv;
	d.x /= max(aspect, 0.0001);      // circular in screen space, not stretched
	float dist = length(d);

	float v = smoothstep(radius * 0.30, radius, dist);
	COLOR = vec4(shade, v * strength);
}
