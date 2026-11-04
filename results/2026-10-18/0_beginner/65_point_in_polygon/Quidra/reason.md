# Task B selection: 65_point_in_polygon / Quidra

## Common answer requirements

[Modification analysis]

Using the Task A source as evidence, explain which parts would need to change and how to satisfy the proposed requirements below. Do not edit the program or produce modified source code.

Proposed requirements:
Include the actual ray-crossing count in every point's output. After the existing "inside" or "outside" result, append one ASCII space followed by "crossings=N", where N is the nonnegative decimal count with no leading zeros. Count only edges satisfying the existing strict crossing conditions, and derive the classification from the parity of that same count. Keep the coordinates and point order unchanged. All other Task A requirements remain unchanged.

## Answer supported by the selection

The current counter starts at zero for each point and increments only after both existing strict crossing tests succeed: the endpoint heights straddle py, and the double-precision intersection is strictly greater than px. The result label uses the parity of that same counter. Append one space and `crossings={crossings}` inside the existing output interpolation after `{result}`. Integer interpolation already produces the required decimal count without padding. No change is needed to the strict conditions, intersection arithmetic, counter, classification or point traversal.

## Source evidence and minimization

The typed success bindings convert integer coordinates and differences to double precision before arithmetic, in the original multiplication/division/addition order. The counter initialization, both crossing conditions, intersection expression, increment and parity expression establish the actual count to print. The existing output line locates the only required modification and preserves coordinates and point order. Input coordinates and edge traversal mechanics do not change and are not necessary for this output-only analysis.

Locations in main source: L4, L5, L8, L9, L10, L11, L12, L13, L14, L15, L16.

All selected lines are complete, verbatim and in source order. The selected source, the question, and documented language/library semantics support the answer. The full source is a sufficient alternative but includes the unrelated material identified above; the retained selection is a reviewed lower-token sufficient candidate, without a claim of exhaustive global minimality.

Measurement: Task A 383; Task B 175. Tokenizer: metric/tokenizer.py, unchanged. These counts and source selections do not establish compilation or execution of Task A.

Execution verification: the revised program compiled and its stdout matched the Python reference, because the historical Quidra source fails current compilation exactly.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 383; Task B 175.
