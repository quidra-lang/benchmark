Append 2400 after 2100 in the input collection. The ordered traversal reaches it ninth; divisibility by 400 makes it leap, producing "2400: leap year". No earlier element or per-year calculation changes, so the original eight lines retain order and meaning.

ipairs traverses the contiguous literal in order; the named leap decision uses the 400 rule before the 4/100 rule; %04d and %s define the line.

The input order, traversal, leap predicate and output connect the appended year to its ninth line. There is no need to reproduce computations for the eight unaffected years.
