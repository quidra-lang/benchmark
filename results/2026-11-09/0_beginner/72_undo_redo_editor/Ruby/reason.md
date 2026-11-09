After undo and redo are excluded, the type-prefix test recognizes "type hello world" and takes its entire remaining payload, retaining the internal space. The other valid edit command "delete 5" takes its decimal remainder, converts it to 5 and shortens the buffer with a lower bound of zero.

start_with?("type ") selects command[5..] using zero-based index 5; delete uses command[7..].to_i and max(0,buffer.length-count). The buffer update consumes the parsed value directly.

The dispatch order and payload slicing/conversion establish type versus delete handling. History mechanics and full command logs do not determine the two payload values.
