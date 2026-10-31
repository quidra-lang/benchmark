# Task B selection: 19_bmi_calculator / Kotlin

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.



Source: `main.kt`. Selected original lines: 4,5,6,8,9,10,11,12,14,15. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L4: `    val names = listOf("Aiko", "Kenji", "Mika", "Ryo", "Yuki")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    val heights = intArrayOf(158, 172, 165, 180, 150)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    val weights = intArrayOf(45, 68, 70, 101, 52)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        val bmi = (weights[i] * 10000).toDouble() / (heights[i] * heights[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        val category = when {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `            bmi < 18.5 -> "underweight"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            bmi < 25 -> "normal"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            bmi < 30 -> "overweight"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `        println("%s: BMI %.1f (%s)".format(Locale.ROOT, names[i], bmi, category))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **253 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **301 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L4: 218 tokens (versus 253); removes `val names = listOf("Aiko", "Kenji", "Mika", "Ryo", "Yuki")`.
- Without L5: 217 tokens (versus 253); removes `val heights = intArrayOf(158, 172, 165, 180, 150)`.
- Without L6: 221 tokens (versus 253); removes `val weights = intArrayOf(45, 68, 70, 101, 52)`.
- Without L8: 209 tokens (versus 253); removes `val bmi = (weights[i] * 10000).toDouble() / (heights[i] * heights[i])`.
- Without L9: 241 tokens (versus 253); removes `val category = when {`.
- Without L10: 235 tokens (versus 253); removes `bmi < 18.5 -> "underweight"`.
- Without L11: 237 tokens (versus 253); removes `bmi < 25 -> "normal"`.
- Without L12: 237 tokens (versus 253); removes `bmi < 30 -> "overweight"`.
- Without L14: 249 tokens (versus 253); removes `}`.
- Without L15: 213 tokens (versus 253); removes `println("%s: BMI %.1f (%s)".format(Locale.ROOT, names[i], bmi, category))`.
