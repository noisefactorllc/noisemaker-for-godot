#version 450
// render/pointsBillboardRender — program "clearDefocus" (clear the defocus accumulation
// target to a flat value before the additive-mode deposit passes write into it). Ported
// from glsl/clearDefocus.glsl. Only runs for blendMode==0 (additive); skipped whenever
// aperture is 0 or viewMode is flat.
//
// Layout effect: vec4 data[1] (uniformLayouts.clearDefocus): clearValue=data[0].x.
layout(set = 0, binding = 0, std140) uniform Params { vec4 data[1]; };
#define clearValue data[0].x

layout(location = 0) out vec4 fragColor;

void main() {
	fragColor = vec4(clearValue);
}
