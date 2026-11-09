When no zero-indegree untaken candidate exists, selection terminates before any removal or selected-course update. Remaining untaken courses then form the alphabetically sorted cycle data; if every course was taken, that remainder is empty instead. The stop condition is candidate availability, not a requirement that all courses were consumed.

best is nullable and filled only by the untaken/zero-indegree condition; best==null breaks before taken[best]. The later collection filters !taken and sorts before the cycle line.

Candidate construction, empty-candidate stop, selected removal and untaken sorted output establish partial topological progress and cycle reporting. No cycle-search implementation is required beyond that remainder.
