// check_definitions.mjs — DEFINITION-DRIFT gate. Asserts the committed effect JSONs under
// godot/addons/noisemaker/effects are exactly what tools/convert-definitions.mjs produces from
// the current reference checkout.
//
//   NM_REFERENCE_ROOT=/path/to/noisemaker node parity/check_definitions.mjs
//
// Why this exists: the other six gates cannot see this class of drift. check_registry compares the
// GDScript registry against the reference registration logic *fed the same JSONs* — identical
// inputs, so a stale input is identical on both sides and passes. lex/parse/validate/expand/graph
// likewise run off the committed JSONs. The result: the port silently fell behind the reference on
// 31 effects (new `artist` tags, reworded descriptions, remap's MAX_VERTS_PER_ZONE 16 -> 64, the
// renderCubemap3D -> renderCubemap3d rename, a missing filter3d/palette3d) with every gate green.
//
// Method: copy the committed tree to a temp dir, regenerate INTO that copy, diff. Regenerating into
// a copy (not an empty dir) is required — the generator carries port-authored `uniformLayouts`
// forward from the file it replaces, and those exist for the four particle effects whose packing
// layout the reference does not declare. Regenerating into an empty dir would drop them and this
// gate would report false drift.
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { execFileSync } from 'node:child_process'
import { tmpdir } from 'node:os'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO = resolve(HERE, '..')
const EFFECTS_DIR = join(REPO, 'godot', 'addons', 'noisemaker', 'effects')

if (!process.env.NM_REFERENCE_ROOT) { console.error('NM_REFERENCE_ROOT is not set'); process.exit(3) }

const tmp = mkdtempSync(join(tmpdir(), 'nm-godot-defs-'))
try {
  cpSync(EFFECTS_DIR, tmp, { recursive: true })
  execFileSync('node', [join(REPO, 'tools', 'convert-definitions.mjs')],
    { env: { ...process.env, NM_OUT_DIR: tmp }, stdio: ['ignore', 'ignore', 'pipe'], encoding: 'utf8' })

  const walk = (d, base, out = []) => {
    for (const e of readdirSync(d)) {
      const p = join(d, e)
      if (statSync(p).isDirectory()) walk(p, base, out)
      else if (e.endsWith('.json')) out.push(relative(base, p))
    }
    return out
  }
  const committed = new Set(walk(EFFECTS_DIR, EFFECTS_DIR))
  const generated = new Set(walk(tmp, tmp))

  const drift = []
  for (const rel of [...new Set([...committed, ...generated])].sort()) {
    // NOTE: a case-only rename (renderCubemap3D -> renderCubemap3d) is invisible on a
    // case-insensitive filesystem; compare names case-sensitively so it still surfaces.
    if (!committed.has(rel)) { drift.push(`MISSING from repo (reference has it): ${rel}`); continue }
    if (!generated.has(rel)) { drift.push(`STALE in repo (reference dropped/renamed it): ${rel}`); continue }
    const a = readFileSync(join(EFFECTS_DIR, rel), 'utf8')
    const b = readFileSync(join(tmp, rel), 'utf8')
    if (a !== b) drift.push(`DRIFTED: ${rel}`)
  }

  console.log('DEFINITION PARITY:')
  if (drift.length === 0) {
    console.log(`  PASS  ${committed.size} definition(s) match the reference exactly`)
    process.exit(0)
  }
  console.log(`  FAIL  ${drift.length} of ${Math.max(committed.size, generated.size)} definition(s) drifted from the reference`)
  for (const d of drift) console.log(`        ${d}`)
  console.log('\n  Fix: NM_REFERENCE_ROOT=... node tools/convert-definitions.mjs')
  console.log('  (a case-only rename needs `git mv` first — macOS will not rename it for you)')
  process.exit(1)
} finally {
  if (existsSync(tmp)) rmSync(tmp, { recursive: true, force: true })
}
