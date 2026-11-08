"""Regression tests for token-view data and the static-view migration."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import tokenizer


class TokenDataTests(unittest.TestCase):
    def test_compact_data_preserves_token_boundaries_and_empty_programs(self):
        self.assertTrue(hasattr(tokenizer, "render_data"), "JSON output is missing")
        data = json.loads(tokenizer.render_data([tokenizer.tokenize("x := 7\n"), []]))
        self.assertEqual(data, {"version": 1, "programs": [
            {"source": "x := 7\n", "lengths": [1, 1, 2, 1, 1, 1]},
            {"source": "", "lengths": []},
        ]})

    def test_unicode_lengths_use_normalized_code_points(self):
        self.assertTrue(hasattr(tokenizer, "render_data"), "JSON output is missing")
        data = json.loads(tokenizer.render_data([tokenizer.tokenize("\ufeff😀\r\n")]))
        self.assertEqual(data["programs"], [{"source": "😀\n", "lengths": [1, 1]}])

    def test_default_cli_writes_only_json_and_keeps_stdout_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                [sys.executable, str(Path(tokenizer.__file__).resolve())],
                cwd=tmp, input="x := 7\n", text=True, capture_output=True, check=True,
            )
            self.assertEqual(result.stdout, "6\n")
            self.assertTrue((Path(tmp) / "token.json").is_file(), "default JSON is missing")
            self.assertFalse((Path(tmp) / "token.html").exists())

    def test_json_cli_keeps_multiple_input_order_and_per_file_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "first.qui").write_text("x := 7\n", encoding="utf-8")
            (root / "second.qui").write_text("😀\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(Path(tokenizer.__file__).resolve()), "--json", "view.json",
                 "first.qui", "second.qui"],
                cwd=root, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "6\n2\n")
            data = json.loads((root / "view.json").read_text(encoding="utf-8"))
            self.assertEqual([p["source"] for p in data["programs"]], ["x := 7\n", "😀\n"])

    def test_explicit_standalone_html_export_remains_available(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = subprocess.run(
                [sys.executable, str(Path(tokenizer.__file__).resolve()), "--html", "view.html"],
                cwd=tmp, input="x\n", text=True, capture_output=True, check=True,
            )
            self.assertEqual(result.stdout, "2\n")
            self.assertIn('<span class="token c0">x</span>',
                          (Path(tmp) / "view.html").read_text(encoding="utf-8"))


class IndexTests(unittest.TestCase):
    def builder(self):
        import importlib.util
        path = Path(tokenizer.__file__).with_name("build_viewer.py")
        self.assertTrue(path.is_file(), "static index builder is missing")
        spec = importlib.util.spec_from_file_location("build_viewer", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_migration_round_trips_multi_file_html_and_builds_selection_index(self):
        builder = self.builder()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent = root / "results/2026-11-07/1_intermediate/00_case"
            for lang, tasks in (("C#", "AB"), ("C++", "A")):
                directory = parent / lang
                directory.mkdir(parents=True)
                for task in tasks:
                    html = tokenizer.render_html([
                        tokenizer.tokenize('println("😀<&>")\n\n'), [],
                        tokenizer.tokenize("  final\n"),
                    ])
                    (directory / f"task{task}.html").write_text(html, encoding="utf-8")
                (directory / "main.txt").write_text("leave untouched", encoding="utf-8")
            index = builder.build_index(root, migrate_html=True)
            self.assertEqual(index, {"version": 1, "results": {"2026-11-07": {
                "1_intermediate": {"00_case": {"C#": "AB", "C++": "A"}},
            }}})
            self.assertEqual(json.loads((root / "metric/views.json").read_text()), index)
            for path in root.glob("results/**/*.json"):
                programs = json.loads(path.read_text(encoding="utf-8"))["programs"]
                self.assertEqual([p["source"] for p in programs], ['println("😀<&>")\n\n', "", "  final\n"])
            self.assertEqual(len(list(root.glob("results/**/*.html"))), 0)
            self.assertEqual((parent / "C#/main.txt").read_text(), "leave untouched")
            first = (root / "metric/views.json").read_bytes()
            builder.build_index(root, migrate_html=True)
            self.assertEqual((root / "metric/views.json").read_bytes(), first)

    def test_migration_refuses_unrecognized_html_without_deleting_it(self):
        builder = self.builder()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            view = root / "results/2026-11-07/0_beginner/00_case/Python/taskA.html"
            view.parent.mkdir(parents=True)
            view.write_text("<html><p>unexpected content</p></html>")
            with self.assertRaises(ValueError):
                builder.build_index(root, migrate_html=True)
            self.assertTrue(view.exists())
            self.assertFalse(view.with_suffix(".json").exists())

    def test_migration_preserves_a_conflicting_existing_json(self):
        builder = self.builder()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            view = root / "results/2026-11-07/0_beginner/00_case/Python/taskA.html"
            view.parent.mkdir(parents=True)
            view.write_text(tokenizer.render_html([tokenizer.tokenize("old\n")]))
            data = view.with_suffix(".json")
            original = '{"version":1,"programs":[{"source":"new\\n","lengths":[3,1]}]}'
            data.write_text(original)
            with self.assertRaises(ValueError):
                builder.build_index(root, migrate_html=True)
            self.assertEqual(data.read_text(), original)
            self.assertTrue(view.exists())


if __name__ == "__main__":
    unittest.main()
