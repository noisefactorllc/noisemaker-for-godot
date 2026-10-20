search synth

// vec2(x, y) fills a vec2 parameter, and vec4(x, y, z, w) fills a vec4
// parameter (registered as color). Wrong component counts fall back.
remap(zone0_bounds: vec4(0, 0, 1, 1), zone0_v0: vec4(1, 0.5, 0, 1)).write(o0)
media(imageSize: vec2(512, 384)).write(o1)
render(o0)
