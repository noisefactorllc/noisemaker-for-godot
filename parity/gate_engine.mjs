// Bounded engine launch for the compiler parity gates.
//
// The gates launched Godot with execFileSync and no timeout. A stalled engine
// launch then ran past the harness's engine deadline as a bare command_timeout
// with no trace: execFileSync captures stdout, so a hung child prints nothing.
// Bound the launch the way parity/run.sh bounds its render: at the gate clock's
// remaining time when the gate runs under scripts/parity-summary, else at a
// fixed default. A stall exits 124 with a named diagnostic and the captured
// tails, in time for the mint, never as a bare command_timeout.
import { spawnSync } from 'node:child_process'

const DEFAULT_BOUND_MS = 170000
const EXIT_MARGIN_MS = 10000

function tail(s, n = 2000) {
    s = String(s || '')
    return s.length > n ? s.slice(-n) : s
}

export function runEngine(bin, args, opts = {}) {
    let bound = DEFAULT_BOUND_MS
    const deadline = Number(process.env.NM_GATE_DEADLINE_MS || 0)
    const start = Number(process.env.NM_GATE_START_MS || 0)
    if (deadline > 0 && start > 0) {
        const remaining = deadline - (Date.now() - start) - EXIT_MARGIN_MS
        if (remaining < bound) bound = remaining
        if (bound < 5000) {
            console.error(`DIAG: the gate's engine deadline has too little time left for: ${bin} ${args.join(' ')}`)
            process.exit(124)
        }
    }
    const r = spawnSync(bin, args, { ...opts, timeout: bound, killSignal: 'SIGKILL' })
    const stalled = r.status === null && (r.signal === 'SIGKILL' || (r.error && r.error.code === 'ETIMEDOUT'))
    if (stalled) {
        console.error(`DIAG: the engine launch did not finish within its ${Math.round(bound / 1000)}s bound (stalled engine launch): ${bin} ${args.join(' ')}`)
        if (r.stdout) console.error('stdout tail:\n' + tail(r.stdout))
        if (r.stderr) console.error('stderr tail:\n' + tail(r.stderr))
        process.exit(124)
    }
    if (r.error) {
        throw new Error(`engine command failed: ${bin} ${args.join(' ')}\n${r.error.message}`)
    }
    if (r.status !== 0) {
        throw new Error(`engine command exited ${r.status}: ${bin} ${args.join(' ')}\nstdout tail:\n${tail(r.stdout)}\nstderr tail:\n${tail(r.stderr)}`)
    }
    return r.stdout
}
