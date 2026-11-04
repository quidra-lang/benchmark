# Task B selection — 91_priority_queue_tasks / C

## Common answer requirements

Locate the equal-priority comparison, preserve priority as the primary key and apply the same new alphabetical tie-break to run and the final drain.

## Source evidence

The comparison currently uses ascending priority then insertion order. Change its equal-priority arm to compare task names lexicographically. The insertion call and push comparison show that tasks enter this heap under the same comparison that pop uses. Both the run handler and the final loop pop from that heap.

## Minimization

Selected complete lines of `main.c`: L5, L9, L10, L13, L17, L25, L31, L33, L50, L51, L57, L61, L62. The insertion and both removal sites tie the edited helper to the actual heap operations. Command strings and print formatting have no separate tie-break to change.

The selected excerpt measures **267 tokens** with `metric/tokenizer.py`.
