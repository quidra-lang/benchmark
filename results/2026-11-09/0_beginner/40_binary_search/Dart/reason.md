The first bounds are 0 and 15, so the midpoint is 7 and the read element is 31, the eighth element. The recorded probe is the midpoint index 7, not value 31 or ordinal 8.

The explicit initial bounds and ~/2 give 7. out.write records mid and a[mid] reads the zero-based list element; the lower/upper update branches are unnecessary.

Initial bounds, midpoint/probe assignment and the referenced input element determine the first read and its zero-based index. Later binary-search decisions cannot affect the first probe.
