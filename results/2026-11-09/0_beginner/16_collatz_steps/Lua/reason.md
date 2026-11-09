Reorder only the output fields to "n: max=M steps=K", retaining one space after the colon and between fields and no spaces around equals signs. Existing maximum/peak supplies M and steps supplies K; original start/initial remains the line label.

The complete string.format line ties the current %d arguments to start, steps and peak; both template field order and the corresponding arguments must be reordered.

The existing output expression already identifies original input, maximum and steps. The unchanged Collatz loop is unnecessary for a field-order-only modification.
