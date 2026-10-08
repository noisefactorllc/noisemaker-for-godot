#version 450
// filter/repeat program repeat — ported from glsl/repeat.glsl. No-layout effect: params and engine globals are injected as #defines;
// bool params arrive as floats, int params via int().
float nm_param_y() { return y; }
#undef y
float nm_param_x() { return x; }
#undef x
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

void main(){
  // Compute global coordinate
  vec2 globalCoord = gl_FragCoord.xy + tileOffset;
  
  // Compute global UV
  vec2 globalUV = globalCoord / fullResolution;
  
  // Apply repeat transformation in global space
  vec2 st = globalUV;
  st.x *= aspectRatio;
  st = st * vec2(nm_param_x(), nm_param_y()) + vec2(offsetX * aspectRatio, offsetY);
  st.x /= aspectRatio;
  
  // Apply wrap mode
  if (int(wrap) == 0) {
      // mirror
      st = abs(mod(st + 1.0, 2.0) - 1.0);
  } else if (int(wrap) == 1) {
      // repeat
      st = fract(st);
  } else {
      // clamp
      st = clamp(st, 0.0, 1.0);
  }
  
  // Convert warped global UV to local UV for sampling
  vec2 localUV = (st * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
  
  // For seamless tiling across tile boundaries, apply wrap to local UV
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