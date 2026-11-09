# Task B selection: 94_league_standings / Python

## Answer requirements

Suppose original team order must remain available after sorting the standings. Identify the source's sort expression and whether it reorders the existing ordering container or returns a separate order. Explain where and how that expression must change if needed so the two orders stay independent, distinguishing shared team records from shared ordering storage. Focus on sorting/aliasing rather than recomputing statistics.

## Answer and source evidence

Python sorted(teams,...) creates a separate ordering list and leaves teams in original order, so its expression already meets the requirement; shared immutable names or separately stored team records do not make the two ordering containers identical. Quidra sorted returns a separate value but assignment writes it back to teams, losing that binding's original order. Bind the sorted result to a separate ordered value and render that, preserving teams. Ordinary Quidra value semantics keep ordering storage independent; no statistics recomputation is required.



Selected `main.py` lines: 44. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
