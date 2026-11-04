# Task B selection: 51_case_converter / Python

## Common answer requirements

Append the upper field using the existing normalized words and output delimiter.

## Source evidence

The word-list expression splits on underscores, hyphens, and before ASCII uppercase letters, discards empty parts, and lowercases the remainder. The snake field shows underscore joining of those normalized words. The upper field can use the same normalized sequence with uppercase letters and append the requested comma-and-space field.

## Minimization

The regex import identifies the splitter and the word-list expression establishes its actual normalization. The snake expression and output line identify the existing join and framing. Selected complete lines of `main.py`: 1, 12, 13, 17.
