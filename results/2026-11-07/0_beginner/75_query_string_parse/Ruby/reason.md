Decode each key and value before testing value membership for that decoded key. When &page=%32 is appended to query 2, it decodes to the already retained "2" and must be skipped, leaving page values "2", "3" in first-appearance order. New distinct values and the single empty value remain valid; sorted-key output is unchanged.

URI.decode_www_form returns decoded string pairs, including empty values. The key/value block currently appends every pair; add a membership check (or ordered uniq at each value list) before display. The hash and keys.sort distinguish value order from key output order.

Percent/plus decoding, decoded-key insertion, value-list append and output ordering locate deduplication after decoding. Deduplicating raw encodings would fail the appended %32 case.
