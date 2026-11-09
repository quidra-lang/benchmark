For -456789 the output is "-456,789". The named sign decision is kept apart from absolute-value decimal digits. Group boundaries count from the right in threes; the sign is attached only outside the digit grouping and no comma is left at either endpoint.

Reversing magnitude digits lets gsub append commas per three digits; reversing back and stripping ^, removes a possible leading comma. The independent negative flag prepends the sign.

The sign binding, absolute digits, grouping boundary and final attachment are each necessary to exclude sign grouping. A positive-only formatting example would not establish the negative path.
