# Task B selection: 19_bmi_calculator / Rust

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.

f64::from on numerator and denominator establishes real division; the ordered if/else-if chain reaches overweight before output formatting.

Source: `main.rs`. Selected original lines: 2,5,9,10,11,12,13,14,15,16,17,20,21. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    for (name, h, w) in [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        ("Mika", 165, 70),` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        let numerator = w * 10000;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        let denominator = h * h;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `        let bmi = f64::from(numerator) / f64::from(denominator);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        let category = if bmi < 18.5 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `            "underweight"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        } else if bmi < 25.0 {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `            "normal"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        } else if bmi < 30.0 {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `            "overweight"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `        };` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L21: `        println!("{}: BMI {:.1} ({})", name, bmi, category);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **212 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **318 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 195 tokens (versus 212); removes `for (name, h, w) in [`.
- Without L5: 194 tokens (versus 212); removes `("Mika", 165, 70),`.
- Without L9: 193 tokens (versus 212); removes `let numerator = w * 10000;`.
- Without L10: 197 tokens (versus 212); removes `let denominator = h * h;`.
- Without L11: 187 tokens (versus 212); removes `let bmi = f64::from(numerator) / f64::from(denominator);`.
- Without L12: 191 tokens (versus 212); removes `let category = if bmi < 18.5 {`.
- Without L13: 205 tokens (versus 212); removes `"underweight"`.
- Without L14: 193 tokens (versus 212); removes `} else if bmi < 25.0 {`.
- Without L15: 205 tokens (versus 212); removes `"normal"`.
- Without L16: 193 tokens (versus 212); removes `} else if bmi < 30.0 {`.
- Without L17: 205 tokens (versus 212); removes `"overweight"`.
- Without L20: 207 tokens (versus 212); removes `};`.
- Without L21: 179 tokens (versus 212); removes `println!("{}: BMI {:.1} ({})", name, bmi, category);`.
