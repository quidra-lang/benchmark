# Task B selection: 25_electricity_bill / Quidra

## Answer requirements

Connect the per-tier usage calculation, basic charge and bill-total accumulation for Suzuki at 120 kWh and Tanaka at 300 kWh. Derive each bill and identify the source decisions that allocate only the excess usage to the higher tier, rather than charging all usage at its highest reached rate. Show how each completed bill then enters the overall total without adding the basic charge a second time.

## Answer and source evidence

At 120 kWh the bill is 900+120*30=4500 yen. At 300 kWh it is 900+120*30+180*36=10980 yen. The min/max clamps or piecewise bounds allocate only the excess above 120 to tier two and none above 300 in these cases. Each bill starts with one 900-yen basic charge and enters total once through total += bill; total starts at zero, so the basic charge is not added again. Output formatting and the higher-than-300 branch are not needed for these two boundary inputs.



Selected `main.qui` lines: 3, 4, 5, 6, 7, 8, 9, 12. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
