#!/usr/bin/env python3
"""Build the shared viewer index from measured result directories."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def build_index(root: Path) -> dict:
    root = root.resolve()
    results: dict = {}
    for path in sorted(root.glob("results/????-??-??/*/*/*/task[AB].json")):
        _, date, difficulty, topic, language, name = path.relative_to(root).parts
        languages = results.setdefault(date, {}).setdefault(difficulty, {}).setdefault(topic, {})
        languages[language] = languages.get(language, "") + name[4]
    index = {"version": 1, "results": results}
    destination = root / "results/views.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(index, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return index


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                        help="repository root (default: parent of metric/)")
    args = parser.parse_args()
    try:
        index = build_index(args.root)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"error: {error}\n")
    count = sum(len(tasks) for date in index["results"].values()
                for difficulty in date.values() for topic in difficulty.values()
                for tasks in topic.values())
    print(f"Indexed {count} token views in results/views.json")


if __name__ == "__main__":
    main()
