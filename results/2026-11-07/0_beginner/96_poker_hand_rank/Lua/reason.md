Ordinary ranks encode T as 10 and A as 14. The ace-low special case recognizes exactly A,2,3,4,5 and uses comparison sequence [5,4,3,2,1], treating ace as 1 there. Ordinary ace-high hands retain ace 14 in their frequency/rank-ordered sequence. These rank values are separate from the final one-based printed hand position.

The one-based alphabet find plus 1 gives 2..14. Ascending distinct values establish wheel detection; the comparator orders ordinary ranks by count then descending value, and the special sequence replaces ace-high order. position is independently supplied by ipairs.

Rank conversion, ace-low recognition/comparison sequence, rank ordering and final printed position distinguish rank 1/14 from report ordinal. Other hand-category branches cannot change the ace-low mapping.
