# Task B selection: 19_bmi_calculator / C#

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.



Source: `Program.cs`. Selected original lines: 5-6,9-11. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `string[] names = { "Aiko", "Kenji", "Mika", "Ryo", "Yuki" };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `int[] heights = { 158, 172, 165, 180, 150 }, weights = { 45, 68, 70, 101, 52 };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    double bmi = (double)(weights[i] * 10000) / (heights[i] * heights[i]);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    string category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    Console.WriteLine($"{names[i]}: BMI {bmi:F1} ({category})");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **234 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **291 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 198 tokens (versus 234); removes `string[] names = { "Aiko", "Kenji", "Mika", "Ryo", "Yuki" };`.
- Without L6: 169 tokens (versus 234); removes `int[] heights = { 158, 172, 165, 180, 150 }, weights = { 45, 68, 70, 101, 52 };`.
- Without L9: 192 tokens (versus 234); removes `double bmi = (double)(weights[i] * 10000) / (heights[i] * heights[i]);`.
- Without L10: 175 tokens (versus 234); removes `string category = bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese";`.
- Without L11: 202 tokens (versus 234); removes `Console.WriteLine($"{names[i]}: BMI {bmi:F1} ({category})");`.
