Count uppercase and lowercase keys separately: the sentence contains P twice and lowercase p seven times, replacing their combined count nine. Remove lowercasing, filter both ASCII letter ranges, and emit occurring A..Z keys before a..z; spaces and ! still fail the letter filter.

List.filled(26,0), toLowerCase and c-97 indexing must agree on a case-preserving storage scheme. Extend the filter to 65..90 too, count separate slots, and emit uppercase then lowercase with matching character conversion.

Normalization, letter filtering, frequency keys and ordered output must be visible together: changing lowercasing alone would still exclude uppercase letters or print them in the wrong order.
