# Task B selection: 42_triangle_classify / Go

## Common answer requirements

Locate the original-side output and the existing sorted side representation; explain printing the latter for every set including invalid triangles, preserving outer order and existing classification rules/labels.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Use the already ascending-sorted three sides in the output prefix instead of the original triple. Where the prefix is constructed before sorting, construct it after the sorted values become available and before the validity branch/early continue. Where a final shared print emits every result, change only its side sequence; where the prefix is printed before classification, substitute sorted sides there. Do not sort the outer collection or change any validity/side/angle test. This also affects invalid triangles because the replacement occurs on their shared prefix/output path.

Array assignment a:=p copies the triple by value; slices.Sort(a[:]) sorts that copy. Print a rather than p.

Source: `main.go`. Selected original lines: 11-13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L11: `		a := p` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `		slices.Sort(a[:])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `		fmt.Printf("%d %d %d: ", p[0], p[1], p[2])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **56 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **490 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L11: 48 tokens (versus 56); removes `a := p`.
- Without L12: 45 tokens (versus 56); removes `slices.Sort(a[:])`.
- Without L13: 19 tokens (versus 56); removes `fmt.Printf("%d %d %d: ", p[0], p[1], p[2])`.
