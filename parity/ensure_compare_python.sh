#!/usr/bin/env bash
# Source me: ensure_compare_python.sh <repo-root> — sets PY in the caller.
#
# The comparator (parity/compare.py) needs numpy and pillow. parity/README.md
# asks a human to create parity/.venv with both installed; a fresh runner
# checkout has no human, so every compare would die with exit 127 (observed
# from a fresh archive extract). Resolve the interpreter here and provision
# the documented environment when it is missing. Every install is bounded so
# a stalled or slow registry ends named inside the gate's budget instead of
# burning the engine command's whole deadline silently, and every step falls
# through inside an `if` so the caller's `set -e` cannot abort mid-provision.
# Provisioning output is kept in parity/out/venv-provision.log: a failure
# must name its cause, not just its exit code.
set -u
_compare_root="$1"
PY="$_compare_root/parity/.venv/bin/python"
[ -x "$PY" ] || [ ! -x "$_compare_root/parity/.venv/Scripts/python.exe" ] || PY="$_compare_root/parity/.venv/Scripts/python.exe"
if [ -x "$PY" ]; then
  return 0 2>/dev/null || exit 0
fi
# A system interpreter that already imports the comparator's needs needs no
# network and no venv; prefer it.
if command -v python3 >/dev/null 2>&1 \
   && python3 -c 'import numpy, PIL' >/dev/null 2>&1; then
  PY="$(command -v python3)"
  return 0 2>/dev/null || exit 0
fi
bound () { # $1 = milliseconds; rest = command; escalates like run.sh's bound_ms
  local rc planned="$1" now remaining=""
  # The gate (scripts/parity-summary) exports its engine deadline and start:
  # cap this step's fixed bound at the deadline's remaining time minus a 10s
  # margin, so a slow registry cannot outlive the engine command's deadline
  # as a bare command_timeout with no stage named. Standalone (no gate clock)
  # the bound stays exactly as large as requested.
  if [ -n "${NM_GATE_DEADLINE_MS:-}" ] && [ -n "${NM_GATE_START_MS:-}" ]; then
    now="$(date +%s%3N 2>/dev/null)"
    case "$now" in *[!0-9]*) now=$(( $(date +%s) * 1000 )) ;; esac
    remaining=$(( NM_GATE_DEADLINE_MS - ( now - NM_GATE_START_MS ) - 10000 ))
    if [ "$remaining" -lt 5000 ]; then
      echo "FAIL: the engine deadline has too little time left to provision the comparator environment" >&2
      return 124
    fi
    if [ "$planned" -gt "$remaining" ]; then set -- "$remaining" "${@:2}"; fi
  fi
  if command -v timeout >/dev/null 2>&1; then timeout -k 10 "$(( $1 / 1000 ))" "${@:2}"; rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout -k 10 "$(( $1 / 1000 ))" "${@:2}"; rc=$?
  else BOUND_MS="$1" node -e 'const{spawnSync}=require("child_process");const r=spawnSync(process.argv[1],process.argv.slice(2),{stdio:"ignore",timeout:Number(process.env.BOUND_MS),killSignal:"SIGKILL"});process.exit(r.status===null?124:r.status)' "${@:2}"; rc=$?
  fi
  [ "$rc" -eq 137 ] && rc=124
  return "$rc"
}
_provision_log="$_compare_root/parity/out/venv-provision.log"
mkdir -p "$_compare_root/parity/out" 2>/dev/null || true
: > "$_provision_log" 2>/dev/null || true
# uv bootstraps a venv without ensurepip, which some check hosts lack; try it
# first and fall back to python3 -m venv.
# Windows venvs keep the interpreter under Scripts/; resolve either layout
# so a successful provision cannot end in FAIL (review finding).
_venv_python() {
  if [ -x "$_compare_root/parity/.venv/bin/python" ]; then
    echo "$_compare_root/parity/.venv/bin/python"
  elif [ -x "$_compare_root/parity/.venv/Scripts/python.exe" ]; then
    echo "$_compare_root/parity/.venv/Scripts/python.exe"
  fi
}
if command -v uv >/dev/null 2>&1 \
   && bound 120000 uv venv "$_compare_root/parity/.venv" >>"$_provision_log" 2>&1; then
  _vp="$(_venv_python)"
  if [ -n "$_vp" ] && bound 120000 uv pip install --python "$_vp" numpy pillow >>"$_provision_log" 2>&1; then
    PY="$_vp"
  fi
fi
if [ ! -x "$PY" ] && command -v python3 >/dev/null 2>&1 \
   && bound 120000 python3 -m venv "$_compare_root/parity/.venv" >>"$_provision_log" 2>&1; then
  _vp="$(_venv_python)"
  if [ -n "$_vp" ] && bound 120000 "$_vp" -m pip install numpy pillow >>"$_provision_log" 2>&1; then
    PY="$_vp"
  fi
fi
if [ ! -x "$PY" ]; then
  echo "FAIL: the comparator environment is unavailable (see parity/out/venv-provision.log):" >&2
  tail -n 12 "$_provision_log" 2>/dev/null >&2 || true
  return 1 2>/dev/null || exit 1
fi
