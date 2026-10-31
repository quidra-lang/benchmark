# Task B selection: 19_bmi_calculator / Quidra

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.

The explicit real64 conversions occur after integer numerator/denominator calculation. Category retains the unrounded real value and frac=1 affects only the display.

The selected expression or branch boundary completes category selection before the formatted output. The comparisons consume the unrounded BMI; the output alone requests one decimal place.

Source: `main.qui`. Selected original lines: 1,2,3,5,6,7,8,9,10,11,13,14. The following original-line dependencies support the answer above:

- L1: `string[] names = ["Aiko", "Kenji", "Mika", "Ryo", "Yuki"]` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L2: `int[] heights = [158, 172, 165, 180, 150]` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L3: `int[] weights = [45, 68, 70, 101, 52]` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L5: `    int numerator = weights[index] * 10000` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L6: `    int denominator = heights[index] * heights[index]` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L7: `    real64 bmi = real64(numerator) / real64(denominator)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L8: `    string category = (` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L9: `        if bmi < 18.5 then "underweight"` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L10: `        elif bmi < 25.0 then "normal"` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L11: `        elif bmi < 30.0 then "overweight"` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L13: `    )` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L14: `    print("{names[index]}: BMI {bmi:frac=1} ({category}){NL}")` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.

## Minimization and semantics

The selected excerpt measures **254 tokens** with `metric/tokenizer.py` `tokenize`; the complete original source is a sufficient alternative of **276 tokens**. Complete original lines and their order are preserved, and no source location is repeated. Excerpts are evidence fragments and need not compile independently. Standard arithmetic, collection, regex, formatting and iteration operations use their language/library semantics. User helper behavior is established by its retained operations.

The smaller deletion alternatives below were measured. Each drops the identified dependency or boundary from this concrete answer. This review establishes a sufficient minimized dependency set, without claiming a global mathematical minimum.

- Without L1: 221 tokens (versus 254); removes `string[] names = ["Aiko", "Kenji", "Mika", "Ryo", "Yuki"]`.
- Without L2: 221 tokens (versus 254); removes `int[] heights = [158, 172, 165, 180, 150]`.
- Without L3: 225 tokens (versus 254); removes `int[] weights = [45, 68, 70, 101, 52]`.
- Without L5: 234 tokens (versus 254); removes `int numerator = weights[index] * 10000`.
- Without L6: 235 tokens (versus 254); removes `int denominator = heights[index] * heights[index]`.
- Without L7: 235 tokens (versus 254); removes `real64 bmi = real64(numerator) / real64(denominator)`.
- Without L8: 245 tokens (versus 254); removes `string category = (`.
- Without L9: 235 tokens (versus 254); removes `if bmi < 18.5 then "underweight"`.
- Without L10: 235 tokens (versus 254); removes `elif bmi < 25.0 then "normal"`.
- Without L11: 235 tokens (versus 254); removes `elif bmi < 30.0 then "overweight"`.
- Without L13: 251 tokens (versus 254); removes `)`.
- Without L14: 222 tokens (versus 254); removes `print("{names[index]}: BMI {bmi:frac=1} ({category}){NL}")`.
