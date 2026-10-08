#version 450
// classicNoisedeck/cellNoise program cellNoise — ported from glsl/cellNoise.glsl. Declared-layout effect: the shader names each layout slot with a #define;
// bool params arrive as floats, int params via int().
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[9]; };
#define resolution data[0].xy
#define time data[0].z
#define seed data[0].w
#define shape data[1].x
#define scale data[1].y
#define cellScale data[1].z
#define cellSmooth data[1].w
#define variation data[2].x
#define speed data[2].y
#define paletteMode data[2].z
#define colorMode data[2].w
#define paletteOffset data[3].xyz
#define cyclePalette data[3].w
#define paletteAmp data[4].xyz
#define rotatePalette data[4].w
#define paletteFreq data[5].xyz
#define repeatPalette data[5].w
#define palettePhase data[6].xyz
#define texInfluence data[7].x
#define texIntensity data[7].y
#define tileOffset data[8].xy
#define fullResolution data[8].zw
layout(set = 0, binding = 1) uniform sampler2D tex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/*
 * Cell noise shader.
 * Generates Worley-style distance fields for use as displacement or masks.
 * Distance metrics and jitter are normalized so tiling remains seamless across seeds.
 */
#define PI 3.14159265359
#define TAU 6.28318530718
#define ar fullResolution.x / fullResolution.y

float map(float value, float inMin, float inMax, float outMin, float outMax) {
    return outMin + (outMax - outMin) * (value - inMin) / (inMax - inMin);
}

// PCG PRNG - MIT License
// https://github.com/riccardoscalco/glsl-pcg-prng
uvec3 pcg(uvec3 v) {
	v = v * uint(1664525) + uint(1013904223);

	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;

	v ^= v >> uint(16);

	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;

	return v;
}

vec3 prng (vec3 p) {
    p.x = p.x >= 0.0 ? p.x * 2.0 : -p.x * 2.0 + 1.0;
    p.y = p.y >= 0.0 ? p.y * 2.0 : -p.y * 2.0 + 1.0;
    p.z = p.z >= 0.0 ? p.z * 2.0 : -p.z * 2.0 + 1.0;
    return vec3(pcg(uvec3(p))) / float(uint(0xffffffff));
}
// end PCG PRNG

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
    float r = rgb.r;
    float g = rgb.g;
    float b = rgb.b;
    
    float max = max(r, max(g, b));
    float min = min(r, min(g, b));
    float delta = max - min;

    float h = 0.0;
    if (delta != 0.0) {
        if (max == r) {
            h = mod((g - b) / delta, 6.0) / 6.0;
        } else if (max == g) {
            h = ((b - r) / delta + 2.0) / 6.0;
        } else if (max == b) {
            h = ((r - g) / delta + 4.0) / 6.0;
        }
    }
    
    float s = (max == 0.0) ? 0.0 : delta / max;
    float v = max;

    return vec3(h, s, v);
}

vec3 linearToSrgb(vec3 linear) {
    vec3 srgb;
    for (int i = 0; i < 3; ++i) {
        if (linear[i] <= 0.0031308) {
            srgb[i] = linear[i] * 12.92;
        } else {
            srgb[i] = 1.055 * pow(linear[i], 1.0 / 2.4) - 0.055;
        }
    }
    return srgb;
}

// oklab transform and inverse - Public Domain/MIT License
// https://bottosson.github.io/posts/oklab/

const mat3 fwdA = mat3(1.0, 1.0, 1.0,
                       0.3963377774, -0.1055613458, -0.0894841775,
                       0.2158037573, -0.0638541728, -1.2914855480);

const mat3 fwdB = mat3(4.0767245293, -1.2681437731, -0.0041119885,
                       -3.3072168827, 2.6093323231, -0.7034763098,
                       0.2307590544, -0.3411344290,  1.7068625689);

const mat3 invB = mat3(0.4121656120, 0.2118591070, 0.0883097947,
                       0.5362752080, 0.6807189584, 0.2818474174,
                       0.0514575653, 0.1074065790, 0.6302613616);

const mat3 invA = mat3(0.2104542553, 1.9779984951, 0.0259040371,
                       0.7936177850, -2.4285922050, 0.7827717662,
                       -0.0040720468, 0.4505937099, -0.8086757660);

vec3 oklab_from_linear_srgb(vec3 c) {
    vec3 lms = invB * c;

    return invA * (sign(lms)*pow(abs(lms), vec3(0.3333333333333)));
}

vec3 linear_srgb_from_oklab(vec3 c) {
    vec3 lms = fwdA * c;

    return fwdB * (lms * lms * lms);
}
// end oklab

vec3 pal(float t) {
    vec3 a = paletteOffset;
    vec3 b = paletteAmp;
    vec3 c = paletteFreq;
    vec3 d = palettePhase;

    t = t * repeatPalette + rotatePalette * 0.01;

    vec3 color = a + b * cos(6.28318 * (c * t + d));

    // convert to rgb if palette is in hsv or oklab mode
    // 1 = hsv, 2 = oklab, 3 = rgb
    if (int(paletteMode) == 1) {
        color = hsv2rgb(color);
    } else if (int(paletteMode) == 2) {
        color.g = color.g * -.509 + .276;
        color.b = color.b * -.509 + .198;
        color = linear_srgb_from_oklab(color);
        color = linearToSrgb(color);
    } 

    return color;
}

float luminance(vec3 color) {
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
}

vec2 rotate2D(vec2 st, float rot) {
    rot = map(rot, 0.0, 360.0, 0.0, 2.0);
    float angle = rot * PI;
    st -= vec2(0.5 * ar, 0.5);
    st = mat2(cos(angle), -sin(angle), sin(angle), cos(angle)) * st;
    st += vec2(0.5 * ar, 0.5);
    return st;
}

float polarShape(vec2 st, int sides) {
    float a = atan(st.x, st.y) + PI;
    float r = TAU / float(sides);
    return cos(floor(0.5 + a / r) * r - a) * length(st);
}

float shapeDistance(vec2 st, vec2 offset, int type, float scale_) {
	st += offset;

	float d = 1.0;
	if (type == 0) {
        // circle
		d = length(st * 1.2);
	} else if (type == 2) {
        // hexagon
		d = polarShape(st * 1.2, 6);
	} else if (type == 3) {
        // octagon
		d = polarShape(st * 1.2, 8);
    } else if (type == 4) {
        // square
        d = polarShape(st * 1.5, 4);
	} else if (type == 6) {
        // triangle
        st.y += 0.05;
		d = polarShape(st * 1.5, 3);
    }

	return d * scale_;
}

vec2 wrapEdges(vec2 st, float freq) {
    if (st.x < 0.0) st.x = freq - 1.0;
    if (st.x > freq * ar) st.x = 0.0;
    if (st.y < 0.0) st.y = freq - 1.0;
    if (st.y > freq) st.y = 0.0;
    return st;
}

// smoothmin from https://iquilezles.org/articles/smin/ - MIT License
float smin(float a, float b, float k) {
    if (k == 0.0) { return min(a, b); }
    float h = max( k-abs(a-b), 0.0 )/k;
    return min( a, b ) - h*h*k*(1.0/4.0);
}

float cells(vec2 st, float freq, float cellSize, int sides) {
    st -= vec2(0.5 * ar, 0.5);
	st *= freq;
    st += vec2(0.5 * ar, 0.5);
	st += prng(vec3(float(int(seed)))).xy;

	vec2 i = floor(st);
	vec2 f = fract(st);

	float d = 1.0;

	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 n = vec2(float(x), float(y));
			vec2 wrap = i + n;
            //wrap = wrapEdges(wrap, freq);
			vec2 point = prng(vec3(wrap, float(int(seed)))).xy;

            vec3 r1 = prng(vec3(float(int(seed)), wrap)) * 0.5 - 0.25; 
			vec3 r2 = prng(vec3(wrap, float(int(seed)))) * 2.0 - 1.0;
            float spd = floor(speed);
            point += vec2(sin(time * TAU * spd + r2.x) * r1.x, cos(time * TAU * spd + r2.y) * r1.y);

            vec2 diff = n + point - f;
			float dist = shapeDistance(vec2(diff.x, -diff.y), vec2(0.0), sides, cellSize);
            if (int(shape) == 1) {
                dist = abs(n.x + point.x - f.x) + abs(n.y + point.y - f.y);
                dist *= cellSize;
            }

            dist += r1.z * (variation * 0.01); // size variation
            d = smin(d, dist, cellSmooth * 0.01);
			//d = min(d, dist);
		}
	}
	return d;
}

void main() {
    vec2 globalCoord = gl_FragCoord.xy + tileOffset;
    vec4 color = vec4(0.0, 0.0, 1.0, 1.0);
    vec2 st = globalCoord / fullResolution.y;

    float freq = map(scale, 1.0, 100.0, 20.0, 1.0);
    float cellSize = map(cellScale, 1.0, 100.0, 3.0, 0.75);

    float texLuminosity = 0.0;
    float texFactor = texIntensity * 0.01;
    vec2 texCoord = globalCoord / fullResolution;

    if (int(texInfluence) > 0) {
        vec3 texRGB = texture(tex, gl_FragCoord.xy / vec2(textureSize(tex, 0))).rgb;

        texLuminosity = luminance(texRGB);

        if (int(texInfluence) == 1) {
            cellSize -= texLuminosity * texFactor;
        } else if (int(texInfluence) == 2) {
            freq -= texLuminosity * (texFactor * 5.0);
        }
    }

    float d = cells(st, freq, cellSize, int(shape));

    if (int(texInfluence) >= 10) {
        if (int(texInfluence) == 10) {
            d += texLuminosity * texFactor;
        } else if (int(texInfluence) == 11) {
            d = mix(d, d / max(0.1, texLuminosity), texFactor);
        } else if (int(texInfluence) == 12) {
            d = mix(d, min(d, texLuminosity), texFactor);
        } else if (int(texInfluence) == 13) {
            d = mix(d, max(d, texLuminosity), texFactor);
        } else if (int(texInfluence) == 14) {
            d = mix(d, mod(d, max(0.1, texLuminosity)), texFactor);
        } else if (int(texInfluence) == 15) {
            d = mix(d, d * texLuminosity, texFactor);
        } else if (int(texInfluence) == 16) {
            d -= texLuminosity * texFactor;
        }
    }

    if (int(colorMode) == 0) {
        color.rgb = vec3(d);
    } else if (int(colorMode) == 1) {
        color.rgb = vec3(1.0 - d);
    } else if (int(colorMode) == 2) {
        if (int(cyclePalette) == -1) {
            d += time;
        } else if (int(cyclePalette) == 1) {
            d -= time;
        }
        color.rgb = pal(d);
    }

    st = globalCoord / fullResolution;

    fragColor = color;
}
