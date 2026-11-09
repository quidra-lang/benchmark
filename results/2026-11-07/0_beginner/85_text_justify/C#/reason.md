# Task B selection: 85_text_justify / C#

Splitting on ASCII space keeps names, as one six-character token, so punctuation contributes to letters and greedy packing. A next word is admitted only while letter total plus minimum gaps fits width 30. For a nonfinal multiword line, spaces=30-sum(lengths), gaps=wordCount-1; quotient goes to each gap and the remainder adds one to leftmost gaps. Final/single-word lines use ordinary joining plus right padding; vertical bars frame the completed width-30 text.

The full packing/formatting operation from word tokens is retained, excluding the long paragraph literal because names, and its meaning are supplied by the question. Main/import scaffolding is unrelated.

Selected complete source lines in `Program.cs`: 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
