#!/usr/bin/env python3
"""Builds an architecture backlog from Swift graph and git churn."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def run_git_churn(repo_root: Path, days: int) -> dict[str, int]:
    cmd = [
        "git",
        "log",
        f"--since={days} days ago",
        "--name-only",
        "--pretty=format:",
    ]
    result = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, check=True)
    churn: dict[str, int] = {}
    for line in result.stdout.splitlines():
        normalized = line.strip()
        if not normalized or not normalized.endswith(".swift") or normalized.startswith("Tests/"):
            continue
        churn[normalized] = churn.get(normalized, 0) + 1
    return churn


def read_file_lines(path: Path) -> int:
    with path.open("r", encoding="utf-8") as file:
        return sum(1 for _ in file)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build architecture backlog for refactoring priorities.")
    parser.add_argument("--root", required=True, help="Project root path")
    parser.add_argument("--graph", required=True, help="Path to graph JSON from swift_dependency_graph.py")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--days", type=int, default=120, help="Git churn lookback")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    graph_path = Path(args.graph).resolve()
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    graph_data = json.loads(graph_path.read_text(encoding="utf-8"))
    churn = run_git_churn(root, args.days)

    graph = graph_data.get("graph", {})
    fan_out = {Path(source).relative_to(root).as_posix(): len(targets) for source, targets in graph.items()}
    fan_in: dict[str, int] = {}
    for source_targets in graph.values():
        for target in source_targets:
            relative_target = Path(target).relative_to(root).as_posix()
            fan_in[relative_target] = fan_in.get(relative_target, 0) + 1

    candidates = []
    for relative_path, file_churn in churn.items():
        absolute_path = root / relative_path
        if not absolute_path.exists():
            continue
        lines = read_file_lines(absolute_path)
        fan_out_count = fan_out.get(relative_path, 0)
        fan_in_count = fan_in.get(relative_path, 0)
        score = (lines / 20) + (file_churn * 8) + (fan_out_count * 5) + (fan_in_count * 3)
        candidates.append(
            {
                "file": relative_path,
                "score": round(score, 2),
                "lines": lines,
                "churn": file_churn,
                "fan_out": fan_out_count,
                "fan_in": fan_in_count,
                "recommendation": "Split feature slices and isolate side effects behind protocol boundaries"
                if lines > 400
                else "Reduce coupling with focused helper extraction",
            }
        )

    backlog = sorted(candidates, key=lambda item: item["score"], reverse=True)[:15]
    payload = {
        "lookback_days": args.days,
        "cycle_count": graph_data.get("cycle_count", 0),
        "priority_backlog": backlog,
    }
    output.write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
    print(f"Backlog entries: {len(backlog)}")
    print(f"Report: {output}")


if __name__ == "__main__":
    main()
