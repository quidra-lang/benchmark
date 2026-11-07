# Task B selection: 30_set_operations / Quidra

## Answer requirements

Suppose the union line gains a size field containing its cardinality. In the local union/output block, identify where and how to count the distinct result elements rather than their sum or the number of original input slots. Connect result construction, the cardinality operation and insertion of the new field, explaining the unit being counted. Leave the other three set results unchanged.

## Answer and source evidence

Compute cardinality from the named union result, using len(result) in Python or union.size() in Quidra, and insert a size field only on the union line. This counts distinct set elements, not their numeric sum or the combined input-array slots. Keep set construction/deduplication and sorted element display. The other three operations retain their existing output.

union retains distinct storage before sorted() turns it into an ordered array. Either cardinality gives the same unit, but union.size() directly names the requested set; show must receive or format that additional union-only field.

Selected `main.qui` lines: 4, 5, 9, 10, 11, 12. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
