#version 450
// filter/threshold program thresh — ported from glsl/thresh.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/* Binary threshold with adjustable edge softness. */
void main(){
  vec2 globalCoord = gl_FragCoord.xy + tileOffset;
  vec2 st = gl_FragCoord.xy / vec2(textureSize(inputTex,0));
  vec4 c = texture(inputTex, st);
  float l = dot(c.rgb, vec3(0.299,0.587,0.114));
  float e = smoothstep(level - sharpness, level + sharpness, l);
  fragColor = vec4(vec3(e),1.0);
}
