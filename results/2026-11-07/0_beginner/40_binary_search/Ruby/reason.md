The first bounds are 0 and 15, so the midpoint is 7 and the read element is 31, the eighth element. The recorded probe is the midpoint index 7, not value 31 or ordinal 8.

Integer (lo+hi)/2 returns 7; probes << mid records that index and values[mid] uses zero-based Array indexing.

Initial bounds, midpoint/probe assignment and the referenced input element determine the first read and its zero-based index. Later binary-search decisions cannot affect the first probe.
