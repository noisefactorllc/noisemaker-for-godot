#version 450
// synth/solid program solid — ported from glsl/solid.glsl. No-layout effect: params
// and engine globals are injected as #defines; bool params arrive as floats, int params via int().
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/* Produces a constant color with premultiplied alpha. */
void main() {
  // Premultiply RGB by alpha for correct compositing
  fragColor = vec4(color * alpha, alpha);
}
