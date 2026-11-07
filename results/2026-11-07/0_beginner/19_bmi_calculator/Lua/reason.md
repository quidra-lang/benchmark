Insert a height==0 guard immediately after accessing each record and before the BMI numerator/denominator expression. That path prints "name: invalid height" and skips division, classification and normal formatting. The existing ordered traversal and unrounded BMI comparisons remain the path for all five valid records.

The person[1..3] access supplies name,height,weight. Wrap the BMI/classification/format block in the valid branch, with the invalid branch printing name; ipairs preserves current order.

Record access and the first BMI division locate the guard; classification/output identify what the invalid path must skip. Traversal and data establish that valid records retain their existing order.
