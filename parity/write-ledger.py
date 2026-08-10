#!/usr/bin/env python3
"""Build a policy-accurate Godot parity ledger from one sweep."""

import argparse
import collections
import json
import re
from pathlib import Path


STRICT_TOLERANCE = 2.001
STRICT_SSIM_MIN = 0.98


def explicit_effect_arguments(source, effect):
    matches = list(re.finditer(
        rf"(?<![A-Za-z0-9_])(?:\.)?{re.escape(effect)}\(", source
    ))
    if not matches:
        return ""
    start = matches[-1].end()
    depth = 0
    quote = None
    escaped = False
    chars = []
    for char in source[start:]:
        if quote:
            chars.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in {'"', "'"}:
            quote = char
            chars.append(char)
        elif char == "(":
            depth += 1
            chars.append(char)
        elif char == ")":
            if depth == 0:
                break
            depth -= 1
            chars.append(char)
        else:
            chars.append(char)
    return re.sub(r"\s+", " ", "".join(chars)).strip()


def top_level_calls(source):
    """Return (name, dotted) calls outside argument lists and comments."""
    calls = []
    depth = 0
    quote = None
    escaped = False
    i = 0
    while i < len(source):
        char = source[i]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            i += 1
            continue
        if source.startswith("//", i):
            newline = source.find("\n", i + 2)
            i = len(source) if newline < 0 else newline + 1
            continue
        if source.startswith("/*", i):
            end = source.find("*/", i + 2)
            i = len(source) if end < 0 else end + 2
            continue
        if char in {'"', "'"}:
            quote = char
            i += 1
            continue
        if char == "(":
            depth += 1
            i += 1
            continue
        if char == ")":
            depth = max(0, depth - 1)
            i += 1
            continue
        if depth == 0 and (char.isalpha() or char == "_"):
            end = i + 1
            while end < len(source) and (source[end].isalnum() or source[end] == "_"):
                end += 1
            cursor = end
            while cursor < len(source) and source[cursor].isspace():
                cursor += 1
            if cursor < len(source) and source[cursor] == "(":
                previous = i - 1
                while previous >= 0 and source[previous].isspace():
                    previous -= 1
                calls.append((source[i:end], previous >= 0 and source[previous] == "."))
            i = end
            continue
        i += 1
    return calls


def effect_metadata(root, program):
    dsl = root / "parity" / "programs" / f"{program}.dsl"
    effect = None
    namespace = "filter"
    source = ""
    if dsl.exists():
        source = dsl.read_text()
        calls = [
            (name, dotted) for name, dotted in top_level_calls(source)
            if name not in {"write", "render", "render3d", "renderCubemap3d"}
        ]
        if calls:
            effect, dotted = calls[-1]
            if not dotted:
                effects_root = root / "godot" / "addons" / "noisemaker" / "effects"
                search = re.search(r"^\s*search\s+([^\n]+)$", source, re.MULTILINE)
                selected_namespace = next((
                    candidate.strip()
                    for candidate in search.group(1).split(",")
                    if (effects_root / candidate.strip() / f"{effect}.json").exists()
                ), None) if search else None
                if selected_namespace in {"filter3d", "synth3d"}:
                    namespace = selected_namespace
                else:
                    effect = None
    mode = explicit_effect_arguments(source, effect) if effect else ""
    if not mode and effect and program.startswith(effect + "_"):
        mode = program[len(effect) + 1 :]
    mode = mode or "default"
    if effect:
        effects_root = root / "godot" / "addons" / "noisemaker" / "effects"
        if namespace == "filter":
            for candidate in ("filter3d", "synth3d"):
                if (effects_root / candidate / f"{effect}.json").exists():
                    namespace = candidate
                    break
    return (f"{namespace}/{effect}" if effect else None), mode


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else args.root / args.output
    rows = []

    for line in args.results.read_text().splitlines():
        if not line:
            continue
        program, requested, tolerance, ssim_min, reason = line.split("\t", 4)
        policy_tolerance = float(tolerance)
        policy_ssim_min = float(ssim_min)
        report_path = args.root / "parity" / "out" / f"{program}.report.json"
        report = json.loads(report_path.read_text()) if report_path.exists() else {}
        verdict = requested
        golden = f"parity/out/{program}.golden.png"
        candidate = f"parity/out/{program}.candidate.png"
        samples = None
        if requested == "TIMED":
            timed_reports = sorted(
                (args.root / "parity" / "out").glob(f"{program}.report.t*.json"),
                key=lambda path: int(re.search(r"\.t(\d+)\.json$", path.name).group(1)),
            )
            samples = []
            for timed_report_path in timed_reports:
                second = int(re.search(r"\.t(\d+)\.json$", timed_report_path.name).group(1))
                timed_report = json.loads(timed_report_path.read_text())
                golden_path = f"parity/out/{program}.golden.t{second}.png"
                candidate_path = f"parity/out/{program}.candidate.t{second}.png"
                max_diff = timed_report.get("max_abs_diff")
                sample_ssim = timed_report.get("ssim")
                try:
                    policy_matches = (
                        timed_report.get("name") == f"{program}_t{second}"
                        and float(timed_report.get("tolerance")) == policy_tolerance
                        and float(timed_report.get("ssim_min")) == policy_ssim_min
                    )
                    within_policy = (
                        float(max_diff) <= policy_tolerance
                        and float(sample_ssim) >= policy_ssim_min
                    )
                except (TypeError, ValueError):
                    policy_matches = False
                    within_policy = False
                samples.append({
                    "time_seconds": second,
                    "golden": golden_path,
                    "candidate": candidate_path,
                    "max_abs_diff": max_diff,
                    "mean_abs_diff": timed_report.get("mean_abs_diff"),
                    "ssim": sample_ssim,
                    "passed": bool(timed_report.get("passed")) and policy_matches and within_policy,
                    "policy_matches": policy_matches,
                })
            evidence_complete = bool(samples) and all(
                sample["passed"]
                and (args.root / sample["golden"]).exists()
                and (args.root / sample["candidate"]).exists()
                for sample in samples
            )
            if not evidence_complete:
                verdict = "FAIL"
                reason = "timed sample evidence is missing or contains a failed comparison"
            golden = [sample["golden"] for sample in samples]
            candidate = [sample["candidate"] for sample in samples]
            if evidence_complete:
                report = {
                    "max_abs_diff": max(sample["max_abs_diff"] for sample in samples),
                    "mean_abs_diff": max(sample["mean_abs_diff"] for sample in samples),
                    "ssim": min(sample["ssim"] for sample in samples),
                }
                if report["max_abs_diff"] <= STRICT_TOLERANCE and report["ssim"] >= STRICT_SSIM_MIN:
                    verdict = "PASS"
                else:
                    verdict = "NEAR"
        if requested == "AUTO":
            try:
                report_valid = (
                    report.get("name") == program
                    and bool(report.get("passed"))
                    and float(report.get("tolerance")) == policy_tolerance
                    and float(report.get("ssim_min")) == policy_ssim_min
                    and float(report.get("max_abs_diff")) <= policy_tolerance
                    and float(report.get("ssim")) >= policy_ssim_min
                )
            except (TypeError, ValueError):
                report_valid = False
            if not report_valid:
                verdict = "FAIL"
                reason = "shell status was not backed by a complete passing comparison report"
            elif report.get("max_abs_diff", float("inf")) <= STRICT_TOLERANCE and report.get("ssim", 0) >= STRICT_SSIM_MIN:
                verdict = "PASS"
            else:
                verdict = "NEAR"
        effect, mode = effect_metadata(args.root, program)
        rows.append({
            "program": program,
            "effect": effect,
            "mode": mode,
            "golden": golden,
            "candidate": candidate,
            "verdict": verdict,
            "max_abs_diff": report.get("max_abs_diff"),
            "mean_abs_diff": report.get("mean_abs_diff"),
            "ssim": report.get("ssim"),
            "passed": verdict in {"PASS", "NEAR"},
            "skipped": verdict in {"SKIP", "CHAOS"},
            "policy": {
                "tolerance": policy_tolerance,
                "ssim_min": policy_ssim_min,
                "strict_tolerance": STRICT_TOLERANCE,
                "strict_ssim_min": STRICT_SSIM_MIN,
                "reason": reason,
            },
        })
        if samples is not None:
            rows[-1]["samples"] = samples

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(sorted(rows, key=lambda row: row["program"]), indent=2) + "\n")

    exit_code = 0
    if any(row["verdict"] == "FAIL" for row in rows):
        exit_code = 1

    programs_dir = args.root / "parity" / "programs"
    if programs_dir.is_dir():
        universe = {path.stem for path in programs_dir.glob("*.dsl")}
        row_counts = collections.Counter(row["program"] for row in rows)
        covered = set(row_counts)
        missing = sorted(universe - covered)
        extra = sorted(covered - universe)
        duplicates = sorted(name for name, count in row_counts.items() if count > 1)
        if len(rows) != len(covered):
            assert duplicates, "row/covered count mismatch with no duplicate program identified"
        if missing or extra or duplicates:
            if missing:
                print(f"[write-ledger] UNIVERSE MISMATCH: {len(missing)} program(s) on disk have no "
                      f"ledger row: {' '.join(missing)}")
            if extra:
                print(f"[write-ledger] UNIVERSE MISMATCH: {len(extra)} ledger row(s) have no matching "
                      f".dsl on disk: {' '.join(extra)}")
            if duplicates:
                print(f"[write-ledger] UNIVERSE MISMATCH: {len(duplicates)} program(s) have more than "
                      f"one ledger row ({len(rows)} rows for {len(covered)} distinct programs): "
                      f"{' '.join(duplicates)}")
            exit_code = 1

    if exit_code:
        raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
