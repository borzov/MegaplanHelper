#!/usr/bin/env python3
"""Builds an intra-project dependency graph for Swift files."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

DECLARATION_PATTERN = re.compile(
    r"\b(?:class|struct|enum|protocol|actor|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"
)
TOKEN_PATTERN = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")
IMPORT_PATTERN = re.compile(r"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)


def load_swift_files(root: Path) -> dict[str, str]:
    swift_files: dict[str, str] = {}
    for path in root.rglob("*.swift"):
        relative_parts = path.relative_to(root).parts
        if (
            "Tests" in relative_parts
            or "build" in relative_parts
            or "DerivedData" in relative_parts
            or ".build" in relative_parts
            or ".claude" in relative_parts
            or any(part.startswith(".") for part in relative_parts[:-1])
        ):
            continue
        swift_files[str(path)] = path.read_text(encoding="utf-8")
    return swift_files


def build_symbol_index(sources: dict[str, str]) -> dict[str, str]:
    index: dict[str, str] = {}
    for file_path, content in sources.items():
        for match in DECLARATION_PATTERN.findall(content):
            index.setdefault(match, file_path)
    return index


def build_graph(sources: dict[str, str], symbol_index: dict[str, str]) -> tuple[dict[str, Counter], dict[str, list[str]]]:
    graph: dict[str, Counter] = defaultdict(Counter)
    imports: dict[str, list[str]] = {}

    for file_path, content in sources.items():
        imports[file_path] = sorted(set(IMPORT_PATTERN.findall(content)))
        symbols = set(TOKEN_PATTERN.findall(content))
        for symbol in symbols:
            target = symbol_index.get(symbol)
            if not target or target == file_path:
                continue
            graph[file_path][target] += 1

    return graph, imports


def build_cycles(graph: dict[str, Counter]) -> list[list[str]]:
    visited: set[str] = set()
    active: set[str] = set()
    stack: list[str] = []
    cycles: list[list[str]] = []

    def visit(node: str) -> None:
        visited.add(node)
        active.add(node)
        stack.append(node)
        for neighbor in graph.get(node, {}):
            if neighbor not in visited:
                visit(neighbor)
            elif neighbor in active:
                start_index = stack.index(neighbor)
                cycle = stack[start_index:] + [neighbor]
                cycles.append(cycle)
        stack.pop()
        active.remove(node)

    for node in graph:
        if node not in visited:
            visit(node)

    def canonicalize_cycle(cycle_path: list[str]) -> tuple[str, ...]:
        cycle_nodes = cycle_path[:-1]
        if not cycle_nodes:
            return tuple()
        rotations = [tuple(cycle_nodes[index:] + cycle_nodes[:index]) for index in range(len(cycle_nodes))]
        reverse_nodes = list(reversed(cycle_nodes))
        rotations.extend(tuple(reverse_nodes[index:] + reverse_nodes[:index]) for index in range(len(reverse_nodes)))
        return min(rotations)

    unique_cycles: list[list[str]] = []
    seen_signatures = set()
    for cycle in cycles:
        signature = canonicalize_cycle(cycle)
        if not signature or signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        unique_cycles.append(cycle)
    return unique_cycles


def main() -> None:
    parser = argparse.ArgumentParser(description="Build Swift intra-project dependency graph.")
    parser.add_argument("--root", required=True, help="Project root path")
    parser.add_argument("--output", required=True, help="Output JSON file path")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    sources = load_swift_files(root)
    symbol_index = build_symbol_index(sources)
    graph, imports = build_graph(sources, symbol_index)

    fan_out = {node: len(edges) for node, edges in graph.items()}
    fan_in: Counter = Counter()
    for source, edges in graph.items():
        for target in edges:
            fan_in[target] += 1

    top_fan_out = sorted(fan_out.items(), key=lambda item: item[1], reverse=True)[:10]
    top_fan_in = fan_in.most_common(10)
    cycles = build_cycles(graph)

    payload = {
        "swift_files": len(sources),
        "declared_symbols": len(symbol_index),
        "edge_count": sum(len(edges) for edges in graph.values()),
        "top_fan_out": top_fan_out,
        "top_fan_in": top_fan_in,
        "cycle_count": len(cycles),
        "cycles": cycles[:20],
        "imports": imports,
        "graph": {key: dict(value) for key, value in graph.items()},
    }
    output.write_text(json.dumps(payload, ensure_ascii=True, indent=2), encoding="utf-8")

    print(f"Swift files: {payload['swift_files']}")
    print(f"Declared symbols: {payload['declared_symbols']}")
    print(f"Dependency edges: {payload['edge_count']}")
    print(f"Cycle count: {payload['cycle_count']}")
    print(f"Report: {output}")


if __name__ == "__main__":
    main()
