For -456789 the output is "-456,789". The named sign decision is kept apart from absolute-value decimal digits. Group boundaries count from the right in threes; the sign is attached only outside the digit grouping and no comma is left at either endpoint.

The output buffer receives the sign before traversal. The guard i>0 forbids a comma immediately after it; (digits.length-i)%3==0 inserts only before a subsequent digit. writeln and stdout.write complete the line.

The sign binding, absolute digits, grouping boundary and final attachment are each necessary to exclude sign grouping. A positive-only formatting example would not establish the negative path.
