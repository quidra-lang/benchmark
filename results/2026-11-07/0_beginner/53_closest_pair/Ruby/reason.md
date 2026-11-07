Keep pair selection on integer squared distance and change only the reported quantity: emit that stored integer directly instead of sqrt(...), removing fixed-four-fraction formatting. Closest/farthest choices and lexicographically first tied pairs remain unchanged because increasing i,j traversal and strict comparisons are unchanged.

closest/farthest retain [squared,i,j]; strict < and > never replace ties. Change %.4f and Math.sqrt(squared) at the shared two-result formatter, retaining labels and pair indices.

The squared-distance selection and output square-root/precision sites separate ranking from display. Other geometric calculations would not change the strictly increasing transformation.
