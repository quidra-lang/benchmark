# Task B: 19_bmi_calculator / Julia

After retrieving a person and before dividing by height squared, test height==0. On that branch emit `name: invalid height` and continue to the next record; otherwise run the existing BMI calculation, classification on the unrounded BMI, and formatted output. The guard must control entry to all these stages, not merely replace a formatted infinity afterward. Sequential traversal keeps the five existing valid records in order.

The loop destructures each (name,height,weight) tuple. Place the height guard before the bmi assignment and use name for the invalid line.

Evidence is from `main.jl`, L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13.

- L3: `for (name, height, weight) in [`
- L4: `("Aiko", 158, 45),`
- L5: `("Kenji", 172, 68),`
- L6: `("Mika", 165, 70),`
- L7: `("Ryo", 180, 101),`
- L8: `("Yuki", 150, 52),`
- L9: `]`
- L10: `bmi = (weight * 10000) / (height * height)`
- L11: `category =`
- L12: `bmi < 18.5 ? "underweight" : bmi < 25 ? "normal" : bmi < 30 ? "overweight" : "obese"`
- L13: `@printf("%s: BMI %.1f (%s)\n", name, bmi, category)`

Minimization: The record layout/access, division, classification and one output block are necessary to identify where validation controls later consumers. No separate trace of valid BMI values is needed. The selected complete original lines, in source order, cost 221 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 221, and the complete source costs 228. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
