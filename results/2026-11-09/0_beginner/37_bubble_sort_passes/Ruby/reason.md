The first pass moves 88 right past 41,5,72,36 into the final slot. Later passes shrink the compared suffix; the final array is 5 13 27 36 41 64 72 88. Passes contain 5,4,2,2,1,0 swaps, totaling 14; pass 6 is printed before its no-swap decision terminates.

changed resets per pass, the exclusive inner range stops before the sorted suffix, simultaneous assignment swaps adjacent entries, and output precedes break unless changed.

Initial data, shrinking pass bounds, swaps, printed trace and post-print early exit establish both total swaps and the visible final zero-swap pass. A sorted-result-only excerpt would miss the pass count.
