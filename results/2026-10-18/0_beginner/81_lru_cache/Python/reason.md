# Task B selection: 81_lru_cache / Python

## Common answer requirements

Identify the miss-only capacity guard, tail eviction, and unconditional front insertion while retaining hit refresh.

## Source evidence

A membership hit removes the key’s old position. The else branch is a miss and pops the tail only at capacity. Change the miss guard from 3 to 4, keeping the tail removal and the front insertion shared by both branches.

## Minimization

The focused branch evidence establishes that the new capacity cannot evict on a hit and that all accesses refresh recency. Counters and formatting need no change. Selected complete lines of `main.py`: 4, 6, 8, 11, 12, 13.
