#version 450
// classicNoisedeck/effects — ported PIXEL-IDENTICALLY from wgsl/effects.wgsl. A multi-effect
// post processor: an affine uv transform (scale/rotate/offset) + flip/mirror, then one of
// ~20 leaf effects (convolution kernels, derivatives/sobel/edge/emboss/outline/shadow,
// pixellate, posterize, cga, subpixel, bloom, zoomBlur), then brightness/contrast/saturate.
// Single render pass (progName "effects").
//
// EFFECT and FLIP are COMPILE-TIME integer #defines injected by the runtime (effects.json
// globals effect.define=EFFECT, flip.define=FLIP). Keep them as bare identifiers; do not
// declare them. Only the reachable variant is compiled (default effect=0 -> EFFECT=0, so the
// `effectAmt != 0 && EFFECT != 0` block is dead and the transform + bc/sat path is tested).
//
// No-layout effect (effects.json has NO uniformLayout): the backend SYNTHESIZES the Params
// UBO and injects `#define <name> data[slot].comp` for the params (effectAmt, scaleAmt,
// rotation, offsetX, offsetY, intensity, saturation) and the 8 engine globals. Use bare
// names: the WGSL `u.effectAmt` -> `effectAmt`, `u.resolution` -> `resolution`, etc.
//
// RESERVED-NAME RENAME: the WGSL helper `fn aspectRatio()` collided with the injected
// `#define aspectRatio data[0].w` (aspectRatio is one of the 8 reserved engine globals, so a
// macro always exists); the reference GLSL reads the engine global directly, and so does
// this port now — the helper is gone. All other helper/local names are collision-free.
//
// COORDINATE NOTE: ported from WGSL (top-left). uv = gl_FragCoord.xy / resolution. NO Y-flip.
// textureSample -> texture; WGSL float `%` -> GLSL `mod`; `select(a,b,c)` -> `c ? b : a`.
// `array<f32,9>` params -> GLSL `float[9]`; `array<vec2f,9>` -> `vec2[9]`.
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag;

const float FX_PI = 3.14159265359;
const float FX_TAU = 6.28318530718;

// The reference maps a full-image coordinate into this tile's input texture as
// (uv * fullResolution - tileOffset) / textureSize. Untiled, tileOffset is 0
// and fullResolution is the render size. The division by the texture size is
// x * rcp(size), which need not return uv exactly; compute it the same way.
vec2 inputCoord(vec2 uv) {
	return (uv * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
}

float mapRange(float value, float inMin, float inMax, float outMin, float outMax) {
	// The final division lowers differently: Dawn computes x * rcp(span)
	// (approximate reciprocal), ANGLE a correctly-rounded divide, so mapped
	// values differ by ~1 ulp and knife-edge taps flip. One Newton-Raphson
	// step pins the reciprocal to the same value on both backends (multiply
	// and subtract are correctly rounded in both Metal math modes). The clamp
	// keeps the span*rmul product from fusing into the (2.0 - ...) subtract.
	float span = inMax - inMin;
	float rmul = 1.0 / span;
	float mc = min(max(span * rmul, -1e38), 1e38);
	return outMin + (outMax - outMin) * ((value - inMin) * (rmul * (2.0 - mc)));
}

// PCG PRNG
uvec3 fxPcg(uvec3 v_in) {
	uvec3 v = v_in * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> uvec3(16u);
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return v;
}

vec3 fxPrng(vec3 p) {
	return vec3(fxPcg(uvec3(p))) / float(0xffffffffu);
}

vec3 brightnessContrast(vec3 color) {
	float bright = mapRange(intensity, -100.0, 100.0, -0.4, 0.4);
	float cont = 1.0;
	if (intensity < 0.0) {
		cont = mapRange(intensity, -100.0, 0.0, 0.5, 1.0);
	} else {
		cont = mapRange(intensity, 0.0, 100.0, 1.0, 1.5);
	}
	return (color - 0.5) * cont + 0.5 + bright;
}

vec3 saturateFn(vec3 color) {
	float sat = mapRange(saturation, -100.0, 100.0, -1.0, 1.0);
	float avg = (color.r + color.g + color.b) / 3.0;
	return color - (avg - color) * sat;
}

// As the reference GLSL (mod(h * 6, 2), not fract(h * 6) * 2).
vec3 hsv2rgb(vec3 hsv) {
    float h = fract(hsv.x);
    float s = hsv.y;
    float v = hsv.z;
    
    float c = v * s; // Chroma
    float x = c * (1.0 - abs(mod(h * 6.0, 2.0) - 1.0));
    float m = v - c;

    vec3 rgb;

    if (0.0 <= h && h < 1.0/6.0) {
        rgb = vec3(c, x, 0.0);
    } else if (1.0/6.0 <= h && h < 2.0/6.0) {
        rgb = vec3(x, c, 0.0);
    } else if (2.0/6.0 <= h && h < 3.0/6.0) {
        rgb = vec3(0.0, c, x);
    } else if (3.0/6.0 <= h && h < 4.0/6.0) {
        rgb = vec3(0.0, x, c);
    } else if (4.0/6.0 <= h && h < 5.0/6.0) {
        rgb = vec3(x, 0.0, c);
    } else if (5.0/6.0 <= h && h < 1.0) {
        rgb = vec3(c, 0.0, x);
    } else {
        rgb = vec3(0.0, 0.0, 0.0);
    }

    return rgb + vec3(m, m, m);
}

vec3 rgb2hsv(vec3 rgb) {
	float maxC = max(rgb.r, max(rgb.g, rgb.b));
	float minC = min(rgb.r, min(rgb.g, rgb.b));
	float delta = maxC - minC;
	float h = 0.0;
	if (delta != 0.0) {
		if (maxC == rgb.r) { h = mod((rgb.g - rgb.b) / delta, 6.0) / 6.0; }
		else if (maxC == rgb.g) { h = ((rgb.b - rgb.r) / delta + 2.0) / 6.0; }
		else { h = ((rgb.r - rgb.g) / delta + 4.0) / 6.0; }
	}
	float s = maxC != 0.0 ? delta / maxC : 0.0;
	return vec3(h, s, maxC);
}

vec3 posterizeFn(vec3 color, float levIn) {
	float lev = levIn;
	if (lev == 0.0) { return color; }
	else if (lev == 1.0) { return step(vec3(0.5), color); }
	float gamma = 0.65;
	vec3 c = pow(color, vec3(gamma));
	c = floor(c * lev) / lev;
	return pow(c, vec3(1.0 / gamma));
}

vec3 pixellate(vec2 uv_in, float sizeIn) {
	float size = sizeIn;
	if (size < 1.0) { return texture(inputTex, inputCoord(uv_in)).rgb; }
	size *= 4.0;
	// The block grid is anchored to the full image, so its cell size is a
	// fraction of fullResolution (the tile size under tiling). Untiled the
	// two resolutions are equal, so this is byte-identical to the previous
	// resolution-based grid. The reference multiplies by the reciprocal
	// instead of dividing; keep its exact rounding.
	float dx = size * (1.0 / fullResolution.x);
	float dy = size * (1.0 / fullResolution.y);
	uv_in -= 0.5;
	vec2 coord = vec2(dx * floor(uv_in.x / dx), dy * floor(uv_in.y / dy));
	coord += 0.5;
	return texture(inputTex, inputCoord(coord)).rgb;
}

vec3 desaturate(vec3 color) {
	float avg = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
	return vec3(avg);
}

vec3 convolve(vec2 uv, float kernel[9], bool divide) {
	// One kernel step is one full-image pixel. Untiled the full resolution
	// equals the canvas resolution; under tiling the canvas is the tile, so
	// the tile resolution would double every kernel step.
	vec2 steps = 1.0 / fullResolution;
	vec2 offs[9] = vec2[9](
		vec2(-steps.x, -steps.y), vec2(0.0, -steps.y), vec2(steps.x, -steps.y),
		vec2(-steps.x, 0.0), vec2(0.0, 0.0), vec2(steps.x, 0.0),
		vec2(-steps.x, steps.y), vec2(0.0, steps.y), vec2(steps.x, steps.y)
	);
	float kernelWeight = 0.0;
	vec3 conv = vec3(0.0);
	for (int i = 0; i < 9; i++) {
		vec3 color = texture(inputTex, uv + offs[i] * effectAmt).rgb;
		conv += color * kernel[i];
		kernelWeight += kernel[i];
	}
	if (divide && kernelWeight != 0.0) { conv /= kernelWeight; }
	return clamp(conv, vec3(0.0), vec3(1.0));
}

vec3 derivativesFn(vec3 color, vec2 uv, bool divide) {
	float deriv_x[9] = float[9](0.0, 0.0, 0.0, 0.0, 1.0, -1.0, 0.0, 0.0, 0.0);
	float deriv_y[9] = float[9](0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, -1.0, 0.0);
	vec3 s1 = convolve(uv, deriv_x, divide);
	vec3 s2 = convolve(uv, deriv_y, divide);
	return color * distance(s1, s2);
}

vec3 sobelFn(vec3 color, vec2 uv) {
	float sobel_x[9] = float[9](1.0, 0.0, -1.0, 2.0, 0.0, -2.0, 1.0, 0.0, -1.0);
	float sobel_y[9] = float[9](1.0, 2.0, 1.0, 0.0, 0.0, 0.0, -1.0, -2.0, -1.0);
	vec3 s1 = convolve(uv, sobel_x, false);
	vec3 s2 = convolve(uv, sobel_y, false);
	return color * distance(s1, s2);
}

vec3 outlineFn(vec3 color, vec2 uv) {
	float sobel_x[9] = float[9](1.0, 0.0, -1.0, 2.0, 0.0, -2.0, 1.0, 0.0, -1.0);
	float sobel_y[9] = float[9](1.0, 2.0, 1.0, 0.0, 0.0, 0.0, -1.0, -2.0, -1.0);
	vec3 s1 = convolve(uv, sobel_x, false);
	vec3 s2 = convolve(uv, sobel_y, false);
	return max(color - distance(s1, s2), vec3(0.0));
}

vec3 shadowFn(vec3 color_in, vec2 uv) {
	float sobel_x[9] = float[9](1.0, 0.0, -1.0, 2.0, 0.0, -2.0, 1.0, 0.0, -1.0);
	float sobel_y[9] = float[9](1.0, 2.0, 1.0, 0.0, 0.0, 0.0, -1.0, -2.0, -1.0);
	vec3 color = rgb2hsv(color_in);
	vec3 x = convolve(uv, sobel_x, false);
	vec3 y = convolve(uv, sobel_y, false);
	float shade_dist = distance(x, y);
	float highlight = shade_dist * shade_dist;
	float shade = (1.0 - ((1.0 - color.z) * (1.0 - highlight))) * shade_dist;
	color = vec3(color.x, color.y, mix(color.z, shade, 0.75));
	return hsv2rgb(color);
}

vec3 convolutionEffect(vec3 color, vec2 uv) {
	float emboss[9] = float[9](-2.0, -1.0, 0.0, -1.0, 1.0, 1.0, 0.0, 1.0, 2.0);
	float sharpen[9] = float[9](-1.0, 0.0, -1.0, 0.0, 5.0, 0.0, -1.0, 0.0, -1.0);
	float blur[9] = float[9](1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0);
	float edge2[9] = float[9](-1.0, 0.0, -1.0, 0.0, 4.0, 0.0, -1.0, 0.0, -1.0);
	float edge3[9] = float[9](-0.875, -0.75, -0.875, -0.75, 5.0, -0.75, -0.875, -0.75, -0.875);
	float sharpenBlur[9] = float[9](-2.0, 2.0, -2.0, 2.0, 1.0, 2.0, -2.0, 2.0, -2.0);

	if (EFFECT == 1) { return convolve(uv, blur, true); }
	else if (EFFECT == 2) { return derivativesFn(color, uv, true); }
	else if (EFFECT == 120) { return clamp(derivativesFn(color, uv, false) * 2.5, vec3(0.0), vec3(1.0)); }
	else if (EFFECT == 3) { return color * convolve(uv, edge2, true); }
	else if (EFFECT == 4) { return convolve(uv, emboss, false); }
	else if (EFFECT == 5) { return outlineFn(color, uv); }
	else if (EFFECT == 6) { return shadowFn(color, uv); }
	else if (EFFECT == 7) { return convolve(uv, sharpen, false); }
	else if (EFFECT == 8) { return sobelFn(color, uv); }
	else if (EFFECT == 9) { return max(color, convolve(uv, edge2, true)); }
	else if (EFFECT == 300) { return convolve(uv, sharpenBlur, true); }
	else if (EFFECT == 301) { return convolve(uv, edge3, true); }
	return color;
}

vec3 cga(vec4 color, vec2 st, vec2 globalCoord) {
	float amt = mapRange(effectAmt, 0.0, 20.0, 0.0, 5.0);
	if (amt < 0.01) { return color.rgb; }
	float pixelDensity = amt * renderScale;
	float size = 2.0 * pixelDensity;
	float dSize = 2.0 * size;
	// The block grid is anchored to the full image, so the block count uses
	// the full resolution (the tile resolution under tiling).
	float amount = fullResolution.x / size;
	float d = 1.0 / amount;
	// The GLSL takes this ratio from fullResolution, so the block grid keeps
	// its shape across print tiles.
	float ar = fullResolution.x / fullResolution.y;
	float sx = floor(st.x / d) * d;
	d = ar / amount;
	float sy = floor(st.y / d) * d;
	// The block grid is globally anchored, so the snapped block center is a
	// full-image coordinate; map it into this tile's input texture.
	vec4 base = texture(inputTex, inputCoord(vec2(sx, sy)));
	float lum = 0.2126 * base.r + 0.7152 * base.g + 0.0722 * base.b;
	float o = floor(6.0 * lum);
	vec3 black = vec3(0.0);
	vec3 light = vec3(85.0, 255.0, 255.0) / 255.0;
	vec3 dark = vec3(254.0, 84.0, 255.0) / 255.0;
	vec3 white = vec3(1.0);
	vec3 c1 = black;
	vec3 c2 = black;
	if (o == 0.0) { c1 = black; c2 = black; }
	else if (o == 1.0) { c1 = black; c2 = dark; }
	else if (o == 2.0) { c1 = dark; c2 = dark; }
	else if (o == 3.0) { c1 = dark; c2 = light; }
	else if (o == 4.0) { c1 = light; c2 = light; }
	else if (o == 5.0) { c1 = light; c2 = white; }
	else { c1 = white; c2 = white; }
	// The checker phase is anchored to the full image (tileOffset is 0
	// untiled), so the pattern does not restart at every tile boundary.
	vec3 result = c1;
	if (mod(globalCoord.x, dSize) > size) {
		if (mod(globalCoord.y, dSize) > size) { result = c1; } else { result = c2; }
	} else {
		if (mod(globalCoord.y, dSize) > size) { result = c2; } else { result = c1; }
	}
	return result;
}

vec3 subpixel(vec2 st, float scaleIn) {
	// The GLSL scales the stripe width by renderScale for whole-canvas
	// high-resolution export.
	float scale = mapRange(scaleIn, 0.0, 100.0, 0.0, 10.0) * renderScale;
	vec3 orig = pixellate(st, scale);
	vec3 color = orig;
	// The stripe mask is anchored to the full image in full-image pixels
	// (equal to tile pixels untiled), so the stripes do not shift or
	// rescale at tile boundaries.
	vec2 coord = floor(st * fullResolution);
	float m = mod(coord.x, 4.0 * scale);
	if (mod(coord.y, 4.0 * scale) <= scale) {
		color *= vec3(0.0);
	} else if (m <= scale) {
		color *= vec3(1.0, 0.0, 0.0);
	} else if (m <= 2.0 * scale) {
		color *= vec3(0.0, 1.0, 0.0);
	} else if (m <= 3.0 * scale) {
		color *= vec3(0.0, 0.0, 1.0);
	} else {
		color *= vec3(0.0);
	}
	float factor = clamp(scale * 0.25, 0.0, 1.0);
	return mix(orig, color, factor);
}

vec3 bloomFn(vec2 st) {
	// Bloom samples a small neighborhood of the full-image coordinate st, so
	// every tap maps through the tile mapping (identity untiled).
	vec3 sum = vec3(0.0);
	vec3 orig = texture(inputTex, inputCoord(st)).rgb;
	float strength = mapRange(effectAmt, 0.0, 20.0, 0.0, 0.25);
	for (int i = -4; i < 4; i++) {
		for (int j = -3; j < 3; j++) {
			sum += texture(inputTex, inputCoord(st + vec2(float(j), float(i)) * 0.004)).rgb * strength;
		}
	}
	vec3 color;
	if (orig.r < 0.3) { color = sum * sum * 0.012 + orig; }
	else if (orig.r < 0.5) { color = sum * sum * 0.009 + orig; }
	else { color = sum * sum * 0.0075 + orig; }
	return clamp(color, vec3(0.0), vec3(1.0));
}

vec3 zoomBlur(vec2 st) {
	vec3 color = vec3(0.0);
	float total = 0.0;
	vec2 toCenter = st - 0.5;
	float offset = fxPrng(vec3(12.9898, 78.233, 151.7182)).x;
	// Pin the evaluation order of the tap chain: relaxed math reassociates
	// toCenter * percent * strength as toCenter * (percent * strength), which
	// shifts tap coordinates by 1 ulp and flips nearest-sampler taps. The
	// min/max clamps are value-exact for finite values and force both
	// backends to evaluate fl(fl(toCenter * percent) * strength). The
	// accumulation clamp keeps the add's operand from being a raw multiply
	// result, which relaxed math fuses into an fma and standard math
	// double-rounds.
	vec3 products[41];
	for (float t = 0.0; t <= 40.0; t += 1.0) {
		float percent = (t + offset) / 40.0;
		float percentSq = min(max(percent * percent, -1e38), 1e38);
		float weight = 4.0 * (percent - percentSq);
		float strength = mapRange(effectAmt, 0.0, 20.0, 0.0, 1.0);
		vec2 tapA = toCenter * percent;
		vec2 tap = min(max(tapA, vec2(-1e38)), vec2(1e38)) * strength;
		vec2 tapB = min(max(tap, vec2(-1e38)), vec2(1e38));
		// Under tiling, clamp each tap component to an absolute 256 px
		// budget (as filter/lens and filter/parallax do): the raw
		// displacement is a fraction of fullResolution, so an unclamped tap
		// would reach past the fixed 1024 px tile overlap on large prints.
		// Untiled the clamp is off and the output is byte-identical.
		if (tileOffset.x != 0.0 || tileOffset.y != 0.0) {
			vec2 tapBudget = vec2(256.0) * invFullResolution;
			tapB = min(max(tapB, -tapBudget), tapBudget);
		}
		vec4 tex = texture(inputTex, inputCoord(st + tapB));
		products[int(t)] = min(max(tex.rgb * weight, vec3(-1e38)), vec3(1e38));
		total += min(max(weight, -1e38), 1e38);
	}
	for (int i = 0; i < 41; i++) {
		color += products[i];
	}
	// Refine the reciprocal with one Newton-Raphson step: the raw division
	// lowers differently (Dawn: x * rcp(x), ANGLE: correctly-rounded divide),
	// and the ~1 ulp difference flips the final 8-bit rounding when the value
	// sits on an x.5 boundary. Multiply/subtract are correctly rounded in both
	// Metal math modes, so both backends converge to the same reciprocal. The
	// min/max clamp pins the inner multiply's order (relaxed math would fuse
	// it into the subtract as an fma; standard math double-rounds).
	float r = 1.0 / total;
	float tr = min(max(total * r, -1e38), 1e38);
	r = r * (2.0 - tr);
	return color * r;
}

vec2 rotate2D(vec2 st_in, float rot) {
	// min/max clamps pin the evaluation order at every multiply that feeds an
	// add or the caller's arithmetic: relaxed math contracts those pairs into
	// fma while standard math double-rounds, and the 1 ulp difference flips
	// sampler taps. The clamps are value-exact for finite values. The aspect
	// scalars are CPU-computed uniforms, so neither backend evaluates an
	// in-shader division here.
	vec2 st = st_in;
	st.x *= aspectRatio;
	st.x = min(max(st.x, -1e38), 1e38);
	float r = mapRange(rot, 0.0, 360.0, 0.0, 2.0);
	float angle = r * FX_PI;
	float ox = min(max(0.5 * aspectRatio, -1e38), 1e38);
	st -= vec2(ox, 0.5);
	float c = cos(angle);
	float s = sin(angle);
	// The reference GLSL's mat2(cos, -sin, sin, cos) * st (column-major).
	float px = min(max(c * st.x, -1e38), 1e38);
	float py = min(max(s * st.y, -1e38), 1e38);
	float qx = min(max(-s * st.x, -1e38), 1e38);
	float qy = min(max(c * st.y, -1e38), 1e38);
	st = vec2(px + py, qx + qy);
	st += vec2(ox, 0.5);
	st.x *= aspectInv;
	st = min(max(st, vec2(-1e38)), vec2(1e38));
	return st;
}

void main() {
	// The GLSL builds a full-image coordinate (gl_FragCoord.xy + tileOffset)
	// and scales it by the CPU-computed reciprocal of fullResolution instead
	// of dividing (see the invFullResolution note in the reference GLSL):
	// both backends then evaluate the same correctly-rounded multiply, so
	// the uv chain is bit-identical and every tile maps the same full-image
	// uv.
	vec2 globalCoord = gl_FragCoord.xy + tileOffset;
	vec2 uv = globalCoord * invFullResolution;

	// The division by a runtime uniform lowers differently (Dawn: x * rcp(y),
	// ANGLE: correctly-rounded divide) — a ~1 ulp difference rescales every uv
	// and flips knife-edge taps. One Newton-Raphson step pins the reciprocal
	// on both backends; the clamp keeps the scaleAmt*sR product from fusing
	// into the (2.0 - ...) subtract.
	float sR = 1.0 / scaleAmt;
	float sC = min(max(scaleAmt * sR, -1e38), 1e38);
	float scale = 100.0 * (sR * (2.0 - sC)); // 25 - 400 maps to 100 / 25 (4) to 100 / 400 (0.25)
	if (scale == 0.0) { scale = 1.0; }

	uv = rotate2D(uv, rotation);
	uv -= 0.5;
	uv *= scale;
	// Clamp before the add: relaxed math contracts the multiply into the
	// add as an fma while standard math double-rounds, and the 1 ulp
	// difference flips sampler taps at x.5 rounding boundaries.
	uv = min(max(uv, vec2(-1e38)), vec2(1e38));
	uv += 0.5;

	// The zoom center is anchored to the full image; the tile resolution
	// would shift it under tiling. Untiled the two are equal.
	vec2 imageSize = fullResolution;
	// imageSize is a copy of fullResolution, so a resolution/imageSize style
	// self-division would be a value divided by itself: ANGLE computes exactly
	// 1.0 while Dawn lowers the division to x * rcp(x) (~1 ulp off), which
	// shifted the offset map's arguments and flipped knife-edge sampler taps.
	// Use the exact 1.0.
	uv.x -= ceil((scale * 0.5) - (0.5 - (1.0 / imageSize.x * scale)));
	uv.y += ceil((scale * 0.5) + (0.5 - (1.0 / imageSize.y * scale)) - (scale));

	// Pin the offset-shift evaluation order with scalar clamps: the map
	// result feeds a multiply then a subtract, and relaxed math contracts
	// that pair into an fma while standard math double-rounds. The clamps
	// are value-exact for finite values.
	float shiftXv = min(max(mapRange(offsetX, -100.0, 100.0, -scale, scale) * 1.5, -1e38), 1e38);
	float shiftYv = min(max(mapRange(offsetY, -100.0, 100.0, -scale, scale) * 1.5, -1e38), 1e38);
	uv -= vec2(shiftXv, shiftYv);
	uv = fract(uv);

	// flip/mirror
	if (FLIP == 1) { uv = 1.0 - uv; }
	else if (FLIP == 2) { uv.x = 1.0 - uv.x; }
	else if (FLIP == 3) { uv.y = 1.0 - uv.y; }
	else if (FLIP == 11) { if (uv.x > 0.5) { uv.x = 1.0 - uv.x; } }
	else if (FLIP == 12) { if (uv.x < 0.5) { uv.x = 1.0 - uv.x; } }
	else if (FLIP == 13) { if (uv.y < 0.5) { uv.y = 1.0 - uv.y; } }
	else if (FLIP == 14) { if (uv.y > 0.5) { uv.y = 1.0 - uv.y; } }
	else if (FLIP == 15) { if (uv.x > 0.5) { uv.x = 1.0 - uv.x; } if (uv.y < 0.5) { uv.y = 1.0 - uv.y; } }
	else if (FLIP == 16) { if (uv.x > 0.5) { uv.x = 1.0 - uv.x; } if (uv.y > 0.5) { uv.y = 1.0 - uv.y; } }
	else if (FLIP == 17) { if (uv.x < 0.5) { uv.x = 1.0 - uv.x; } if (uv.y < 0.5) { uv.y = 1.0 - uv.y; } }
	else if (FLIP == 18) { if (uv.x < 0.5) { uv.x = 1.0 - uv.x; } if (uv.y > 0.5) { uv.y = 1.0 - uv.y; } }

	vec4 color = texture(inputTex, uv);

	if (effectAmt != 0.0 && EFFECT != 0) {
		if (EFFECT == 100) { color = vec4(pixellate(uv, effectAmt), color.a); }
		else if (EFFECT == 110) { color = vec4(posterizeFn(color.rgb, effectAmt), color.a); }
		else if (EFFECT == 200) { color = vec4(cga(color, uv, globalCoord), color.a); }
		else if (EFFECT == 210) { color = vec4(subpixel(uv, effectAmt), color.a); }
		else if (EFFECT == 220) { color = vec4(bloomFn(uv), color.a); }
		else if (EFFECT == 230) { color = vec4(zoomBlur(uv), color.a); }
		else { color = vec4(convolutionEffect(color.rgb, uv), color.a); }
	}

	vec3 c = brightnessContrast(color.rgb);
	c = saturateFn(c);

	frag = vec4(c, color.a);
}
