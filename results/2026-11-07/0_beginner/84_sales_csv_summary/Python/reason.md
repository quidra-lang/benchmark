# Task B selection: 84_sales_csv_summary / Python

## Answer requirements

Suppose quantity is accidentally retained as the CSV string "10" for the first notebook row. In the local row-processing block, identify where and how to establish its exact integer value before sales multiplication and product-quantity accumulation. Explain whether the current conversions already prevent the problem, which nearby fields stay textual and how the sales amount and quantity take different aggregation paths. Distinguish runtime conversion from a declared type guarantee.

## Answer and source evidence

The present source already converts quantity "10" and unit price "200" to exact integers before multiplication, producing sales2000 and quantity10. Date, region and product remain textual fields. Sales enters total, region and day amounts; quantity separately enters the product count. Retain/add int conversion at that row-ingestion site, never after multiplying or aggregating a string.

Python int performs runtime conversion and rebinding, not a static integer declaration; source strings would otherwise have different multiplication/addition behavior.

Selected `main.py` lines: 21, 22, 23, 24, 25, 26, 27. All selected lines are copied verbatim in source order.

## Language semantics and minimization

Ordinary lexical scope, evaluation order and the documented semantics of the selected standard-library operations are available as language knowledge. The selected declarations establish the values or contracts actually needed by this question; the selected operations establish the relevant data or control dependencies. Unrelated cases, separate output fields and unused helpers are excluded. Closing delimiters and blank lines are included only when they share a required physical source line. A different implementation of the proposed change is not evidence about the existing program and is not part of this excerpt. This selection is a source review under the Task B assumptions, not a claim that the program was compiled or executed.
