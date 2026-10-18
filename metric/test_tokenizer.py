"""Regression tests for benchmark-specific tokenizer behavior.

Run from the repository root:
    python3 -m unittest discover -s metric -p 'test_*.py'
"""
import unittest

from metric.tokenizer import tokenize


class EmptyBracketsTest(unittest.TestCase):
    def assert_tokens(self, source: str, expected: list[str]) -> None:
        self.assertEqual([token.text for token in tokenize(source)], expected)

    def test_empty_array_type(self) -> None:
        self.assert_tokens("int[] values", ["int", "[]", " ", "values"])

    def test_empty_index_and_nested_array(self) -> None:
        self.assert_tokens("values[]", ["values", "[]"])
        self.assert_tokens("int[][]", ["int", "[]", "[]"])

    def test_empty_array_literal(self) -> None:
        self.assert_tokens("[]", ["[]"])
        self.assert_tokens("[]\n", ["[]", "\n"])

    def test_nonempty_brackets_remain_separate(self) -> None:
        self.assert_tokens("values[0]", ["values", "[", "0", "]"])
        self.assert_tokens("[ ]", ["[", " ", "]"])

    def test_brackets_inside_strings_follow_literal_rules(self) -> None:
        self.assert_tokens('"[]"', ['"', "[", "]", '"'])


if __name__ == "__main__":
    unittest.main()
