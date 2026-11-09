Keep pair selection on integer squared distance and change only the reported quantity: emit that stored integer directly instead of sqrt(...), removing fixed-four-fraction formatting. Closest/farthest choices and lexicographically first tied pairs remain unchanged because increasing i,j traversal and strict comparisons are unchanged.

d is the integer sum of squares; strict improvement updates pair and best together. Replace the two math.sqrt(...).toStringAsFixed(4) fragments with nearest/farthest integer interpolation; labels and pair fields stay as written.

The squared-distance selection and output square-root/precision sites separate ranking from display. Other geometric calculations would not change the strictly increasing transformation.
