When no zero-indegree untaken candidate exists, selection terminates before any removal or selected-course update. Remaining untaken courses then form the alphabetically sorted cycle data; if every course was taken, that remainder is empty instead. The stop condition is candidate availability, not a requirement that all courses were consumed.

until ready.empty? guards shift, so it never removes from an empty queue. The returned (courses-order).sort becomes cycle through the list-2 call and is joined in the cycle output.

Candidate construction, empty-candidate stop, selected removal and untaken sorted output establish partial topological progress and cycle reporting. No cycle-search implementation is required beyond that remainder.
