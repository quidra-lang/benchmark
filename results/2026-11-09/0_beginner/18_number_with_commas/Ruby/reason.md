For -456789 the output is "-456,789". The named sign decision is kept apart from absolute-value decimal digits. Group boundaries count from the right in threes; the sign is attached only outside the digit grouping and no comma is left at either endpoint.

negative tests the original n; n.abs.to_s supplies only magnitude digits. The lookahead selects internal non-boundaries followed by complete triples, so the sign prefix cannot receive a comma.

The sign binding, absolute digits, grouping boundary and final attachment are each necessary to exclude sign grouping. A positive-only formatting example would not establish the negative path.
