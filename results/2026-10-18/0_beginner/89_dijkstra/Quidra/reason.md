# Task B selection for 89_dijkstra

Change the start index from A (0) to G (6). The selected declarations
and assignments establish the unreached and predecessor sentinels and show
that one start index seeds both the zero distance and the ready mask.

The output loop initializes the predecessor walk from each destination in
A-to-G order. The walk collects names until the sentinel and the output line
reverses them. The start retains the predecessor sentinel, so the G line
contains just G with distance zero. These same evidence requirements apply to
the Python selection. Graph construction, relaxation, and path allocation
are outside the requested change and add no necessary evidence.

Selected complete lines in order are 3, 9, 10, 12, 13, 14, 28, 30, 31, 32, 33, 34.
Task A uses 541 tokens. Task B uses 170 tokens.
