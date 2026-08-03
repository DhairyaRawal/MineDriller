shader_type canvas_item;
render_mode unshaded;

// Terrain rim shading.
//
// Chunk textures are a pixel mask: carved rock is transparent, solid rock is
// opaque. This shader samples the alpha channel in a ring around each solid
// pixel and darkens it in proportion to how much open space is nearby, so
// every tunnel wall gets a soft contact shadow and reads as a recessed 3D
// hole. It runs on the carve mask itself, which means freshly drilled tunnels
// are shaded the instant they appear -- no CPU work, no per-tile bevel (a
// bevel would re-introduce the blocky grid look we deliberately removed).

uniform float rim_radius : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.72;
uniform vec3 rim_tint : source_color = vec3(0.05, 0.03, 0.02);

// Depth grading: the deeper the chunk, the hotter and darker the rock.
uniform float depth_frac : hint_range(0.0, 1.0) = 0.0;
uniform vec3 deep_tint : source_color = vec3(1.0, 0.62, 0.48);
uniform float deep_darken : hint_range(0.0, 1.0) = 0.32;

// Large-scale mottling. The rock texture is one 32px tile stamped over and
// over, which the eye reads as a repeating pattern. Smooth noise at a scale of
// several cells breaks the repeat -- deliberately NOT per-cell, because
// cell-uniform brightness just draws the grid back in as a checkerboard.
uniform vec2 cell_uv = vec2(0.03125, 0.0625);
uniform float chunk_id = 0.0;
uniform float mottle : hint_range(0.0, 0.5) = 0.20;

const int RING = 8;

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

// Alpha at an offset, treating anything outside the chunk as solid so that
// vertical chunk seams never render as a dark line.
float alpha_at(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 1.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);

	if (src.a < 0.02) {
		// Carved space: fully transparent, the dark backdrop shows through.
		COLOR = vec4(0.0);
	} else {
		vec2 texel = TEXTURE_PIXEL_SIZE;
		float openness = 0.0;

		// Two rings give a softer falloff than one, for the cost of 16 taps.
		for (int i = 0; i < RING; i++) {
			float a = (float(i) / float(RING)) * 6.2831853;
			vec2 dir = vec2(cos(a), sin(a));
			openness += (1.0 - alpha_at(TEXTURE, UV + dir * texel * rim_radius)) * 0.65;
			openness += (1.0 - alpha_at(TEXTURE, UV + dir * texel * rim_radius * 0.5)) * 0.35;
		}
		openness = clamp(openness / float(RING), 0.0, 1.0);

		vec3 rgb = src.rgb;

		// Break up the tile repeat before anything else. Coordinates are in
		// cell units and offset by chunk so the pattern is continuous across
		// chunk seams; the frequencies are fractional so features never line
		// up with cell edges.
		vec2 cpos = UV / cell_uv + vec2(0.0, chunk_id * 16.0);
		float m = vnoise(cpos * 0.37) * 0.65 + vnoise(cpos * 1.13) * 0.35;
		rgb *= 1.0 - mottle * 0.5 + mottle * m;

		// Depth grading, so the rim shadow sits on top of graded rock.
		rgb = mix(rgb, rgb * deep_tint, depth_frac);
		rgb *= 1.0 - deep_darken * depth_frac;

		// Contact shadow into the opening.
		rgb = mix(rgb, rim_tint, openness * rim_strength);

		COLOR = vec4(rgb, src.a);
	}
}
