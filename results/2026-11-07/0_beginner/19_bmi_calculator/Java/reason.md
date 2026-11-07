# Task B selection: 19_bmi_calculator / Java

Add the zero-height check immediately inside the indexed person loop, using heights[i] and names[i], before weights[i]*10000 and heights[i]*heights[i] feed real division. Emit name: invalid height and skip the BMI/classification/formatting path for that record. The existing array/index order and unrounded bmi thresholds remain applicable to the five valid records.

The parallel input fields, iteration and BMI-to-category-to-output block identify every stage guarded by the change; no other source operation participates.

Selected complete source lines in `Main.java`: 5, 6, 7, 8, 9, 10, 11. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
