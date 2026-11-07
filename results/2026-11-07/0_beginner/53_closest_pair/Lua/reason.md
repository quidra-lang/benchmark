Keep pair selection on integer squared distance and change only the reported quantity: emit that stored integer directly instead of sqrt(...), removing fixed-four-fraction formatting. Closest/farthest choices and lexicographically first tied pairs remain unchanged because increasing i,j traversal and strict comparisons are unchanged.

nearest/farthest retain squared distance in cell 3 and zero-based pair IDs in cells 1,2. Replace math.sqrt(pair[3]) and %.4f with an integer field while retaining the two-item output loop.

The squared-distance selection and output square-root/precision sites separate ranking from display. Other geometric calculations would not change the strictly increasing transformation.
