For (4,8), the closed edge traversal yields four strict rightward crossings, so the revised line is "(4, 8): outside crossings=4". Keep the same strict y-side test and intersection>px rule; classify by parity of the same count used by the new suffix.

inside currently stores parity alone. Replace it with an integer count initialized to zero and increment at the x>p.$1 site; derive the classification from count.isOdd and append that same count to print.

Point/edge traversal, strict crossing conditions, parity classification and line output identify where to retain and report the same count. An independent intersection recomputation would be unnecessary.
