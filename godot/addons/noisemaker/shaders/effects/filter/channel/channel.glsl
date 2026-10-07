#version 450
// filter/channel program channel — ported from glsl/channel.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/* Extracts a single channel (r=0, g=1, b=2, a=3) as grayscale. */
void main(){
  vec2 globalCoord = gl_FragCoord.xy + tileOffset;
  vec2 st = (gl_FragCoord.xy - 0.5) / vec2(textureSize(inputTex, 0));
  vec4 c = texture(inputTex, st);
  
  float v;
  if (int(channel) == 0) {
    v = c.r;
  } else if (int(channel) == 1) {
    v = c.g;
  } else if (int(channel) == 2) {
    v = c.b;
  } else {
    v = c.a;
  }
  
  v = fract(v * scale + offset);
  fragColor = vec4(vec3(v), 1.0);
}
