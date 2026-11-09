After undo and redo are excluded, the type-prefix test recognizes "type hello world" and takes its entire remaining payload, retaining the internal space. The other valid edit command "delete 5" takes its decimal remainder, converts it to 5 and shortens the buffer with a lower bound of zero.

startsWith("type ") selects substring(5); the delete fallback uses int.parse(substring(7)) and substring(0,max(0,current.length-n)). Splitting into individual words would lose the type payload space and is unnecessary.

The dispatch order and payload slicing/conversion establish type versus delete handling. History mechanics and full command logs do not determine the two payload values.
