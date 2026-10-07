search synth, filter

perlin(scale: 75, octaves: 2)
  .pixelSort(angled: -180, darkest: true)
  .write(o0)

render(o0)
