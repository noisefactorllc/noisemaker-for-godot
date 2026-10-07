search synth, filter, render
noise(seed: 1, scaleX: 50, scaleY: 50).loopBegin(alpha: 50).blur().loopEnd().write(o0)
render(o0)
