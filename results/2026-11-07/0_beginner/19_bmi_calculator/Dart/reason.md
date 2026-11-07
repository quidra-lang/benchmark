Insert a height==0 guard immediately after accessing each record and before the BMI numerator/denominator expression. That path prints "name: invalid height" and skips division, classification and normal formatting. The existing ordered traversal and unrounded BMI comparisons remain the path for all five valid records.

The record fields p.$1, p.$2, p.$3 represent name,height,weight. A guard and continue before bmi bypass all later stages; the switch still uses the raw double and toStringAsFixed(1) remains display-only.

Record access and the first BMI division locate the guard; classification/output identify what the invalid path must skip. Traversal and data establish that valid records retain their existing order.
