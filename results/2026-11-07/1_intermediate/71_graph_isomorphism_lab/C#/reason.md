# Task B selection — C#

## Answer requirements shared across languages

1. Trace REFINE g with no individualisation arguments from graph lookup through initial ascending degree-color classes.
2. Explain construction of old-color/neighbor-color signatures and each candidate partition,including why replacement is simultaneous rather than sequential vertex feedback.
3. Explain stability testing and round counting,why the final stable attempt is uncounted,and the ascending color/vertex display.

## Selected source locations

- `Program.cs`: 32, 73, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 649, 677, 678, 679, 687, 688, 689, 690, 691, 692

## Evidence and language semantics

Graphs lookup supplies the graph. DegreeColors maps degrees to ascending distinct ranks. Signatures read the old colors; separate next is filled after all signatures exist. Cells equality returns old colors and rounds before replacement/increment. Display loops colors then ascending v. With no individualisation arguments,the initial degree-based refinement flows directly to this display; no individualize operation runs. Because the signature includes the previous color,classes can split but cannot merge,so unchanged class count means a stable partition even if candidate labels would differ.

## Minimization and alternatives

Retain graph lookup,degree-rank construction,signature/candidate formation,the stability guard before replacement/increment,and ordered display. Known sorting,popcount,container and value-assignment semantics avoid unrelated graph construction and canonicalization. Custom rank/comparison/cell helpers are retained where they establish ordering or class counts. The stable-round guard alone would not establish simultaneous updates or output; the full command dispatcher would add unrelated features.

The excerpt contains 970 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
