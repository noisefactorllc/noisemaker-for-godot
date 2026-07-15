#!/usr/bin/env python3
"""Create one Godot-render manifest for single-frame and timed sweep cases."""

import argparse
import json
from pathlib import Path


EXCLUDED = {"reactionDiffusion", "agentsPoints", "convolutionFeedback"}
TIMED_SAMPLE_EVERY = {"temporalAberration": 10, "navierStokes": 5}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--size", type=int, default=256)
    args = parser.parse_args()
    out_dir = args.root / "parity" / "out"
    entries = []

    for dsl in sorted((args.root / "parity" / "programs").glob("*.dsl")):
        name = dsl.stem
        if name in EXCLUDED:
            continue
        if name in TIMED_SAMPLE_EVERY:
            for stale in out_dir.glob(f"{name}.candidate.t*.png"):
                stale.unlink()
            entries.append({
                "name": name,
                "dsl": str(dsl),
                "out": str(out_dir / f"{name}.candidate.png"),
                "size": args.size,
                "run_seconds": 30,
                "sample_every": TIMED_SAMPLE_EVERY[name],
            })
            continue
        if not (out_dir / f"{name}.golden.png").exists():
            continue
        candidate = out_dir / f"{name}.candidate.png"
        candidate.unlink(missing_ok=True)
        entries.append({
            "name": name,
            "dsl": str(dsl),
            "out": str(candidate),
            "size": args.size,
            "run_seconds": 0,
            "sample_every": 0,
        })

    args.output.write_text(json.dumps({"entries": entries}, indent=2) + "\n")
    print(len(entries))


if __name__ == "__main__":
    main()
