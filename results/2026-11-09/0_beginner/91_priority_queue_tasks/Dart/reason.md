Replace the equal-priority insertion-sequence tie-break with ascending task name. The six run lines become deploy(1), test(2), email(3), review(2), build(1), lint(3), each in the existing "run: name (priority p)" format. The remaining line becomes "remaining: report docs backup cleanup". The final list must drain with the same comparator as ordinary run removal.

before compares Task priority then sequence; change the second clause to name.compareTo(...). Heap push/pop share it, Task names remain available and final remaining uses repeated heap.pop, keeping both paths aligned.

The priority/name/sequence comparator, command order, run removal and final drain connect every changed tie to output. A queue insertion-only excerpt would miss inconsistent remaining-order rendering.
