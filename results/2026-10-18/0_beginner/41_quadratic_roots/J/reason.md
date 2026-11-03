# Task B selection: 41_quadratic_roots / J

## Common answer requirements

For (-2,5,4), derive discriminant and both quadratic-formula values; explain why the negative denominator makes the minus-root value larger; identify source ordering and its preservation in printed x1/x2.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The discriminant is 5²−4(−2)(4)=57>0. With denominator−4, the +sqrt value is (−5+sqrt57)/(−4)≈−0.6374586088 and the −sqrt value is (−5−sqrt57)/(−4)≈3.1374586088. Thus formula order alone is not descending. The selected max/min expressions or conditional swap explicitly put the larger value first; x1 prints 3.1375 and x2 prints −0.6375 with four fractional digits. The distinct-real branch is selected because 57 is positive.

The selected body of fixed establishes four fractional digits; >. and <. order the values independently of denominator sign.

Source: `main.ijs`. Selected original lines: 1,2,6,7,8,9,13,14,15,16,17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `fixed =: 3 : 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `  , '4' 8!:2 y` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `  for_row. 6 3$1 _3 _10 _2 5 4 3 1 _2 4 _12 9 1 2 5 _2 3 _4 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    'a b c' =. row` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    d =. (b*b)-4*a*c` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    denominator =. 2.0*a` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    if. d>0 do.` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `      root =. %:0.0+d` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `      first =. ((-b)+root)%denominator` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `      second =. ((-b)-root)%denominator` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `      smoutput prefix,'x1 = ',(fixed first>.second),', x2 = ',fixed first<.second` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **213 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **411 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 203 tokens (versus 213); removes `fixed =: 3 : 0`.
- Without L2: 200 tokens (versus 213); removes `, '4' 8!:2 y`.
- Without L6: 156 tokens (versus 213); removes `for_row. 6 3$1 _3 _10 _2 5 4 3 1 _2 4 _12 9 1 2 5 _2 3 _4 do.`.
- Without L7: 200 tokens (versus 213); removes `'a b c' =. row`.
- Without L8: 196 tokens (versus 213); removes `d =. (b*b)-4*a*c`.
- Without L9: 202 tokens (versus 213); removes `denominator =. 2.0*a`.
- Without L13: 204 tokens (versus 213); removes `if. d>0 do.`.
- Without L14: 200 tokens (versus 213); removes `root =. %:0.0+d`.
- Without L15: 196 tokens (versus 213); removes `first =. ((-b)+root)%denominator`.
- Without L16: 196 tokens (versus 213); removes `second =. ((-b)-root)%denominator`.
- Without L17: 177 tokens (versus 213); removes `smoutput prefix,'x1 = ',(fixed first>.second),', x2 = ',fixed first<.second`.
