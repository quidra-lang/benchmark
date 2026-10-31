# Task B selection: 19_bmi_calculator / J

## Common answer requirements

Retrieve Mika’s height/weight, derive integer BMI numerator/denominator and real division; trace category thresholds on unrounded BMI and distinguish one-decimal half-up display from classification.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

Mika is165cm and70kg. The integer numerator is70×10000=700000 and denominator165²=27225. Floating-point/real division gives BMI≈25.7116620753. It is not below18.5 or25, but is below30, so category is overweight. The category tests use that unrounded bmi variable; the one-decimal formatting happens only at output, giving `Mika: BMI 25.7 (overweight)`. This concrete value is not a half-way tie, so half-up one-decimal rounding gives25.7 while preserving classification on the full value. The Task B assumptions apply to unchanged formatter requirements.

% is real division; right-to-left evaluation makes height*height its denominator. The fixed-format 8!:2 applies only in smoutput after the unrounded category comparison.

The selected expression or branch boundary completes category selection before the formatted output. The comparisons consume the unrounded BMI; the output alone requests one decimal place.

Source: `main.ijs`. Selected original lines: 2,3,4,5,6,7,9,10,11,12,13. The following original-line dependencies support the answer above:

- L2: `  names =. ;:'Aiko Kenji Mika Ryo Yuki'` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L3: `  heights =. 158 172 165 180 150` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L4: `  weights =. 45 68 70 101 52` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L5: `  for_index. i.5 do.` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L6: `    height =. index{heights` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L7: `    bmi =. ((index{weights)*10000) % height*height` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L9: `    if. bmi<18.5 do. category =. 'underweight'` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L10: `    elseif. bmi<25 do. category =. 'normal'` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L11: `    elseif. bmi<30 do. category =. 'overweight'` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.
- L12: `    end.` — This delimiter or branch boundary establishes the relevant control/expression scope.
- L13: `    smoutput (>index{names), ': BMI ', (, '1' 8!:2 bmi), ' (', category, ')'` — This line supplies the concrete input, state transition, condition, helper association, calculation, or output operation explained above.

## Minimization and semantics

The selected excerpt measures **215 tokens** with `metric/tokenizer.py` `tokenize`; the complete original source is a sufficient alternative of **244 tokens**. Complete original lines and their order are preserved, and no source location is repeated. Excerpts are evidence fragments and need not compile independently. Standard arithmetic, collection, regex, formatting and iteration operations use their language/library semantics. User helper behavior is established by its retained operations.

The smaller deletion alternatives below were measured. Each drops the identified dependency or boundary from this concrete answer. This review establishes a sufficient minimized dependency set, without claiming a global mathematical minimum.

- Without L2: 197 tokens (versus 215); removes `names =. ;:'Aiko Kenji Mika Ryo Yuki'`.
- Without L3: 190 tokens (versus 215); removes `heights =. 158 172 165 180 150`.
- Without L4: 194 tokens (versus 215); removes `weights =. 45 68 70 101 52`.
- Without L5: 204 tokens (versus 215); removes `for_index. i.5 do.`.
- Without L6: 206 tokens (versus 215); removes `height =. index{heights`.
- Without L7: 190 tokens (versus 215); removes `bmi =. ((index{weights)*10000) % height*height`.
- Without L9: 195 tokens (versus 215); removes `if. bmi<18.5 do. category =. 'underweight'`.
- Without L10: 197 tokens (versus 215); removes `elseif. bmi<25 do. category =. 'normal'`.
- Without L11: 197 tokens (versus 215); removes `elseif. bmi<30 do. category =. 'overweight'`.
- Without L12: 212 tokens (versus 215); removes `end.`.
- Without L13: 168 tokens (versus 215); removes `smoutput (>index{names), ': BMI ', (, '1' 8!:2 bmi), ' (', category, ')'`.
