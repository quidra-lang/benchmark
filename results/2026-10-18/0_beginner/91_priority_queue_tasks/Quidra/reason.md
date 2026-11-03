# Task B selection: 91_priority_queue_tasks / Quidra

The question requires a numeric-primary, alphabetical-name-secondary comparator shared by both run removals and the final remaining list, without changing operation data or formatting. The selected Collections import and PriorityQueue<string, int> constructor establish the value/priority types and default contract. The push maps fields[1] to the string task value and parsed fields[2] to numeric priority. Both take consumers use this same queue; the while guard, remaining push and output establish that the final list is repeated removal order.

Collections README at pinned commit 8088abdd898dd833821b5e0a12261418611e2610 documents smaller priorities first, insertion-order default ties, and the constructor's capture-free tie_before comparator over values. Supply a pure strict alphabetical string comparator there; smaller numeric priorities remain primary, and both removal paths automatically use the new tie rule. The comparator is fixed at construction, so no later reassignment is implied. No new library API or capture of local state is assumed.

Operation iteration, splitting, add guarding and run formatting are unchanged parsing/display details; the retained push and take lines already identify the queue boundaries and data roles. The original larger excerpt is sufficient but adds those unrelated details. Dropping the constructor would lose the shared configuration boundary; dropping the push would lose value/priority mapping; dropping the final drain would lose evidence that remaining uses removals from the same configured queue. This is the previously reviewed 126-token scope candidate.

Selected complete main.qui lines: 1, 8, 12, 14, 17, 18, 19, 20. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py: Task A **339** tokens; Task B **126** tokens. These are source-token measures. This is a minimized sufficient selection among the reviewed alternatives, not a proof of a global minimum. Native compiler/output checks are recorded separately in validation.json.
