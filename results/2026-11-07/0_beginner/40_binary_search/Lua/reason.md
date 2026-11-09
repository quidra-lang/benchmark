The first bounds are 0 and 15, so the midpoint is 7 and the read element is 31, the eighth element. The recorded probe is the midpoint index 7, not value 31 or ordinal 8.

The logical midpoint uses //2. It records mid unchanged but numbers[mid+1] translates to physical table position 8, preserving zero-based reported probes.

Initial bounds, midpoint/probe assignment and the referenced input element determine the first read and its zero-based index. Later binary-search decisions cannot affect the first probe.
