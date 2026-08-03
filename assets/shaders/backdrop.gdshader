shader_type canvas_item;
render_mode unshaded;

// Full-screen backdrop: sky gradient above ground, parallax rock strata below.
//
// The strata scroll at a fraction of the camera speed, so the space behind the
// tunnels reads as distant rock receding into the dark rather than a flat fill.
// One quad, no extra nodes, no per-frame CPU cost beyond two uniform writes.

uniform float cam_y = 0.0;          // camera centre, world px
uniform float view_h = 1280.0;      // viewport height, world px
uniform float depth_frac : hint_range(0.0, 1.0) = 0.0;

uniform vec3 sky_high : source_color = vec3(0.29, 0.55, 0.80);
uniform vec3 sky_low : source_color = vec3(0.66, 0.80, 0.90);
uniform vec3 rock_near : source_color = vec3(0.16, 0.105, 0.078);
uniform vec3 rock_far : source_color = vec3(0.075, 0.048, 0.042);
uniform vec3 core_glow : source_color = vec3(0.32, 0.09, 0.06);

uniform float parallax : hint_range(0.0, 1.0) = 0.35;
uniform float band_h = 210.0;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.52);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// World y of this pixel, then the parallax-shifted y used for strata.
	float wy = cam_y + (UV.y - 0.5) * view_h;
	float py = cam_y * parallax + (UV.y - 0.5) * view_h;

	vec3 col;

	if (wy < 0.0) {
		// Above ground: vertical sky gradient, warmer toward the horizon.
		float t = clamp(1.0 + wy / 900.0, 0.0, 1.0);
		col = mix(sky_high, sky_low, pow(t, 1.4));
	} else {
		// Underground: banded strata with organic noise, fading with depth.
		float band = vnoise(vec2(UV.x * 3.0, py / band_h));
		float grain = vnoise(vec2(UV.x * 14.0, py / 90.0)) * 0.35;
		float k = clamp(band * 0.8 + grain, 0.0, 1.0);

		col = mix(rock_far, rock_near, k);
		col = mix(col, core_glow, depth_frac * 0.55);
		col *= 1.0 - 0.30 * depth_frac;

		// Soft fade through the first screen below the surface so the sky
		// does not cut to rock on a hard line.
		float blend = clamp(wy / 420.0, 0.0, 1.0);
		float t = clamp(1.0 + wy / 900.0, 0.0, 1.0);
		col = mix(mix(sky_high, sky_low, pow(t, 1.4)), col, blend);
	}

	COLOR = vec4(col, 1.0);
}
