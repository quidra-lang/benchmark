After undo and redo are excluded, the type-prefix test recognizes "type hello world" and takes its entire remaining payload, retaining the internal space. The other valid edit command "delete 5" takes its decimal remainder, converts it to 5 and shortens the buffer with a lower bound of zero.

sub(1,5)=="type " selects sub(6), the complete one-based remainder. The delete fallback parses sub(8) with tonumber, then computes the bounded retained prefix.

The dispatch order and payload slicing/conversion establish type versus delete handling. History mechanics and full command logs do not determine the two payload values.
