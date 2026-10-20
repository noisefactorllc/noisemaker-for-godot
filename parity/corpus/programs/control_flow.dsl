search synth, filter

// Control flow parses and compiles; the runtime does not execute it.
if (true) {
    // A comment inside a block attaches to the next statement.
    let inner = 60
    noise(seed: 1, scaleX: inner).write(o0)
} elif (false) {
    noise().write(o0)
} else {
    // A comment before the closing brace stays on the block.
}
noise(seed: 2, scaleX: 50).write(o1)
return
render(o1)
