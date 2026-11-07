# Task B: 19_bmi_calculator / R

After retrieving a person and before dividing by height squared, test height==0. On that branch emit `name: invalid height` and continue to the next record; otherwise run the existing BMI calculation, classification on the unrounded BMI, and formatted output. The guard must control entry to all these stages, not merely replace a formatted infinity afterward. Sequential traversal keeps the five existing valid records in order.

The loop reads people$height[i] and the corresponding name. Guard before bmi division, then next skips category selection and sprintf on the invalid path.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10.

- L1: `people <- data.frame(`
- L2: `name = c("Aiko", "Kenji", "Mika", "Ryo", "Yuki"),`
- L3: `height = c(158L, 172L, 165L, 180L, 150L), weight = c(45L, 68L, 70L, 101L, 52L)`
- L4: `)`
- L5: `for (i in seq_len(nrow(people))) {`
- L6: `height <- people$height[i]`
- L7: `weight <- people$weight[i]`
- L8: `bmi <- (weight * 10000L) / (height * height)`
- L9: `category <- if (bmi < 18.5) "underweight" else if (bmi < 25) "normal" else if (bmi < 30) "overweight" else "obese"`
- L10: `cat(sprintf("%s: BMI %.1f (%s)\n", people$name[i], bmi, category))`

Minimization: The record layout/access, division, classification and one output block are necessary to identify where validation controls later consumers. No separate trace of valid BMI values is needed. The selected complete original lines, in source order, cost 287 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 287, and the complete source costs 289. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
