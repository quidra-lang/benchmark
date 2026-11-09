# Task B: 19_bmi_calculator / J

After retrieving a person and before dividing by height squared, test height==0. On that branch emit `name: invalid height` and continue to the next record; otherwise run the existing BMI calculation, classification on the unrounded BMI, and formatted output. The guard must control entry to all these stages, not merely replace a formatted infinity afterward. Sequential traversal keeps the five existing valid records in order.

The parallel name/height/weight arrays and for index establish the record. Test the retrieved height before bmi; use index{::names for the error label and continue. before the current classification/output block.

Evidence is from `main.ijs`, L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13.

- L2: `names =. ;:'Aiko Kenji Mika Ryo Yuki'`
- L3: `heights =. 158 172 165 180 150`
- L4: `weights =. 45 68 70 101 52`
- L5: `for_index. i.5 do.`
- L6: `height =. index{heights`
- L7: `bmi =. ((index{weights)*10000) % height*height`
- L8: `category =. 'obese'`
- L9: `if. bmi<18.5 do. category =. 'underweight'`
- L10: `elseif. bmi<25 do. category =. 'normal'`
- L11: `elseif. bmi<30 do. category =. 'overweight'`
- L12: `end.`
- L13: `smoutput (>index{names), ': BMI ', (, '1' 8!:2 bmi), ' (', category, ')'`

Minimization: The record layout/access, division, classification and one output block are necessary to identify where validation controls later consumers. No separate trace of valid BMI values is needed. The selected complete original lines, in source order, cost 224 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 224, and the complete source costs 244. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
