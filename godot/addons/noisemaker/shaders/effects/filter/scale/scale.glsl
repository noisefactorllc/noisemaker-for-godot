#version 450
// filter/scale program scale — ported from glsl/scale.glsl. No-layout effect: params and engine globals are injected as #defines;
// bool params arrive as floats, int params via int().
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

void main(){
  // Compute global UV from tile-local coordinates
  vec2 globalCoord = gl_FragCoord.xy + tileOffset;
  vec2 st = globalCoord / fullResolution;
  
  // Apply scale transform in global UV space (centered and aspect-corrected)
  vec2 c = vec2(centerX, centerY);
  st -= c;
  st.x *= aspectRatio;
  st = st / vec2(scaleX, scaleY);
  st.x /= aspectRatio;
  st += c;
  
  // Convert global UV to local UV for sampling inputTex
  vec2 localUV = (st * fullResolution - tileOffset) / resolution;
  
  // Apply wrap mode to local UV
  if (int(wrap) == 0) {
      // mirror
      localUV = abs(mod(localUV + 1.0, 2.0) - 1.0);
  } else if (int(wrap) == 1) {
      // repeat
      localUV = fract(localUV);
  } else {
      // clamp
      localUV = clamp(localUV, 0.0, 1.0);
  }
  
  fragColor = vec4(texture(inputTex, localUV).rgb, 1.0);
}