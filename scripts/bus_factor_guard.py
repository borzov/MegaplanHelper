#!/usr/bin/env python3
"""Generates bus factor risk report for critical Swift components."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


CRITICAL_PATTERNS = (
    "AppState.swift",
    "Services/MegaplanAPI.swift",
    "Services/NotificationManager.swift",
    "Services/KeychainManager.swift",
    "ViewModels/NotificationListViewModel.swift",
)


def run_ownership(repo_root: Path, relative_path: str) -> list[str]:
    cmd = ["git", "log", "--format=%an", "--", relative_path]
    result = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, check=True)
    owners = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    return sorted(owners)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate bus factor risk report.")
    parser.add_argument("--root", required=True, help="Project root path")
    parser.add_argument("--output", required=True, help="Output JSON file")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    report = []
    for relative_path in CRITICAL_PATTERNS:
        owners = run_ownership(root, relative_path)
        report.append(
            {
                "file": relative_path,
                "owner_count": len(owners),
                "owners": owners,
                "risk": "critical" if len(owners) <= 1 else "moderate",
                "next_action": "Assign backup owner and require cross-review for every change"
                if len(owners) <= 1
                else "Keep regular ownership rotation",
            }
        )

    payload = {"critical_components": report}
    output.write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")
    print(f"Report: {output}")


if __name__ == "__main__":
    main()
