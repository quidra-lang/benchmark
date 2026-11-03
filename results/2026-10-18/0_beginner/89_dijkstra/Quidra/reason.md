# Task B selection — 89_dijkstra / Quidra

Change the start index from 0 (A) to 6 (G). The same index initializes both distance zero and the ready mask. Its predecessor remains the sentinel, so following predecessors stops after collecting G. Reversing the collected names places G first. The output loop still walks the names in their fixed A-to-G order, and G has distance zero and a one-name path.

Selected complete source lines in order are 1, 3, 13, 15, 16, 17, 31, 33, 34, 35, 36, 37.

Tokenizer: Task A 600 tokens; Task B 154 tokens.
