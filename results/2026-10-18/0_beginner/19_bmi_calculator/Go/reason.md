# Task B selection: 19_bmi_calculator / Go

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.

The struct field order name,h,w establishes165 as height and70 as weight. Explicit float64 conversions make division real. Only the false thresholds and selected overweight assignment are needed for this case.

The selected expression or branch boundary completes category selection before the formatted output. The comparisons consume the unrounded BMI; the output alone requests one decimal place.

Source: `main.go`. Selected original lines: 6,7,8,9,10,11,12,14,16,18,19,20,21. The following original-line dependencies support the answer above:

- L6: `	people := []struct {` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L7: `		name string` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L8: `		h, w int` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L9: `	}{{"Aiko", 158, 45}, {"Kenji", 172, 68}, {"Mika", 165, 70}, {"Ryo", 180, 101}, {"Yuki", 150, 52}}` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L10: `	for _, p := range people {` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L11: `		numerator, denominator := p.w*10000, p.h*p.h` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L12: `		bmi := float64(numerator) / float64(denominator)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L14: `		if bmi < 18.5 {` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L16: `		} else if bmi < 25 {` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L18: `		} else if bmi < 30 {` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L19: `			category = "overweight"` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L20: `		}` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L21: `		fmt.Printf("%s: BMI %.1f (%s)\n", p.name, bmi, category)` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.

## Minimization and semantics

The selected excerpt measures **271 tokens** with `metric/tokenizer.py` `tokenize`; the complete original source is a sufficient alternative of **328 tokens**. Complete original lines and their order are preserved, and no source location is repeated. Excerpts are evidence fragments and need not compile independently. Standard arithmetic, collection, regex, formatting and iteration operations use their language/library semantics. User helper behavior is established by its retained operations.

The smaller deletion alternatives below were measured. Each drops the identified dependency or boundary from this concrete answer. This review establishes a sufficient minimized dependency set, without claiming a global mathematical minimum.

- Without L6: 261 tokens (versus 271); removes `people := []struct {`.
- Without L7: 265 tokens (versus 271); removes `name string`.
- Without L8: 262 tokens (versus 271); removes `h, w int`.
- Without L9: 187 tokens (versus 271); removes `}{{"Aiko", 158, 45}, {"Kenji", 172, 68}, {"Mika", 165, 70}, {"Ryo", 180, 101}, {"Yuki", 150, 52}}`.
- Without L10: 255 tokens (versus 271); removes `for _, p := range people {`.
- Without L11: 243 tokens (versus 271); removes `numerator, denominator := p.w*10000, p.h*p.h`.
- Without L12: 253 tokens (versus 271); removes `bmi := float64(numerator) / float64(denominator)`.
- Without L14: 256 tokens (versus 271); removes `if bmi < 18.5 {`.
- Without L16: 254 tokens (versus 271); removes `} else if bmi < 25 {`.
- Without L18: 254 tokens (versus 271); removes `} else if bmi < 30 {`.
- Without L19: 260 tokens (versus 271); removes `category = "overweight"`.
- Without L20: 267 tokens (versus 271); removes `}`.
- Without L21: 235 tokens (versus 271); removes `fmt.Printf("%s: BMI %.1f (%s)\n", p.name, bmi, category)`.
