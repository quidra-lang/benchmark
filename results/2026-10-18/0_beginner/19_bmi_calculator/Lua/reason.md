# Task B selection: 19_bmi_calculator / Lua

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.



Source: `main.lua`. Selected original lines: 1-6. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `local people = {{"Aiko", 158, 45}, {"Kenji", 172, 68}, {"Mika", 165, 70}, {"Ryo", 180, 101}, {"Yuki", 150, 52}}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `for _, person in ipairs(people) do` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    local name, height, weight = person[1], person[2], person[3]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    local bmi = (weight * 10000) / (height * height)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    local category = bmi < 18.5 and "underweight" or bmi < 25 and "normal" or bmi < 30 and "overweight" or "obese"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    io.write(string.format("%s: BMI %.1f (%s)\n", name, bmi, category))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **259 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **261 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 171 tokens (versus 259); removes `local people = {{"Aiko", 158, 45}, {"Kenji", 172, 68}, {"Mika", 165, 70}, {"Ryo", 180, 101}, {"Yuki", 150, 52}}`.
- Without L2: 243 tokens (versus 259); removes `for _, person in ipairs(people) do`.
- Without L3: 229 tokens (versus 259); removes `local name, height, weight = person[1], person[2], person[3]`.
- Without L4: 230 tokens (versus 259); removes `local bmi = (weight * 10000) / (height * height)`.
- Without L5: 201 tokens (versus 259); removes `local category = bmi < 18.5 and "underweight" or bmi < 25 and "normal" or bmi < 30 and "overweight" or "obese"`.
- Without L6: 221 tokens (versus 259); removes `io.write(string.format("%s: BMI %.1f (%s)\n", name, bmi, category))`.
