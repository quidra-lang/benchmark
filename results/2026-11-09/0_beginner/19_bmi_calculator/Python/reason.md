# Task B selection: 19_bmi_calculator / Python

## Answer requirements

Suppose a new person record has height 0 and must produce name: invalid height instead of a BMI line. Explain how to insert the validation so it controls entry to the integer numerator/denominator calculation, real division, classification and formatting stages. Identify how the invalid path bypasses those stages while the five valid records keep their existing order and unrounded-BMI classification. Use the source's actual record access and output structure.

## Answer and source evidence

Add the new tuple record to the people collection. Immediately after destructuring name,height,weight and before any BMI division, test height==0; on that path emit `name: invalid height` and continue to the next record. The valid path retains weight*10000 divided by height squared, classifies the unrounded value at 18.5,25,30, then formats one decimal. Sequential iteration keeps the five existing records in order. The selected record construction, binding, dependent calculations, category choices and output collectively identify the required bypass and unchanged path.



Selected `main.py` lines: 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
