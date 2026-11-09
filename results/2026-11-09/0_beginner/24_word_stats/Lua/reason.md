Keep total word characters and word count as exact integer operands, but ensure their quotient is real when porting to integer-truncating division. The present expression already uses real division; a port must preserve that operation or convert an operand before division, rather than rounding afterwards.

The zero total, per-word #word update and #words denominator identify exact counts. / is real division, unlike //; the port must retain that distinction.

The character total and word-count division establish the numeric operation that must stay real. Longest/shortest-word processing cannot affect this quotient.
