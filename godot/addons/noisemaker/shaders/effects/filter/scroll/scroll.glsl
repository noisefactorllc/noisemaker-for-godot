#version 450
// filter/scroll program scroll — ported from glsl/scroll.glsl. No-layout effect: params and engine globals are injected as #defines;
// bool params arrive as floats, int params via int().
float nm_param_x() { return x; }
#undef x
float nm_param_y() { return y; }
#undef y
layout(set = 0, binding = 1) uniform sampler2D inputTex;
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 fragColor;

/* Scrolls texture coordinates with wraparound. */
void main(){
  vec2 globalCoord = gl_FragCoord.xy + tileOffset;
  vec2 globalUV = globalCoord / fullResolution;
  
  globalUV.x *= aspectRatio;
  vec2 offset = vec2(-nm_param_x() + time * -speedX, nm_param_y() + time * speedY);
  offset.x *= aspectRatio;
  globalUV += offset;
  globalUV.x /= aspectRatio;
  
  // Convert to local UV for sampling
  vec2 localUV = (globalUV * fullResolution - tileOffset) / vec2(textureSize(inputTex, 0));
  
  // Apply wrap mode in local UV space to constrain to tile bounds
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