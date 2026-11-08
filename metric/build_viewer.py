#!/usr/bin/env python3
"""Build the static token-view index; optionally migrate legacy task HTML."""
from __future__ import annotations

import argparse
from html.parser import HTMLParser
import json
from pathlib import Path

from tokenizer import render_data, render_html, tokenize


class _LegacySource(HTMLParser):
    """Read only code cells, preserving line breaks and separate programs."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.programs: list[list[str]] = []
        self.code_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        classes = (dict(attrs).get("class") or "").split()
        if tag == "div" and "program" in classes:
            self.programs.append([])
        elif tag == "div" and "line" in classes and self.programs:
            self.programs[-1].append("")
        elif tag == "span" and ("code" in classes or self.code_depth):
            self.code_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag == "span" and self.code_depth:
            self.code_depth -= 1

    def handle_data(self, data: str) -> None:
        if self.code_depth and self.programs and self.programs[-1]:
            self.programs[-1][-1] += data


def migrate_view(path: Path) -> None:
    """Replace a generated view only after an exact rendering round trip."""
    original = path.read_text(encoding="utf-8")
    parser = _LegacySource()
    parser.feed(original)
    programs = [tokenize("\n".join(lines)) for lines in parser.programs]
    if not programs or render_html(programs) != original:
        raise ValueError(f"Cannot safely migrate unrecognized or outdated HTML: {path}")
    data = render_data(programs)
    target = path.with_suffix(".json")
    if target.exists() and json.loads(target.read_text(encoding="utf-8")) != json.loads(data):
        raise ValueError(f"Conflicting token data already exists: {target}")
    target.write_text(data, encoding="utf-8")
    path.unlink()


def build_index(root: Path, migrate_html: bool = False) -> dict:
    root = root.resolve()
    if migrate_html:
        for path in sorted(root.glob("results/????-??-??/*/*/*/task[AB].html")):
            migrate_view(path)
    results: dict = {}
    for path in sorted(root.glob("results/????-??-??/*/*/*/task[AB].json")):
        _, date, difficulty, topic, language, name = path.relative_to(root).parts
        languages = results.setdefault(date, {}).setdefault(difficulty, {}).setdefault(topic, {})
        languages[language] = languages.get(language, "") + name[4]
    index = {"version": 1, "results": results}
    destination = root / "metric/views.json"
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
    parser.add_argument("--migrate-html", action="store_true",
                        help="convert existing generated task HTML to JSON and remove the old HTML")
    args = parser.parse_args()
    try:
        index = build_index(args.root, args.migrate_html)
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f"error: {error}\n")
    count = sum(len(tasks) for date in index["results"].values()
                for difficulty in date.values() for topic in difficulty.values()
                for tasks in topic.values())
    print(f"Indexed {count} token views in metric/views.json")


if __name__ == "__main__":
    main()
