For (4,8), the closed edge traversal yields four strict rightward crossings, so the revised line is "(4, 8): outside crossings=4". Keep the same strict y-side test and intersection>px rule; classify by parity of the same count used by the new suffix.

The integer crossings accumulator and %2 test already share one count. The i % #polygon + 1 access closes the polygon, / computes the real intersection, and the formatter gains the suffix argument.

Point/edge traversal, strict crossing conditions, parity classification and line output identify where to retain and report the same count. An independent intersection recomputation would be unnecessary.
