search synth, filter

// A chain sees only the lets written before it.
let early = 80
let late = 30
noise(seed: 1, scaleX: early, scaleY: late).write(o0)

// A read of a name that no earlier let assigns gets S003 at the
// identifier, and the argument falls back to the parameter default.
noise(seed: 2, scaleX: late, scaleY: missing).write(o1)

// The latest assignment of a name wins for the chains after it.
let late = 90
let missing = 42
noise(seed: 3, scaleX: late, scaleY: missing).write(o2)

render(o0)
