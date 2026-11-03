# Task B selection: 19_bmi_calculator / Zig

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.

The final else and expression terminator complete the multiline category expression before formatted output. They establish that output consumes the category selected by the unrounded threshold chain; this case selects the preceding overweight arm.

Source: `main.zig`. Selected original lines: 8,11,15,16,17,18,19,20,21,22,23,24,25. The following original-line dependencies support the answer above:

- L8: `    const people = [_]Person{` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L11: `        .{ .name = "Mika", .height = 165, .weight = 70 },` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L15: `    for (people) |p| {` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L16: `        const bmi = @as(f64, @floatFromInt(p.weight * 10000)) / @as(f64, @floatFromInt(p.height * p.height));` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L17: `        const category: []const u8 = if (bmi < 18.5)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L18: `            "underweight"` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L19: `        else if (bmi < 25)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L20: `            "normal"` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L21: `        else if (bmi < 30)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L22: `            "overweight"` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L23: `        else` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L24: `            "obese";` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L25: `        try out.print("{s}: BMI {d:.1} ({s})\n", .{ p.name, bmi, category });` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.

## Minimization and semantics

The selected excerpt measures **259 tokens** with `metric/tokenizer.py` `tokenize`; the complete original source is a sufficient alternative of **560 tokens**. Complete original lines and their order are preserved, and no source location is repeated. Excerpts are evidence fragments and need not compile independently. Standard arithmetic, collection, regex, formatting and iteration operations use their language/library semantics. User helper behavior is established by its retained operations.

The smaller deletion alternatives below were measured. Each drops the identified dependency or boundary from this concrete answer. This review establishes a sufficient minimized dependency set, without claiming a global mathematical minimum.

- Without L8: 246 tokens (versus 259); removes `const people = [_]Person{`.
- Without L11: 223 tokens (versus 259); removes `.{ .name = "Mika", .height = 165, .weight = 70 },`.
- Without L15: 246 tokens (versus 259); removes `for (people) |p| {`.
- Without L16: 200 tokens (versus 259); removes `const bmi = @as(f64, @floatFromInt(p.weight * 10000)) / @as(f64, @floatFromInt(p.height * p.height));`.
- Without L17: 232 tokens (versus 259); removes `const category: []const u8 = if (bmi < 18.5)`.
- Without L18: 252 tokens (versus 259); removes `"underweight"`.
- Without L19: 244 tokens (versus 259); removes `else if (bmi < 25)`.
- Without L20: 252 tokens (versus 259); removes `"normal"`.
- Without L21: 244 tokens (versus 259); removes `else if (bmi < 30)`.
- Without L22: 252 tokens (versus 259); removes `"overweight"`.
- Without L23: 255 tokens (versus 259); removes `else`.
- Without L24: 251 tokens (versus 259); removes `"obese";`.
- Without L25: 211 tokens (versus 259); removes `try out.print("{s}: BMI {d:.1} ({s})\n", .{ p.name, bmi, category });`.
