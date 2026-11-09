Replace the equal-priority insertion-sequence tie-break with ascending task name. The six run lines become deploy(1), test(2), email(3), review(2), build(1), lint(3), each in the existing "run: name (priority p)" format. The remaining line becomes "remaining: report docs backup cleanup". The final list must drain with the same comparator as ordinary run removal.

Array tuple comparison currently orders [priority,sequence,name]. Reorder the tuple to [priority,name,...] and update pop destructuring and the final name index consistently. Both push and pop compare tuples, and the final list repeatedly pops.

The priority/name/sequence comparator, command order, run removal and final drain connect every changed tie to output. A queue insertion-only excerpt would miss inconsistent remaining-order rendering.
