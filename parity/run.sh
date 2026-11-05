#!/usr/bin/env bash
# parity/run.sh <name> [tolerance] [ssim_min] [size]
#
# Render the Godot candidate for a Tier-1 program and compare it against the
# existing golden. Goldens + graph JSON are produced by the reference harness
# (parity/export-and-render.mjs) into parity/out/ — see parity/README.md.
#
# RenderingDevice is null under --headless, so the Godot runner is launched
# NON-headless with the window positioned offscreen (--position 5000,5000).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Bounds for engine steps: a host without a window session can stall the
# launch forever, burning the engine command's whole deadline. Prefer the
# host's timeout command (macOS ships gtimeout from coreutils, not
# timeout); fall back to node's own spawn timeout, which every gate host
# has because the gate runs node itself. A stall exits 124 as a named
# failure instead of burning the engine command's deadline silently.
bound_ms () { # $1 = milliseconds; rest = command
  # The bound itself must not hang: a child that ignores TERM (a stalled
  # engine launch) survives plain timeout, so the bound burns the engine
  # command's deadline anyway (red probe: timeout 2 'trap "" TERM; sleep 12'
  # exits after 12s, not 2s). Escalate to SIGKILL 10s after the bound on
  # every branch so the stall always ends as a named exit.
  if command -v timeout >/dev/null 2>&1; then timeout -k 10 "$(( $1 / 1000 ))" "${@:2}"; rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout -k 10 "$(( $1 / 1000 ))" "${@:2}"; rc=$?
  else BOUND_MS="$1" node -e 'const{spawnSync}=require("child_process");const r=spawnSync(process.argv[1],process.argv.slice(2),{stdio:"inherit",timeout:Number(process.env.BOUND_MS),killSignal:"SIGKILL"});process.exit(r.status===null?124:r.status)' bound_ms "${@:2}"; rc=$?
  fi
  # The escalation kill makes timeout(1) exit 137 (128+SIGKILL), not 124;
  # the bound's named-failure contract is 124, so map the kill back.
  if [ "$rc" -eq 137 ]; then rc=124; fi
  return "$rc"
}
NAME="${1:?usage: run.sh <name> [tol] [ssim_min] [size]}"
# Default 2.001 (not 2): compare.py computes max-abs-diff as float ((x-y)/255*255),
# so a TRUE 8-bit diff of 2 reports ~2.0000035 and would false-fail a strict "<=2".
# 2.001 accepts true diffs <=2 and still rejects >=3.
TOL="${2:-2.001}"
SSIM="${3:-0.98}"
SIZE="${4:-256}"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PY="$ROOT/parity/.venv/bin/python"
# A Windows venv keeps its interpreter under Scripts/.
[ -x "$PY" ] || [ ! -x "$ROOT/parity/.venv/Scripts/python.exe" ] || PY="$ROOT/parity/.venv/Scripts/python.exe"
GRAPH="$ROOT/parity/out/$NAME.graph.json"
GOLD="$ROOT/parity/out/$NAME.golden.png"
CAND="$ROOT/parity/out/$NAME.candidate.png"
REPORT="$ROOT/parity/out/$NAME.report.json"

# Delete the stale candidate and report before any early exit (a missing graph
# or golden below) so a later classification cannot read an earlier run's
# artifacts. With SKIP_RENDER=1 the existing candidate is intentionally reused.
if [ "${SKIP_RENDER:-0}" != "1" ]; then
	rm -f "$CAND" "$REPORT"
fi

[ -f "$GRAPH" ] || { echo "missing graph: $GRAPH (run: node tools/export-graph.mjs --file parity/programs/$NAME.dsl $GRAPH)"; exit 2; }
[ -f "$GOLD" ]  || { echo "missing golden: $GOLD (run the reference harness)"; exit 2; }

if [ "${SKIP_RENDER:-0}" != "1" ]; then
	render_args=(--graph "$GRAPH" --out "$CAND" --size "$SIZE")
	[ "$NAME" != "media" ] || render_args+=(--media-fixture)
	set +e
	# The render opens a real window (RenderingDevice is null under
	# --headless). A host without a window session can stall the engine
	# launch forever. Bound it (see bound_ms above) so a stall fails named
	# instead of burning the engine command's whole deadline.
	render_log=$(bound_ms 240000 "$GODOT" --path "$ROOT/godot" --script res://addons/noisemaker/tools/render_graph.gd \
		--position 5000,5000 -- "${render_args[@]}" 2>&1)
	render_rc=$?
	set -e
	if [ "$render_rc" -eq 124 ] || [ "$render_rc" -eq 137 ]; then
		echo "DIAG: the Godot render for $NAME did not finish within its bound (rc $render_rc); a windowed engine launch on a headless host is the likely stall"
	fi
	# "ERROR" (Godot ERR_FAIL_* engine messages) must be surfaced: a failed
	# render_pipeline_create prints its exact validation reason as an ERROR
	# line, which the previous lowercase-only filter dropped from tails.
	printf '%s\n' "$render_log" | grep -E "NM_RENDERED|NM_SHADER_DIAG|NM_PASS_STATS|RD_NULL|SCRIPT ERROR|ERROR:|shader |missing|error" || true
	[ "$render_rc" -eq 0 ] || { echo "FAIL: Godot renderer exited $render_rc for $NAME"; exit 1; }
fi
[ -f "$CAND" ] || { echo "FAIL: Godot renderer produced no candidate for $NAME"; exit 1; }

"$PY" "$ROOT/parity/compare.py" "$GOLD" "$CAND" \
	--name "$NAME" --tolerance "$TOL" --ssim-min "$SSIM" \
	--report "$ROOT/parity/out/$NAME.report.json" || {
	{
	# Threshold failure: surface the full metrics report and artifact identity so a
	# native-runner failure is diagnosable from its output tail alone (the report
	# JSON lives only on the runner host otherwise).
	echo "DIAG report $NAME:"
	cat "$ROOT/parity/out/$NAME.report.json" || true
	echo "DIAG artifacts $NAME:"
	ls -l "$GOLD" "$CAND" 2>/dev/null || true
	(sha256sum "$GOLD" "$CAND" 2>/dev/null || shasum -a 256 "$GOLD" "$CAND" 2>/dev/null || true)
	grep -o '"\(error\|max_abs_diff\|mean_abs_diff\|ssim\|tolerance\|ssim_min\|golden_shape\|candidate_shape\)":[^,}]*' "$ROOT/parity/out/$NAME.report.json" 2>/dev/null | tr '\n' ' ' | sed 's/^/DIAG metrics: /'; echo
	# Identify WHICH artifact is degenerate (black/garbage) without the PNGs:
	# per-image mean, stddev and nonzero-alpha fraction.
	"$PY" - "$GOLD" "$CAND" <<-'PYEOF' || true
	import sys
import numpy as np
from PIL import Image
for tag, p in (("golden", sys.argv[1]), ("candidate", sys.argv[2])):
    try:
        a = np.asarray(Image.open(p).convert("RGBA"), dtype=np.float64)
        print(f"DIAG image {tag}: shape={a.shape} mean={a.mean():.2f} std={a.std():.2f} "
              f"nonzero_alpha_frac={(a[..., 3] > 0).mean():.4f} "
              f"rgb_mean={a[..., :3].mean():.2f}")
    except Exception as e:
        print(f"DIAG image {tag}: unreadable: {e}")
PYEOF
	} >&2
	exit 1
}
