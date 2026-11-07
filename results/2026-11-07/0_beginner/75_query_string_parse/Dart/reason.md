Decode each key and value before testing value membership for that decoded key. When &page=%32 is appended to query 2, it decodes to the already retained "2" and must be skipped, leaving page values "2", "3" in first-appearance order. New distinct values and the single empty value remain valid; sorted-key output is unchanged.

Uri.decodeQueryComponent and split/indexOf preserve first-equals handling and empty values. putIfAbsent(...).add(value) is the affected accumulation site; add only if the decoded per-key list does not contain value, retaining keys.sort and mapped quoting.

Percent/plus decoding, decoded-key insertion, value-list append and output ordering locate deduplication after decoding. Deduplicating raw encodings would fail the appended %32 case.
