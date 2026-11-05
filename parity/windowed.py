"""Bounded windowed engine spawns for the live suites.

Every windowed Godot launch goes through run_windowed: its per-spawn bound
stays far under the operator's 300-second engine-command cap, and one stalled
launch fails named and marks the process so every later windowed launch in
the same run fails in milliseconds instead of stalling again. A runner whose
display or GPU cannot serve windowed renders therefore ends as a named
failure inside the cap, never as a bare harness kill with no artifacts.

Headless launches do not go through this helper: they work without a display
and must not be aborted by a windowed stall.
"""

import os
import subprocess

STALL_FLAG = "NM_WINDOWED_STALLED"
STALL_MESSAGE = (
    "a windowed engine launch stalled past its bound; later windowed "
    "launches fail immediately because the environment cannot run them"
)


def run_windowed(args, *, timeout, **kwargs):
    """Run a windowed engine launch under its named bound.

    Raises RuntimeError immediately when an earlier launch in this process
    stalled, and subprocess.TimeoutExpired (after setting the stall flag)
    when this launch stalls, so the failure always names its cause.
    """
    if os.environ.get(STALL_FLAG):
        raise RuntimeError(STALL_MESSAGE)
    try:
        return subprocess.run(args, timeout=timeout, **kwargs)
    except subprocess.TimeoutExpired:
        os.environ[STALL_FLAG] = "1"
        raise
