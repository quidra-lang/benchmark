# Task B selection: 62_edit_distance / Ruby

## Common answer requirements

Explain the empty-prefix table boundaries and trace the three predecessor cases through the distance from flaw to lawn.

## Source evidence

The table’s boundary entries are the length of the nonempty prefix: from empty, insert every target character; to empty, delete every source character. With rows for flaw and columns for lawn, the upper entry plus one deletes the final source character, the left entry plus one inserts the final target character, and the diagonal entry adds zero for a match or one for replacement. In prefix-length coordinates, (1,0)=1 (delete f), (2,1)=1 (match l), (3,2)=1 (match a), and (4,3)=1 (match w). At (4,4) the alternatives are deletion 4, insertion 2, replacement 3; appending n yields the final distance 2.

## Minimization

The question supplies both inputs. Case arrays, unrelated examples, and caller prints are unnecessary; the selected table indexing, boundary writes and recurrence determine the answer.

Selected complete lines of `main.rb`: 7–12. The prior excerpt measured 301 tokens; this excerpt measures 199 with `metric/tokenizer.py`.
