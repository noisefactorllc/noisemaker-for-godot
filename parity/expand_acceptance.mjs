// expand_acceptance.mjs — the single definition of the accepted expansion
// difference class between the Godot candidate expander and the reference
// expander.
//
// Observed and accepted difference: the candidate copies each pass
// definition's `defines` onto the expanded pass object, while the reference
// keeps pass-level defines implicit in the program name. Both expanders
// select the identical program: the name carries the `__<KEY>_<value>`
// suffix built from those same define entries (reference expander.js appends
// `programDefineSuffix`/pass-define suffix; the candidate emits the same
// suffixed name and additionally records the pass defines for its runtime).
// A pass-defines-only mismatch is therefore accepted exactly when:
//   1. the candidate pass has `defines` and the reference pass has none,
//   2. both passes reference the byte-identical program name,
//   3. every `<KEY>: <value>` entry is encoded in that shared name as a
//      segment-boundary `__<KEY>_<value>` token (followed by the end of the
//      name or another `__`), so prefix collisions like VIEW_MODE:1 against
//      a `__VIEW_MODE_10` program are rejected,
//   4. after removing those candidate pass defines, both graphs compare
//      equal under the gate's deep comparator.
// Any other difference is rejected. parity/check_expand.mjs consumes this
// module; parity/test_expand_acceptance.py pins the rule with unit fixtures
// and source guards so the accepted class cannot silently widen.

export function numEq(a, b) {
    if (a === b) return true
    return Math.abs(a - b) <= 1e-12 * Math.max(1, Math.abs(a), Math.abs(b))
}

export function deepEq(a, b) {
    if (a === b) return true
    if (typeof a === 'number' && typeof b === 'number') return numEq(a, b)
    if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return a === b
    if (Array.isArray(a) !== Array.isArray(b)) return false
    if (Array.isArray(a)) {
        if (a.length !== b.length) return false
        for (let i = 0; i < a.length; i++) if (!deepEq(a[i], b[i])) return false
        return true
    }
    const ka = Object.keys(a), kb = Object.keys(b)
    if (ka.length !== kb.length) return false
    for (const k of ka) { if (!(k in b) || !deepEq(a[k], b[k])) return false }
    return true
}

export function firstDiff(a, b, path) {
    if (deepEq(a, b)) return null
    const ta = a === null ? 'null' : Array.isArray(a) ? 'array' : typeof a
    const tb = b === null ? 'null' : Array.isArray(b) ? 'array' : typeof b
    if (ta !== tb || (ta !== 'object' && ta !== 'array')) return `${path}: ref=${JSON.stringify(a)} mine=${JSON.stringify(b)}`
    if (Array.isArray(a)) {
        if (a.length !== b.length) return `${path}: length ref=${a.length} mine=${b.length}`
        for (let i = 0; i < a.length; i++) { const d = firstDiff(a[i], b[i], `${path}[${i}]`); if (d) return d }
        return `${path}: (array differs)`
    }
    const keys = new Set([...Object.keys(a), ...Object.keys(b)])
    for (const k of keys) {
        if (!(k in a)) return `${path}.${k}: missing in ref (mine=${JSON.stringify(b[k])})`
        if (!(k in b)) return `${path}.${k}: missing in mine (ref=${JSON.stringify(a[k])})`
        const d = firstDiff(a[k], b[k], `${path}.${k}`); if (d) return d
    }
    return `${path}: (object differs)`
}

function programEncodesDefine(program, defines) {
    if (typeof program !== 'string' || defines === null || typeof defines !== 'object') return false
    for (const [k, v] of Object.entries(defines)) {
        const token = `__${k}_${v}`
        let at = program.indexOf(token)
        // Segment-boundary match: the token must be followed by the end of
        // the name or the start of the next __segment, so VIEW_MODE:1 cannot
        // ride on a __VIEW_MODE_10 suffix.
        let found = false
        while (at !== -1) {
            const end = at + token.length
            if (end === program.length || program.startsWith('__', end)) { found = true; break }
            at = program.indexOf(token, at + 1)
        }
        if (!found) return false
    }
    return true
}

// Classify a candidate/reference expansion diff. Returns
// { accepted, normalized, entries, reason } where `normalized` is the
// candidate graph with the accepted pass defines removed, `entries` lists
// every accepted pass-defines difference, and `reason` names the first
// unaccepted difference when accepted is false.
export function classifyPassDefinesDiff(refOut, candOut) {
    const entries = []
    const refPasses = refOut && Array.isArray(refOut.passes) ? refOut.passes : null
    const candPasses = candOut && Array.isArray(candOut.passes) ? candOut.passes : null
    if (refPasses && candPasses && refPasses.length === candPasses.length) {
        for (let i = 0; i < candPasses.length; i++) {
            const rp = refPasses[i], cp = candPasses[i]
            if (cp && cp.defines !== undefined && cp.defines !== null && rp && rp.defines === undefined) {
                if (cp.program !== rp.program) {
                    return { accepted: false, normalized: null, entries, reason: `passes[${i}]: program names differ (ref=${JSON.stringify(rp.program)} mine=${JSON.stringify(cp.program)})` }
                }
                if (!programEncodesDefine(cp.program, cp.defines)) {
                    return { accepted: false, normalized: null, entries, reason: `passes[${i}]: pass defines not encoded in program name ${JSON.stringify(cp.program)}` }
                }
                entries.push({ index: i, name: cp.name ?? null, program: cp.program, defines: cp.defines })
            }
        }
    }
    let normalized = candOut
    if (entries.length > 0) {
        normalized = JSON.parse(JSON.stringify(candOut))
        for (const e of entries) delete normalized.passes[e.index].defines
    }
    const reason = firstDiff(refOut, normalized, 'out')
    if (reason) return { accepted: false, normalized, entries, reason }
    return { accepted: true, normalized, entries, reason: null }
}