# Task B selection: 75_query_string_parse / Quidra

## Answer requirements

Suppose each decoded key retains only distinct decoded values in first-appearance order. Explain how decoding must precede duplicate detection, and how grouped value storage then feeds the existing sorted-key output. Use appending &page=%32 to the second query as a concrete case: the later decoded 2 must not duplicate its earlier value. Identify where and how to change accumulation while preserving key order, distinct later values and empty-value handling.

## Answer and source evidence

Decode each key and value before testing duplicate values in that key's storage. Keep an ordered list per key; append only if the decoded value is absent, retaining later distinct values and the empty string. In the second query page=2 then page=3 then page=%32 yields decoded page values [2,3], not [2,3,2]. Existing sorted-key output remains; deduplicating raw spellings would incorrectly distinguish 2 and %32.

decode_form_component normalizes plus/percent spelling before decoded.get(key). The existing list append is the guarded update site; sorted_entries and quoted rendering remain unchanged.

Selected `main.qui` lines: 11, 21, 22, 23, 24, 25, 26, 27, 28, 30, 31, 32. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
