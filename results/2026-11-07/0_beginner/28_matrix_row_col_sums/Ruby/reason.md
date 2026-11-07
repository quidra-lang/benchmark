Replace row/column/grand additions with maxima and seed from actual entries (or a valid low identity), preserving all matrix entries and six-character fields. The first row summary becomes 912. The final row values become 947,765,819,912,720,947; there are still five lines with six fields each.

row_sum names the row aggregation; transpose.map(&:sum) and columns.sum are the other aggregation sites. Change their reductions to max while retaining row concatenation, %6d, join and puts.

The matrix, row/column/grand accumulation sites and width-six renderer establish both the changed operators and preserved table shape. A row-only excerpt would miss the final summary row.
